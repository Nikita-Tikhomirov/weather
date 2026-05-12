"""
Project Bridge Server — persistent WebSocket server that manages deepseek-tui
sessions per project directory. Designed to run on the PC continuously.

Mobile app connects via WebSocket, triggers terminal launch, and
exchanges messages bidirectionally.

Usage: python project_bridge.py [--port 9876] [--host 0.0.0.0]
"""
import argparse
import asyncio
import json
import os
import re
import signal
import subprocess
import sys
import threading
from pathlib import Path
from typing import Optional, Dict

# Fix Windows Proactor event loop socket errors
if sys.platform == 'win32':
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

# ---------------------------------------------------------------------------
# ANSI escape code stripping
# ---------------------------------------------------------------------------
ANSI_RE = re.compile(r'\x1b\[[0-9;]*[a-zA-Z]|\x1b\].*?\x07|\x1b\[[0-9]+[A-K]')

def strip_ansi(text: str) -> str:
    return ANSI_RE.sub('', text)

# ---------------------------------------------------------------------------
# Single project session (deepseek-tui subprocess)
# ---------------------------------------------------------------------------
class ProjectSession:
    def __init__(self, project_id: str, project_dir: str):
        self.project_id = project_id
        self.project_dir = str(Path(project_dir).resolve())
        self.process: Optional[subprocess.Popen] = None
        self._read_thread: Optional[threading.Thread] = None
        self._running = False
        self._clients: set = set()  # WebSocket writers for this session

    def start(self) -> bool:
        """Start deepseek-tui in the project directory."""
        if not Path(self.project_dir).exists():
            return False

        exe = self._find_deepseek_tui()
        if not exe:
            return False

        try:
            # Use non-interactive inline mode for piped I/O
            # On Windows with .cmd wrapper, invoke via cmd /c
            if sys.platform == 'win32' and exe.endswith('.cmd'):
                cmd_args = ['cmd', '/c', exe, '--no-alt-screen', '--yolo', '-w', self.project_dir]
            else:
                cmd_args = [exe, '--no-alt-screen', '--yolo', '-w', self.project_dir]

            self.process = subprocess.Popen(
                cmd_args,
                cwd=self.project_dir,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding='utf-8',
                errors='replace',
                bufsize=1,
                creationflags=subprocess.CREATE_NO_WINDOW if sys.platform == 'win32' else 0,
            )
            self._running = True
            self._broadcast_status(f"deepseek-tui started in {self.project_dir}")

            self._read_thread = threading.Thread(target=self._read_stdout, daemon=True)
            self._read_thread.start()

            # Launch visible terminal
            self._launch_terminal()

            return True
        except Exception as e:
            self._broadcast_error(f"Failed to start: {e}")
            return False

    def _find_deepseek_tui(self) -> Optional[str]:
        import shutil
        # On Windows, prefer .cmd/.exe; fallback to unqualified name
        if sys.platform == 'win32':
            for name in ['deepseek-tui.cmd', 'deepseek-tui.exe', 'deepseek.cmd', 'deepseek.exe']:
                found = shutil.which(name)
                if found:
                    return found
            # Check npm global install
            npm_root = os.path.expandvars(r'%APPDATA%\npm')
            for name in ['deepseek-tui.cmd', 'deepseek.cmd']:
                p = Path(npm_root) / name
                if p.exists():
                    return str(p)
        for name in ['deepseek-tui', 'deepseek']:
            found = shutil.which(name)
            if found:
                return found
        return None

    def _launch_terminal(self) -> None:
        """Open visible WezTerm/PowerShell with deepseek-tui (full TUI)."""
        project_path = self.project_dir
        wezterm = self._find_wezterm()
        if wezterm:
            try:
                # Use cmd /c to properly invoke .cmd wrapper on Windows
                if sys.platform == 'win32':
                    subprocess.Popen(
                        [wezterm, 'start', '--cwd', project_path, '--',
                         'cmd', '/c', 'deepseek-tui', '--yolo'],
                        creationflags=subprocess.CREATE_NEW_CONSOLE,
                    )
                else:
                    subprocess.Popen(
                        [wezterm, 'start', '--cwd', project_path, '--',
                         'deepseek-tui', '--yolo'],
                    )
                return
            except Exception:
                pass
        # Fallback: PowerShell
        try:
            ps_cmd = f'Set-Location "{project_path}"; deepseek-tui --yolo'
            subprocess.Popen(
                ['powershell', '-NoExit', '-Command', ps_cmd],
                creationflags=subprocess.CREATE_NEW_CONSOLE,
            )
        except Exception:
            pass

    @staticmethod
    def _find_wezterm() -> Optional[str]:
        import shutil
        found = shutil.which('wezterm')
        if found:
            return found
        if sys.platform == 'win32':
            for base in [
                os.path.expandvars(r'%ProgramFiles%\WezTerm'),
                os.path.expandvars(r'%LOCALAPPDATA%\Programs\WezTerm'),
            ]:
                p = Path(base) / 'wezterm.exe'
                if p.exists():
                    return str(p)
        return None

    def send(self, text: str) -> None:
        """Send text to deepseek-tui stdin."""
        if self.process and self.process.stdin and self._running:
            try:
                self.process.stdin.write(text + '\n')
                self.process.stdin.flush()
            except (BrokenPipeError, OSError):
                self._running = False

    def _read_stdout(self) -> None:
        try:
            for line in self.process.stdout:
                if not self._running:
                    break
                clean = strip_ansi(line.rstrip('\n\r'))
                if clean.strip():
                    self._broadcast_output(clean)
        except (ValueError, OSError):
            pass
        finally:
            self._running = False
            self._broadcast_status("deepseek-tui process ended")

    def add_client(self, writer: asyncio.StreamWriter) -> None:
        self._clients.add(writer)

    def remove_client(self, writer: asyncio.StreamWriter) -> None:
        self._clients.discard(writer)

    def _broadcast_output(self, text: str) -> None:
        msg = json.dumps({'type': 'output', 'text': text}, ensure_ascii=False) + '\n'
        dead = set()
        for w in self._clients:
            try:
                w.write(msg.encode('utf-8'))
            except Exception:
                dead.add(w)
        self._clients -= dead

    def _broadcast_status(self, text: str) -> None:
        msg = json.dumps({'type': 'status', 'text': text}, ensure_ascii=False) + '\n'
        dead = set()
        for w in self._clients:
            try:
                w.write(msg.encode('utf-8'))
            except Exception:
                dead.add(w)
        self._clients -= dead

    def _broadcast_error(self, text: str) -> None:
        msg = json.dumps({'type': 'error', 'text': text}, ensure_ascii=False) + '\n'
        dead = set()
        for w in self._clients:
            try:
                w.write(msg.encode('utf-8'))
            except Exception:
                dead.add(w)
        self._clients -= dead

    @property
    def is_running(self) -> bool:
        return self._running and self.process is not None and self.process.poll() is None

    def stop(self) -> None:
        self._running = False
        if self.process:
            try:
                self.process.terminate()
                self.process.wait(timeout=3)
            except Exception:
                try:
                    self.process.kill()
                except Exception:
                    pass
            self.process = None


