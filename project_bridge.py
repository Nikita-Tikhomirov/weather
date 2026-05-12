"""
Project Bridge Server — manages deepseek-tui PTY sessions per project.
Designed to run on the PC continuously.

Mobile app connects via VPS tunnel, messages flow bidirectionally.
Each project gets a persistent PTY (pseudo-terminal) session with
full TUI rendering, thinking tokens, and /command support.

Usage: python project_bridge.py [--tunnel 31.129.97.211:9877]
"""
import argparse
import asyncio
import json
import os
import re
import subprocess
import sys
import threading
from pathlib import Path
from typing import Optional, Dict

if sys.platform == 'win32':
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

# ---------------------------------------------------------------------------
# ANSI escape code stripping
# ---------------------------------------------------------------------------
ANSI_RE = re.compile(r'\x1b\[[0-9;]*[a-zA-Z]|\x1b\].*?\x07|\x1b\[[0-9]+[A-K]|\x1b\[\?[0-9]+[hl]')

def strip_ansi(text: str) -> str:
    return ANSI_RE.sub('', text)

# ---------------------------------------------------------------------------
# Persistent PTY session
# ---------------------------------------------------------------------------
class PtySession:
    """Wraps winpty.PtyProcess for a persistent deepseek-tui session."""

    def __init__(self, project_id: str, project_dir: str):
        self.project_id = project_id
        self.project_dir = str(Path(project_dir).resolve())
        self._proc = None  # winpty.PtyProcess
        self._running = False
        self._read_thread: Optional[threading.Thread] = None
        self._lock = threading.Lock()
        self._output_callbacks: list = []

    def start(self) -> bool:
        if not Path(self.project_dir).exists():
            return False

        node, js_path = self._get_node_and_js()
        if not node or not js_path:
            return False

        try:
            from winpty import PtyProcess
            argv = [node, js_path, '--yolo', '-w', self.project_dir]
            self._proc = PtyProcess.spawn(argv, cwd=self.project_dir)
            self._running = True
            self._broadcast('status', f'deepseek-tui PTY started in {self.project_dir}')

            self._read_thread = threading.Thread(target=self._read_loop, daemon=True)
            self._read_thread.start()

            # Also open visible WezTerm
            self._launch_terminal()
            return True
        except Exception as e:
            self._broadcast('error', f'PTY start failed: {e}')
            return False

    def _read_loop(self):
        buf = b''
        while self._running and self._proc:
            try:
                data = self._proc.read(4096, blocking=False)
                if data:
                    buf += data
                    # Try to decode whatever we have
                    while b'\n' in buf or len(buf) > 8192:
                        if b'\n' in buf:
                            idx = buf.index(b'\n')
                            line_bytes = buf[:idx+1]
                            buf = buf[idx+1:]
                        else:
                            line_bytes = buf
                            buf = b''
                        try:
                            text = line_bytes.decode('utf-8', errors='replace')
                            clean = strip_ansi(text).strip()
                            if clean:
                                self._broadcast('output', clean)
                        except Exception:
                            pass
                else:
                    # No data, sleep a bit
                    import time
                    time.sleep(0.1)
            except Exception:
                import time
                time.sleep(0.5)

        self._running = False
        self._broadcast('status', 'deepseek-tui PTY ended')

    def write(self, text: str):
        if self._proc and self._running:
            try:
                self._proc.write(text + '\r\n')
            except Exception:
                self._running = False

    def add_callback(self, cb):
        self._output_callbacks.append(cb)

    def remove_callback(self, cb):
        self._output_callbacks = [c for c in self._output_callbacks if c is not cb]

    def _broadcast(self, typ: str, text: str):
        for cb in self._output_callbacks:
            try:
                cb(typ, text)
            except Exception:
                pass

    @property
    def is_running(self):
        return self._running and self._proc is not None

    def stop(self):
        self._running = False
        if self._proc:
            try:
                self._proc.terminate()
            except Exception:
                pass
            self._proc = None

    @staticmethod
    def _get_node_and_js() -> tuple:
        import shutil
        node = shutil.which('node') or 'node'
        npm_root = os.path.expandvars(r'%APPDATA%\npm')
        js = Path(npm_root) / 'node_modules' / 'deepseek-tui' / 'bin' / 'deepseek-tui.js'
        if js.exists():
            return node, str(js)
        cmd_path = Path(npm_root) / 'deepseek-tui.cmd'
        if cmd_path.exists():
            try:
                content = cmd_path.read_text(encoding='utf-8')
                m = re.search(r'"%_prog%"\s+"([^"]+)"', content)
                if m:
                    js_path = m.group(1).replace('%dp0%', npm_root)
                    return node, js_path
            except Exception:
                pass
        return None, None

    def _launch_terminal(self):
        wezterm = self._find_wezterm()
        if wezterm:
            try:
                if sys.platform == 'win32':
                    subprocess.Popen(
                        [wezterm, 'start', '--cwd', self.project_dir, '--',
                         'cmd', '/c', 'deepseek-tui', '--yolo'],
                        creationflags=subprocess.CREATE_NEW_CONSOLE,
                    )
                else:
                    subprocess.Popen(
                        [wezterm, 'start', '--cwd', self.project_dir, '--',
                         'deepseek-tui', '--yolo'],
                    )
                return
            except Exception:
                pass
        try:
            ps_cmd = f'Set-Location "{self.project_dir}"; deepseek-tui --yolo'
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


