"""
Project Bridge - WebSocket server that manages a deepseek-tui session
for a specific project directory.

Usage: python project_bridge.py --project-dir "C:\path\to\project" [--port PORT]

The bridge:
1. Starts a WebSocket server on localhost
2. Launches deepseek-tui in the project directory
3. Routes messages: WebSocket <-> deepseek-tui stdin/stdout
4. Opens WezTerm (or PowerShell) for visible terminal access
"""
import argparse
import asyncio
import json
import os
import re
import signal
import socket
import subprocess
import sys
import threading
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# ANSI escape code stripping
# ---------------------------------------------------------------------------
ANSI_RE = re.compile(r'\x1b\[[0-9;]*[a-zA-Z]|\x1b\].*?\x07|\x1b\[[0-9]+[A-K]')

def strip_ansi(text: str) -> str:
    return ANSI_RE.sub('', text)

# ---------------------------------------------------------------------------
# Process manager for deepseek-tui
# ---------------------------------------------------------------------------
class TuiProcess:
    def __init__(self, project_dir: str):
        self.project_dir = Path(project_dir).resolve()
        self.process: Optional[subprocess.Popen] = None
        self._read_thread: Optional[threading.Thread] = None
        self._running = False
        self._on_output: Optional[callable] = None

    def start(self, on_output: callable) -> bool:
        """Start deepseek-tui in the project directory."""
        if not self.project_dir.exists():
            on_output(f"[bridge] Project directory not found: {self.project_dir}")
            return False

        self._on_output = on_output

        # Find deepseek-tui executable
        exe = self._find_deepseek_tui()
        if not exe:
            on_output("[bridge] deepseek-tui not found in PATH")
            return False

        try:
            # Launch with stdin/stdout pipes
            self.process = subprocess.Popen(
                [exe],
                cwd=str(self.project_dir),
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
            on_output(f"[bridge] deepseek-tui started in {self.project_dir}")

            # Start reader thread
            self._read_thread = threading.Thread(target=self._read_stdout, daemon=True)
            self._read_thread.start()

            return True
        except Exception as e:
            on_output(f"[bridge] Failed to start deepseek-tui: {e}")
            return False

    def _find_deepseek_tui(self) -> Optional[str]:
        """Locate deepseek-tui executable."""
        # Common names
        candidates = ['deepseek-tui', 'deepseek', 'deekseek-tui']
        
        # Check PATH first
        for name in candidates:
            import shutil
            found = shutil.which(name)
            if found:
                return found

        # Check common install locations on Windows
        if sys.platform == 'win32':
            for base in [
                os.path.expandvars(r'%LOCALAPPDATA%\Programs\deepseek\bin'),
                os.path.expandvars(r'%USERPROFILE%\.cargo\bin'),
                os.path.expandvars(r'%APPDATA%\npm'),
            ]:
                for name in ['deepseek-tui.exe', 'deepseek.exe']:
                    p = Path(base) / name
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
        """Continuously read stdout and forward via callback."""
        try:
            for line in self.process.stdout:
                if not self._running:
                    break
                clean = strip_ansi(line.rstrip('\n\r'))
                if clean.strip():
                    self._on_output(clean)
        except (ValueError, OSError):
            pass
        finally:
            self._running = False
            self._on_output("[bridge] deepseek-tui process ended")

    def stop(self) -> None:
        """Stop the process."""
        self._running = False
        if self.process:
            try:
                if sys.platform == 'win32':
                    self.process.terminate()
                else:
                    self.process.send_signal(signal.SIGTERM)
                self.process.wait(timeout=3)
            except Exception:
                try:
                    self.process.kill()
                except Exception:
                    pass
            self.process = None

    @property
    def is_running(self) -> bool:
        return self._running and self.process is not None and self.process.poll() is None


# ---------------------------------------------------------------------------
# Terminal launcher (WezTerm or PowerShell)
# ---------------------------------------------------------------------------
def launch_terminal(project_dir: str) -> Optional[subprocess.Popen]:
    """Open a visible terminal with deepseek-tui in the project directory."""
    project_path = Path(project_dir).resolve()

    # Try WezTerm first
    wezterm = _find_wezterm()
    if wezterm:
        try:
            proc = subprocess.Popen(
                [wezterm, 'start', '--cwd', str(project_path), '--', 'deepseek-tui'],
                creationflags=subprocess.CREATE_NEW_CONSOLE if sys.platform == 'win32' else 0,
            )
            return proc
        except Exception:
            pass

    # Fallback to PowerShell
    try:
        ps_command = f'Set-Location "{project_path}"; deepseek-tui'
        proc = subprocess.Popen(
            ['powershell', '-NoExit', '-Command', ps_command],
            creationflags=subprocess.CREATE_NEW_CONSOLE,
        )
        return proc
    except Exception:
        pass

    # Last resort: cmd
    try:
        proc = subprocess.Popen(
            ['cmd', '/c', 'start', 'cmd', '/k', f'cd /d "{project_path}" && deepseek-tui'],
        )
        return proc
    except Exception:
        return None


def _find_wezterm() -> Optional[str]:
    """Find WezTerm executable."""
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


# ---------------------------------------------------------------------------
# WebSocket server
# ---------------------------------------------------------------------------
class ProjectBridge:
    def __init__(self, project_dir: str, port: int = 0):
        self.project_dir = str(Path(project_dir).resolve())
        self.port = port
        self.tui: Optional[TuiProcess] = None
        self._clients: set = set()
        self._server = None

    async def start(self) -> int:
        """Start the bridge. Returns the actual port."""
        # Start deepseek-tui
        self.tui = TuiProcess(self.project_dir)
        ok = self.tui.start(on_output=self._broadcast)
        if not ok:
            print(f"WARNING: deepseek-tui not available, bridge will forward commands only", file=sys.stderr)

        # Launch visible terminal
        launch_terminal(self.project_dir)

        # Start WebSocket server
        self._server = await asyncio.start_server(
            self._handle_client,
            host='127.0.0.1',
            port=self.port,
        )
        
        # Get actual port
        addr = self._server.sockets[0].getsockname()
        actual_port = addr[1]
        self.port = actual_port

        # Write port to file so Flutter can discover it
        port_file = Path(self.project_dir) / '.project_bridge_port'
        port_file.write_text(str(actual_port))

        print(f"Bridge started on port {actual_port} for {self.project_dir}", flush=True)

        return actual_port

    async def _handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        """Handle a WebSocket client connection."""
        self._clients.add(writer)
        addr = writer.get_extra_info('peername')
        print(f"[bridge] Client connected: {addr}", flush=True)

        try:
            # Send initial status
            status = {
                'type': 'status',
                'project_dir': self.project_dir,
                'tui_running': self.tui.is_running if self.tui else False,
            }
            self._send_json(writer, status)

            # Read messages from client
            while True:
                data = await reader.readline()
                if not data:
                    break
                
                line = data.decode('utf-8', errors='replace').strip()
                if not line:
                    continue
                
                # Try to parse as JSON (command message)
                try:
                    msg = json.loads(line)
                    await self._handle_message(writer, msg)
                except json.JSONDecodeError:
                    # Plain text - forward to deepseek-tui
                    if self.tui and self.tui.is_running:
                        self.tui.send(line)
                    else:
                        self._send_json(writer, {
                            'type': 'error',
                            'message': 'deepseek-tui not running',
                        })

        except (ConnectionResetError, asyncio.IncompleteReadError):
            pass
        finally:
            self._clients.discard(writer)
            writer.close()
            await writer.wait_closed()
            print(f"[bridge] Client disconnected: {addr}", flush=True)

    async def _handle_message(self, writer: asyncio.StreamWriter, msg: dict) -> None:
        """Handle a structured message from the client."""
        msg_type = msg.get('type', '')

        if msg_type == 'send':
            text = msg.get('text', '')
            if text and self.tui and self.tui.is_running:
                self.tui.send(text)
                self._send_json(writer, {
                    'type': 'sent',
                    'text': text,
                })
        elif msg_type == 'ping':
            self._send_json(writer, {
                'type': 'pong',
                'tui_running': self.tui.is_running if self.tui else False,
            })
        elif msg_type == 'restart':
            if self.tui:
                self.tui.stop()
                ok = self.tui.start(on_output=self._broadcast)
                self._send_json(writer, {
                    'type': 'status',
                    'tui_running': ok,
                })
        elif msg_type == 'stop':
            if self.tui:
                self.tui.stop()
            self._send_json(writer, {
                'type': 'status',
                'tui_running': False,
            })

    def _broadcast(self, text: str) -> None:
        """Send text to all connected clients."""
        msg = {'type': 'output', 'text': text}
        dead = set()
        for writer in self._clients:
            try:
                self._send_json(writer, msg)
            except Exception:
                dead.add(writer)
        self._clients -= dead

    @staticmethod
    def _send_json(writer: asyncio.StreamWriter, obj: dict) -> None:
        """Send a JSON message followed by newline."""
        data = json.dumps(obj, ensure_ascii=False) + '\n'
        writer.write(data.encode('utf-8'))

    async def stop(self) -> None:
        """Stop the bridge."""
        if self.tui:
            self.tui.stop()
        if self._server:
            self._server.close()
            await self._server.wait_closed()
        # Clean up port file
        port_file = Path(self.project_dir) / '.project_bridge_port'
        try:
            port_file.unlink(missing_ok=True)
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
async def main():
    parser = argparse.ArgumentParser(description='Project Bridge for deepseek-tui')
    parser.add_argument('--project-dir', required=True, help='Project directory path')
    parser.add_argument('--port', type=int, default=0, help='WebSocket port (0=auto)')
    parser.add_argument('--no-terminal', action='store_true', help='Skip opening visible terminal')
    args = parser.parse_args()

    bridge = ProjectBridge(args.project_dir, args.port)
    port = await bridge.start()
    print(f"BRIDGE_PORT={port}", flush=True)

    try:
        await asyncio.Event().wait()  # Run forever
    except KeyboardInterrupt:
        pass
    finally:
        await bridge.stop()


if __name__ == '__main__':
    asyncio.run(main())