# ---------------------------------------------------------------------------
# Default project list (synced with mobile fallback)
# ---------------------------------------------------------------------------
DEFAULT_PROJECTS = [
    {"id": "tudushka",    "name": "Тудушка",       "path": r"C:\Users\user\Desktop\weather",        "icon": "terminal"},
    {"id": "cifra",       "name": "Цифра",         "path": r"C:\Users\user\Desktop\depseeker_test", "icon": "code"},
    {"id": "stylish-house","name": "Stylysh-house","path": r"C:\Users\user\Desktop\stylish-house",  "icon": "code"},
    {"id": "nousro",      "name": "Nousro",        "path": r"C:\Users\user\Desktop\nousro",         "icon": "folder"},
]


# ---------------------------------------------------------------------------
# WebSocket server
# ---------------------------------------------------------------------------
class BridgeServer:
    def __init__(self, host: str = '0.0.0.0', port: int = 9876):
        self.host = host
        self.port = port
        self._sessions: Dict[str, ProjectSession] = {}
        self._server = None

    def _load_projects(self) -> list:
        """Load project list from JSON config, fallback to defaults."""
        candidates = [
            Path('family_data/nik/projects.json'),
            Path(os.getcwd()) / 'family_data/nik/projects.json',
        ]
        for path in candidates:
            if path.exists():
                try:
                    data = json.loads(path.read_text(encoding='utf-8'))
                    return data.get('projects', DEFAULT_PROJECTS)
                except Exception:
                    pass
        return DEFAULT_PROJECTS

    async def start(self) -> None:
        self._server = await asyncio.start_server(
            self._handle_client,
            host=self.host,
            port=self.port,
        )
        addr = self._server.sockets[0].getsockname()
        print(f"Bridge server listening on {addr[0]}:{addr[1]}", flush=True)
        print(f"Projects: {len(self._load_projects())} configured", flush=True)

    async def _handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        addr = writer.get_extra_info('peername')
        print(f"[server] Client connected: {addr}", flush=True)

        current_session: Optional[ProjectSession] = None

        try:
            # Send project list on connect
            projects = self._load_projects()
            self._send_json(writer, {
                'type': 'projects',
                'projects': projects,
            })

            while True:
                data = await reader.readline()
                if not data:
                    break

                line = data.decode('utf-8', errors='replace').strip()
                if not line:
                    continue

                try:
                    msg = json.loads(line)
                except json.JSONDecodeError:
                    # Plain text — forward to current session
                    if current_session and current_session.is_running:
                        current_session.send(line)
                    continue

                msg_type = msg.get('type', '')

                if msg_type == 'start':
                    # Start/resume a project session
                    project_id = msg.get('project_id', '')
                    project_dir = msg.get('project_dir', '')

                    if not project_dir:
                        # Look up by id
                        for proj in projects:
                            if proj.get('id') == project_id:
                                project_dir = proj.get('path', '')
                                break

                    if not project_dir:
                        self._send_json(writer, {'type': 'error', 'text': 'project not found'})
                        continue

                    # Reuse or create session
                    session_key = project_id or project_dir
                    if session_key not in self._sessions:
                        session = ProjectSession(project_id, project_dir)
                        ok = session.start()
                        if not ok:
                            self._send_json(writer, {'type': 'error', 'text': 'failed to start deepseek-tui'})
                            continue
                        self._sessions[session_key] = session
                    else:
                        session = self._sessions[session_key]

                    current_session = session
                    session.add_client(writer)
                    self._send_json(writer, {
                        'type': 'status',
                        'text': f'Session active: {project_id or project_dir}',
                        'project_id': project_id,
                        'tui_running': session.is_running,
                    })

                elif msg_type == 'send':
                    text = msg.get('text', '')
                    if text and current_session and current_session.is_running:
                        current_session.send(text)
                        self._send_json(writer, {'type': 'sent', 'text': text})

                elif msg_type == 'ping':
                    self._send_json(writer, {
                        'type': 'pong',
                        'sessions': len(self._sessions),
                    })

                elif msg_type == 'stop':
                    if current_session:
                        current_session.remove_client(writer)
                        current_session.stop()
                        # Don't remove from _sessions — allow reconnect
                    self._send_json(writer, {'type': 'status', 'text': 'Session stopped'})

                elif msg_type == 'list':
                    self._send_json(writer, {
                        'type': 'projects',
                        'projects': self._load_projects(),
                    })

        except (ConnectionResetError, asyncio.IncompleteReadError):
            pass
        finally:
            if current_session:
                current_session.remove_client(writer)
            writer.close()
            await writer.wait_closed()
            print(f"[server] Client disconnected: {addr}", flush=True)

    @staticmethod
    def _send_json(writer: asyncio.StreamWriter, obj: dict) -> None:
        data = json.dumps(obj, ensure_ascii=False) + '\n'
        writer.write(data.encode('utf-8'))

    async def stop(self) -> None:
        for session in self._sessions.values():
            session.stop()
        self._sessions.clear()
        if self._server:
            self._server.close()
            await self._server.wait_closed()