# ---------------------------------------------------------------------------
# Default projects
# ---------------------------------------------------------------------------
DEFAULT_PROJECTS = [
    {"id": "tudushka",    "name": "Тудушка",       "path": r"C:\Users\user\Desktop\weather",        "icon": "terminal"},
    {"id": "cifra",       "name": "Цифра",         "path": r"C:\Users\user\Desktop\depseeker_test", "icon": "code"},
    {"id": "stylish-house","name": "Stylysh-house","path": r"C:\Users\user\Desktop\stylish-house",  "icon": "code"},
    {"id": "nousro",      "name": "Nousro",        "path": r"C:\Users\user\Desktop\nousro",         "icon": "folder"},
]


# ---------------------------------------------------------------------------
# Tunnel client
# ---------------------------------------------------------------------------
class TunnelClient:
    def __init__(self, tunnel_host: str, tunnel_port: int = 9877):
        self.tunnel_host = tunnel_host
        self.tunnel_port = tunnel_port
        self._sessions: Dict[str, PtySession] = {}
        self._writers: Dict[str, list] = {}  # project_id -> list of tunnel writers
        self._tasks: list = []
        self._projects: list = []

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
        print(f"Tunnel client -> {self.tunnel_host}:{self.tunnel_port}", flush=True)
        print(f"Projects: {[p['id'] for p in self._projects]}", flush=True)

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
                writer.write(json.dumps({'type': 'register', 'project_id': project_id},
                                        ensure_ascii=False).encode() + b'\n')
                await writer.drain()
                print(f"[tunnel] Registered: {project_id}", flush=True)

                # Store writer for this project
                self._writers.setdefault(project_id, []).append(writer)

                # Read messages from mobile
                while True:
                    line = await reader.readline()
                    if not line:
                        break

                    line_str = line.decode('utf-8', errors='replace').strip()
                    if not line_str:
                        continue

                    try:
                        msg = json.loads(line_str)
                        if msg.get('type') in ('pong', 'ping', 'list', 'status'):
                            continue
                        if msg.get('type') == 'send':
                            text = msg.get('text', '')
                            if text:
                                print(f"[tunnel] {project_id} <- {text[:60]}", flush=True)
                                self._send_to_project(project_id, project_dir, text)
                    except json.JSONDecodeError:
                        if line_str:
                            self._send_to_project(project_id, project_dir, line_str)

            except (ConnectionRefusedError, ConnectionResetError, OSError, asyncio.TimeoutError) as e:
                print(f"[tunnel] {project_id} disconnected: {e}. Retry in 10s...", flush=True)
            except Exception as e:
                print(f"[tunnel] {project_id} error: {e}. Retry in 10s...", flush=True)

            await asyncio.sleep(10)

    def _send_to_project(self, project_id: str, project_dir: str, text: str):
        """Send text to the PTY session, auto-start if needed."""
        session = self._sessions.get(project_id)
        if not session or not session.is_running:
            session = PtySession(project_id, project_dir)
            ok = session.start()
            if not ok:
                self._broadcast_to_mobiles(project_id, 'error', f'Failed to start session for {project_id}')
                return
            self._sessions[project_id] = session
            # Hook output to mobile
            session.add_callback(lambda typ, txt, pid=project_id: self._broadcast_to_mobiles(pid, typ, txt))

        session.write(text)

    def _broadcast_to_mobiles(self, project_id: str, typ: str, text: str):
        """Send output to all connected mobile clients for this project."""
        msg = json.dumps({'type': typ, 'text': text}, ensure_ascii=False) + '\n'
        data = msg.encode('utf-8')
        writers = self._writers.get(project_id, [])
        dead = []
        for w in writers:
            try:
                w.write(data)
            except Exception:
                dead.append(w)
        for w in dead:
            writers.remove(w)
            try:
                w.close()
            except Exception:
                pass

    async def stop(self):
        for task in self._tasks:
            task.cancel()
        for session in self._sessions.values():
            session.stop()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
async def main():
    parser = argparse.ArgumentParser(description='Project Bridge Server')
    parser.add_argument('--tunnel', type=str, default='', metavar='HOST:PORT',
                        help='VPS tunnel address (e.g. 31.129.97.211:9877)')
    args = parser.parse_args()

    if args.tunnel:
        parts = args.tunnel.split(':')
        host, port = parts[0], int(parts[1]) if len(parts) > 1 else 9877
        client = TunnelClient(host, port)
        try:
            await client.start()
        except KeyboardInterrupt:
            print("\nShutting down...", flush=True)
        finally:
            await client.stop()
    else:
        print("Use --tunnel HOST:PORT for tunnel mode", flush=True)


if __name__ == '__main__':
    asyncio.run(main())
