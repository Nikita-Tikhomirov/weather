"""
Project Bridge Server — deepseek-tui exec with Python-managed conversation history.
Each project session accumulates messages in Python, prepends them to exec prompts.

Usage: python project_bridge.py [--tunnel 31.129.97.211:9877]
"""
import argparse, asyncio, json, os, re, subprocess, sys, threading
from pathlib import Path
from typing import Optional, Dict

if sys.platform == 'win32':
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

ANSI_RE = re.compile(r'\x1b\[[0-9;]*[a-zA-Z]|\x1b\].*?\x07|\x1b\[[0-9]+[A-K]|\x1b\[\?[0-9]+[hl]')
def strip_ansi(text: str) -> str:
    return ANSI_RE.sub('', text)

DEFAULT_PROJECTS = [
    {"id": "tudushka",    "name": "Тудушка",       "path": r"C:\Users\user\Desktop\weather",        "icon": "terminal"},
    {"id": "cifra",       "name": "Цифра",         "path": r"C:\Users\user\Desktop\depseeker_test", "icon": "code"},
    {"id": "stylish-house","name": "Stylysh-house","path": r"C:\Users\user\Desktop\stylish-house",  "icon": "code"},
    {"id": "nousro",      "name": "Nousro",        "path": r"C:\Users\user\Desktop\nousro",         "icon": "folder"},
]

class TunnelClient:
    def __init__(self, tunnel_host: str, tunnel_port: int = 9877):
        self.tunnel_host = tunnel_host
        self.tunnel_port = tunnel_port
        self._sessions: Dict[str, Session] = {}
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

    def _get_node_js(self) -> tuple:
        import shutil
        node = shutil.which('node') or 'node'
        npm = os.path.expandvars(r'%APPDATA%\npm')
        js = Path(npm) / 'node_modules' / 'deepseek-tui' / 'bin' / 'deepseek-tui.js'
        if js.exists(): return node, str(js)
        return None, None

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
                first = True
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
                                if first:
                                    self._launch_terminal(pdir)
                                    first = False
                                asyncio.create_task(self._exec(pid, pdir, txt))
                    except json.JSONDecodeError:
                        if ls:
                            asyncio.create_task(self._exec(pid, pdir, ls))
            except Exception as e:
                print(f"[tunnel] {pid} err: {e}. Retry 10s...", flush=True)
            await asyncio.sleep(10)

    async def _exec(self, pid: str, pdir: str, text: str):
        writers = self._writers.get(pid, [])

        node, js = self._get_node_js()
        if not node or not js:
            self._send(writers, 'error', 'deepseek-tui not found'); return

        # Use -c to continue the most recent session in this workspace
        first = pid not in self._sessions
        if first:
            self._sessions[pid] = True  # mark as active
            flags = ['--yolo', '-w', pdir]
        else:
            flags = ['--yolo', '-c', '-w', pdir]

        cmd = [node, js] + flags + ['exec', '--auto', '-']
        self._send(writers, 'status', '...')
        print(f"[tunnel] {pid} exec {'(new)' if first else '(cont)'}", flush=True)

        loop = asyncio.get_event_loop()

        def run():
            try:
                proc = subprocess.run(
                    cmd,
                    cwd=pdir,
                    input=text,  # stdin, no arg length limits
                    capture_output=True,
                    text=True, encoding='utf-8', errors='replace',
                    timeout=300,
                )
                return proc.stdout, proc.stderr, proc.returncode
            except subprocess.TimeoutExpired:
                return None, None, -1
            except Exception as e:
                return None, str(e), -2

        stdout, stderr, rc = await loop.run_in_executor(None, run)
        print(f"[tunnel] {pid} exec: rc={rc} out={len(stdout or '')}", flush=True)

        if stdout:
            for line in stdout.split('\n'):
                clean = strip_ansi(line.strip())
                if clean:
                    self._send(writers, 'output', clean)
        elif stderr:
            for line in stderr.split('\n'):
                clean = strip_ansi(line.strip())
                if clean:
                    self._send(writers, 'output', clean)
        else:
            self._send(writers, 'status', f'exit {rc}')

    def _send(self, writers: list, typ: str, text: str):
        if not writers: return
        msg = json.dumps({'type':typ,'text':text}, ensure_ascii=False)+'\n'
        data = msg.encode('utf-8')
        dead = []
        for w in writers:
            try: w.write(data)
            except Exception: dead.append(w)
        for w in dead:
            writers.remove(w)
            try: w.close()
            except Exception: pass

    def _launch_terminal(self, pdir: str):
        import shutil
        wz = shutil.which('wezterm')
        if not wz:
            for b in [os.path.expandvars(r'%ProgramFiles%\WezTerm'),
                      os.path.expandvars(r'%LOCALAPPDATA%\Programs\WezTerm')]:
                p = Path(b) / 'wezterm.exe'
                if p.exists(): wz = str(p); break
        if wz:
            try:
                subprocess.Popen([wz,'start','--cwd',pdir,'--','cmd','/c','deepseek-tui','--yolo'],
                    creationflags=subprocess.CREATE_NEW_CONSOLE)
                return
            except Exception: pass
        try:
            subprocess.Popen(['powershell','-NoExit','-Command',
                f'Set-Location "{pdir}"; deepseek-tui --yolo'],
                creationflags=subprocess.CREATE_NEW_CONSOLE)
        except Exception: pass

    async def stop(self):
        for t in self._tasks: t.cancel()

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