# ---------------------------------------------------------------------------
# Tunnel client — connects PC to VPS relay
# ---------------------------------------------------------------------------
class TunnelClient:
    """Connects to tunnel_server.py on VPS for each project, relays messages."""

    def __init__(self, tunnel_host: str, tunnel_port: int = 9877):
        self.tunnel_host = tunnel_host
        self.tunnel_port = tunnel_port
        self._projects: list = []
        self._tasks: list = []
        self._terminal_launched: set = set()

    def _load_projects(self) -> list:
        candidates = [
            Path('family_data/nik/projects.json'),
            Path(os.getcwd()) / 'family_data/nik/projects.json',
        ]
        for path in candidates:
            if path.exists():
                try:
                    data = json.loads(path.read_text(encoding='utf-8'))
                    return data.get('projects', DEFAULT_PROJECTS)
                except Exception:
                    pass
        return DEFAULT_PROJECTS

    async def start(self):
        self._projects = self._load_projects()
        print(f"Tunnel client connecting to {self.tunnel_host}:{self.tunnel_port}", flush=True)
        print(f"Projects to register: {[p['id'] for p in self._projects]}", flush=True)

        for project in self._projects:
            task = asyncio.create_task(self._register_project(project))
            self._tasks.append(task)

        if self._tasks:
            await asyncio.gather(*self._tasks, return_exceptions=True)

    async def _register_project(self, project: dict):
        project_id = project['id']
        project_dir = project['path']

        while True:
            try:
                reader, writer = await asyncio.wait_for(
                    asyncio.open_connection(self.tunnel_host, self.tunnel_port),
                    timeout=10,
                )
                # Register as bridge
                reg_msg = json.dumps({
                    'type': 'register',
                    'project_id': project_id,
                }, ensure_ascii=False) + '\n'
                writer.write(reg_msg.encode('utf-8'))
                await writer.drain()

                print(f"[tunnel] Registered bridge for {project_id}", flush=True)

                # Wait for mobile client connection
                while True:
                    line = await reader.readline()
                    if not line:
                        break

                    line_str = line.decode('utf-8', errors='replace').strip()
                    if not line_str:
                        continue

                    try:
                        msg = json.loads(line_str)
                        msg_type = msg.get('type', '')

                        if msg_type in ('pong', 'ping', 'list', 'status'):
                            continue

                        if msg_type in ('send',):
                            text = msg.get('text', '')
                            if text:
                                print(f"[tunnel] {project_id} <- {text}", flush=True)
                                # Run one-shot deepseek-tui exec
                                asyncio.create_task(
                                    self._exec_prompt(project_id, project_dir, text, writer)
                                )
                            continue

                    except json.JSONDecodeError:
                        # Plain text — also run as prompt
                        if line_str:
                            print(f"[tunnel] {project_id} <- {line_str[:60]}", flush=True)
                            asyncio.create_task(
                                self._exec_prompt(project_id, project_dir, line_str, writer)
                            )

            except (ConnectionRefusedError, ConnectionResetError, OSError, asyncio.TimeoutError) as e:
                print(f"[tunnel] Connection failed for {project_id}: {e}. Retrying in 10s...", flush=True)
            except Exception as e:
                print(f"[tunnel] Error for {project_id}: {e}. Retrying in 10s...", flush=True)

            await asyncio.sleep(10)

    async def _exec_prompt(self, project_id: str, project_dir: str, prompt: str, writer: asyncio.StreamWriter):
        """Run deepseek-tui exec and send output back to mobile."""
        exe = self._find_exe()
        if not exe:
            self._send_error(writer, 'deepseek-tui not found')
            return

        # Build command: deepseek-tui -w <dir> exec --auto <prompt>
        # Use node directly to avoid cmd /c quoting issues
        cmd = self._build_exec_cmd(exe, project_dir, prompt)
        if not cmd:
            self._send_error(writer, 'cannot build exec command')
            return

        self._send_to(writer, {'type': 'status', 'text': '...'})
        print(f"[tunnel] {project_id} exec: {prompt[:80]}", flush=True)

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                cwd=project_dir,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.STDOUT,
            )
            output = []
            async for line in proc.stdout:
                decoded = line.decode('utf-8', errors='replace').rstrip('\n\r')
                clean = strip_ansi(decoded)
                if clean.strip():
                    output.append(clean)
                    self._send_to(writer, {'type': 'output', 'text': clean})

            await proc.wait()
            if not output:
                self._send_to(writer, {'type': 'status', 'text': '(no output)'})
            else:
                print(f"[tunnel] {project_id} -> {len(output)} lines", flush=True)

        except Exception as e:
            self._send_error(writer, f'exec failed: {e}')
            print(f"[tunnel] exec error: {e}", flush=True)

        # Launch visible terminal on first message (once)
        if project_id not in self._terminal_launched:
            self._terminal_launched.add(project_id)
            self._launch_terminal(project_dir)

    def _build_exec_cmd(self, exe: str, project_dir: str, prompt: str) -> Optional[list]:
        """Build command list for deepseek-tui exec. Avoids cmd /c by using node directly."""
        # If the exe is a .cmd wrapper, extract the node call
        if sys.platform == 'win32' and exe.endswith('.cmd'):
            try:
                with open(exe, 'r', encoding='utf-8') as f:
                    content = f.read()
                # Extract js path from: "%_prog%"  "%dp0%\node_modules\...\deepseek-tui.js" %*
                m = re.search(r'"%_prog%"\s+"([^"]+)"', content)
                if m:
                    dp0 = str(Path(exe).parent)
                    js_path = m.group(1).replace('%dp0%', dp0)
                    # Use bundled node.exe or system node
                    node_exe = Path(dp0) / 'node.exe'
                    node = str(node_exe) if node_exe.exists() else 'node'
                    return [node, js_path, '-w', project_dir, 'exec', '--auto', prompt]
            except Exception:
                pass
            # Fallback: use cmd /c with the .cmd directly
            return ['cmd', '/c', exe, '-w', project_dir, 'exec', '--auto', prompt]

        # Direct executable (non-Windows or .exe)
        return [exe, '-w', project_dir, 'exec', '--auto', prompt]

    def _find_exe(self) -> Optional[str]:
        """Find deepseek-tui executable."""
        import shutil
        if sys.platform == 'win32':
            for name in ['deepseek-tui.cmd', 'deepseek-tui.exe', 'deepseek.cmd', 'deepseek.exe']:
                found = shutil.which(name)
                if found:
                    return found
            npm_root = os.path.expandvars(r'%APPDATA%\npm')
            for name in ['deepseek-tui.cmd', 'deepseek.cmd']:
                p = Path(npm_root) / name
                if p.exists():
                    return str(p)
        for name in ['deepseek-tui', 'deepseek']:
            found = shutil.which(name)
            if found:
                return found
        return None

    def _launch_terminal(self, project_dir: str) -> None:
        """Open visible terminal with deepseek-tui."""
        wezterm = self._find_wezterm()
        if wezterm:
            try:
                if sys.platform == 'win32':
                    subprocess.Popen(
                        [wezterm, 'start', '--cwd', project_dir, '--',
                         'cmd', '/c', 'deepseek-tui', '--yolo'],
                        creationflags=subprocess.CREATE_NEW_CONSOLE,
                    )
                else:
                    subprocess.Popen(
                        [wezterm, 'start', '--cwd', project_dir, '--',
                         'deepseek-tui', '--yolo'],
                    )
                return
            except Exception:
                pass
        try:
            ps_cmd = f'Set-Location "{project_dir}"; deepseek-tui --yolo'
            subprocess.Popen(
                ['powershell', '-NoExit', '-Command', ps_cmd],
                creationflags=subprocess.CREATE_NEW_CONSOLE,
            )
        except Exception:
            pass

    @staticmethod
    def _find_wezterm() -> Optional[str]:
        import shutil
        found = shutil.which('wezterm')
        if found:
            return found
        if sys.platform == 'win32':
            for base in [os.path.expandvars(r'%ProgramFiles%\WezTerm'),
                         os.path.expandvars(r'%LOCALAPPDATA%\Programs\WezTerm')]:
                p = Path(base) / 'wezterm.exe'
                if p.exists():
                    return str(p)
        return None

    def _send_to(self, writer: asyncio.StreamWriter, obj: dict):
        try:
            data = json.dumps(obj, ensure_ascii=False) + '\n'
            writer.write(data.encode('utf-8'))
        except Exception:
            pass

    def _send_error(self, writer: asyncio.StreamWriter, text: str):
        self._send_to(writer, {'type': 'error', 'text': text})

    async def stop(self):
        for task in self._tasks:
            task.cancel()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
async def main():
    parser = argparse.ArgumentParser(description='Project Bridge Server')
    parser.add_argument('--port', type=int, default=9876, help='Local WebSocket port (direct mode)')
    parser.add_argument('--host', type=str, default='0.0.0.0', help='Bind address (direct mode)')
    parser.add_argument('--tunnel', type=str, default='', metavar='HOST:PORT',
                        help='VPS tunnel address (e.g. 31.129.97.211:9877) — use tunnel mode')
    args = parser.parse_args()

    if args.tunnel:
        # Tunnel mode: connect PC to VPS relay
        parts = args.tunnel.split(':')
        tunnel_host = parts[0]
        tunnel_port = int(parts[1]) if len(parts) > 1 else 9877

        client = TunnelClient(tunnel_host, tunnel_port)
        try:
            await client.start()
        except KeyboardInterrupt:
            print("\nShutting down...", flush=True)
        finally:
            await client.stop()
    else:
        # Direct mode: listen for local connections
        server = BridgeServer(host=args.host, port=args.port)
        await server.start()
        try:
            await asyncio.Event().wait()
        except KeyboardInterrupt:
            print("\nShutting down...", flush=True)
        finally:
            await server.stop()


if __name__ == '__main__':
    asyncio.run(main())
