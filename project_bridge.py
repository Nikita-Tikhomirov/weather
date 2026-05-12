"""
Project Bridge — persistent PTY sessions per project.
One deepseek-tui process per project, stays alive until explicit stop.
Full TUI output (ANSI-stripped) streamed to mobile.

Usage: python project_bridge.py [--tunnel 31.129.97.211:9877]
"""
import argparse, asyncio, json, os, re, subprocess, sys, threading, time
from pathlib import Path
from typing import Optional, Dict

if sys.platform == 'win32':
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

ANSI_RE = re.compile(r'\x1b\[[0-9;]*[a-zA-Z]|\x1b\].*?\x07|\x1b\[[0-9]+[A-K]|\x1b\[\?[0-9]+[hl]|\x1b\[\?[0-9]+h|\x1b\[\?[0-9]+l')
def clean_line(text: str) -> str:
    """Strip ANSI and return cleaned text, or empty string if nothing useful."""
    s = ANSI_RE.sub('', text).strip()
    # Filter out purely cosmetic lines (cursor movements, screen clears yield empty)
    if not s or s in (' ', '  ', '   '):
        return ''
    # Filter TUI frame characters
    if s.startswith('─') or s.startswith('│') or s.startswith('┌') or s.startswith('└'):
        return ''
    return s

DEFAULT_PROJECTS = [
    {"id": "tudushka",    "name": "Тудушка",       "path": r"C:\Users\user\Desktop\weather",        "icon": "terminal"},
    {"id": "cifra",       "name": "Цифра",         "path": r"C:\Users\user\Desktop\depseeker_test", "icon": "code"},
    {"id": "stylish-house","name": "Stylysh-house","path": r"C:\Users\user\Desktop\stylish-house",  "icon": "code"},
    {"id": "nousro",      "name": "Nousro",        "path": r"C:\Users\user\Desktop\nousro",         "icon": "folder"},
]

class PtySession:
    """Persistent PTY session for one project."""
    def __init__(self, pid: str, pdir: str):
        self.pid = pid
        self.pdir = pdir
        self.proc = None
        self.thread = None
        self.running = False
        self.writers: list = []

    def start(self) -> bool:
        from winpty import PtyProcess
        node, js = self._get_node_js()
        if not node or not js:
            return False
        try:
            argv = [node, js, '--yolo', '-w', self.pdir]
            self.proc = PtyProcess.spawn(argv, cwd=self.pdir, dimensions=(40, 120))
            self.running = True
            self.thread = threading.Thread(target=self._read_loop, daemon=True)
            self.thread.start()
            print(f"[pty] Started {self.pid}", flush=True)
            return True
        except Exception as e:
            print(f"[pty] Start failed {self.pid}: {e}", flush=True)
            return False

    def _read_loop(self):
        while self.running:
            try:
                line = self.proc.readline()
                if line:
                    clean = clean_line(line)
                    if clean:
                        self._broadcast('output', clean)
                else:
                    break
            except EOFError:
                break
            except Exception:
                time.sleep(0.2)
        self.running = False
        self._broadcast('status', 'Session ended')

    def write(self, text: str):
        if self.proc and self.running:
            try:
                self.proc.write(text + '\r\n')
            except Exception:
                self.running = False

    def _broadcast(self, typ: str, text: str):
        msg = json.dumps({'type': typ, 'text': text}, ensure_ascii=False) + '\n'
        data = msg.encode('utf-8')
        dead = []
        for w in self.writers:
            try:
                w.write(data)
            except Exception:
                dead.append(w)
        for w in dead:
            self.writers.remove(w)

    def stop(self):
        self.running = False
        if self.proc:
            try:
                self.proc.terminate()
            except Exception:
                pass
            self.proc = None

    @staticmethod
    def _get_node_js():
        import shutil as _sh
        node = _sh.which('node') or 'node'
        npm = os.path.expandvars(r'%APPDATA%\npm')
        js = Path(npm) / 'node_modules' / 'deepseek-tui' / 'bin' / 'deepseek-tui.js'
        if js.exists():
            return node, str(js)
        return None, None

class TunnelClient:
    def __init__(self, tunnel_host: str, tunnel_port: int = 9877):
        self.tunnel_host = tunnel_host
        self.tunnel_port = tunnel_port
        self._sessions: Dict[str, PtySession] = {}
        self._writers: Dict[str, list] = {}
        self._tasks: list = []

    def _load_projects(self) -> list:
        candidates = [Path('family_data/nik/projects.json'),
                      Path(os.getcwd()) / 'family_data/nik/projects.json']
        for path in candidates:
            if path.exists():
                try:
                    data = json.loads(path.read_text(encoding='utf-8'))
                    return data.get('projects', DEFAULT_PROJECTS)
                except Exception: pass
        return DEFAULT_PROJECTS

    async def start(self):
        projects = self._load_projects()
        print(f"Tunnel -> {self.tunnel_host}:{self.tunnel_port}", flush=True)
        for p in projects:
            t = asyncio.create_task(self._register_project(p))
            self._tasks.append(t)
        if self._tasks:
            await asyncio.gather(*self._tasks, return_exceptions=True)

    async def _register_project(self, project: dict):
        pid, pdir = project['id'], project['path']
        while True:
            try:
                r, w = await asyncio.wait_for(
                    asyncio.open_connection(self.tunnel_host, self.tunnel_port), timeout=10)
                w.write(json.dumps({'type':'register','project_id':pid}, ensure_ascii=False).encode()+b'\n')
                await w.drain()
                self._writers.setdefault(pid, []).append(w)
                print(f"[tunnel] {pid} registered", flush=True)

                # Start persistent PTY session
                session = self._sessions.get(pid)
                if not session or not session.running:
                    session = PtySession(pid, pdir)
                    if session.start():
                        self._sessions[pid] = session
                
                if session and session.running:
                    session.writers.append(w)

                while True:
                    line = await r.readline()
                    if not line: break
                    ls = line.decode('utf-8','replace').strip()
                    if not ls: continue
                    try:
                        msg = json.loads(ls)
                        if msg.get('type') in ('pong','ping','list','status'): continue
                        if msg.get('type') == 'send':
                            txt = msg.get('text','')
                            if txt:
                                print(f"[tunnel] {pid} <- {txt[:60]}", flush=True)
                                if session and session.running:
                                    session.write(txt)
                    except json.JSONDecodeError:
                        if ls and session and session.running:
                            session.write(ls)
            except Exception as e:
                print(f"[tunnel] {pid} err: {e}. Retry 10s...", flush=True)
            await asyncio.sleep(10)

    async def stop(self):
        for t in self._tasks: t.cancel()
        for s in self._sessions.values(): s.stop()

async def main():
    p = argparse.ArgumentParser()
    p.add_argument('--tunnel', default='', metavar='HOST:PORT')
    args = p.parse_args()
    if args.tunnel:
        h, po = args.tunnel.split(':')
        c = TunnelClient(h, int(po) if po else 9877)
        try: await c.start()
        except KeyboardInterrupt: print("\nDone", flush=True)
        finally: await c.stop()
    else:
        print("Use --tunnel HOST:PORT")

if __name__ == '__main__':
    asyncio.run(main())
