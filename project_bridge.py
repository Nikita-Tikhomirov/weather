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
                                asyncio.create_task(self._handle_message(pid, pdir, txt))
                    except json.JSONDecodeError:
                        if ls:
                            asyncio.create_task(self._handle_message(pid, pdir, ls))
            except Exception as e:
                print(f"[tunnel] {pid} err: {e}. Retry 10s...", flush=True)
            await asyncio.sleep(10)

    async def _handle_message(self, pid: str, pdir: str, text: str):
        """Handle incoming message: /commands locally, else exec."""
        writers = self._writers.get(pid, [])
        
        # File commands
        if text.startswith('/'):
            result = await self._run_local_cmd(text, pdir)
            if result is not None:
                for line in result.split('\n'):
                    if line.strip():
                        self._send(writers, 'output', line.strip())
                return
        
        await self._exec(pid, pdir, text, writers)

    async def _run_local_cmd(self, text: str, pdir: str) -> Optional[str]:
        """Handle /commands locally. Returns string or None if not a command."""
        parts = text.split(maxsplit=1)
        cmd = parts[0].lower()
        arg = parts[1] if len(parts) > 1 else ''
        
        if cmd == '/ls':
            target = os.path.join(pdir, arg) if arg else pdir
            try:
                items = os.listdir(target)
                return '\n'.join(sorted(items))
            except Exception as e:
                return f'ls error: {e}'
        
        if cmd == '/cat':
            if not arg: return 'Usage: /cat <file>'
            try:
                fp = os.path.join(pdir, arg)
                return Path(fp).read_text(encoding='utf-8', errors='replace')[:5000]
            except Exception as e:
                return f'cat error: {e}'
        
        if cmd in ('/tree', '/dir'):
            try:
                r = subprocess.run(['cmd','/c','dir','/s','/b'], cwd=pdir,
                    capture_output=True, text=True, errors='replace', timeout=5)
                return r.stdout[:4000] or '(empty)'
            except Exception as e:
                return f'tree error: {e}'
        
        if cmd == '/git':
            try:
                r = subprocess.run(['git','status','--short'], cwd=pdir,
                    capture_output=True, text=True, errors='replace', timeout=5)
                return r.stdout.strip() or '(clean)'
            except Exception as e:
                return f'git error: {e}'
        
        if cmd == '/pwd':
            return pdir
        
        if cmd == '/help':
            return '/ls [path]  /cat <file>  /tree  /git  /pwd  /help'
        
        return None  # not a local command, forward to exec

    async def _exec(self, pid: str, pdir: str, text: str, writers: list):
        node, js = self._get_node_js()
        if not node or not js:
            self._send(writers, 'error', 'deepseek-tui not found'); return

        first = pid not in self._sessions
        if first:
            self._sessions[pid] = True
            # Preload superpowers skill on first message
            text = '/skill superpowers-lite\n' + text
        flags = ['--yolo', '-c', '-w', pdir] if not first else ['--yolo', '-w', pdir]

        # Use --json for structured output with tool calls
        cmd = [node, js] + flags + ['exec', '--json', '--auto', '-']
        self._send(writers, 'status', '...')
        print(f"[tunnel] {pid} exec {'(cont)' if not first else '(new)'}", flush=True)

        loop = asyncio.get_event_loop()
        
        def run_stream():
            import queue
            q = queue.Queue()
            def target():
                try:
                    proc = subprocess.Popen(
                        cmd, cwd=pdir, stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                        text=True, encoding='utf-8', errors='replace', bufsize=1,
                    )
                    proc.stdin.write(text)
                    proc.stdin.close()
                    for line in proc.stdout:
                        q.put(('out', line.rstrip('\n\r')))
                    for line in proc.stderr:
                        q.put(('err', line.rstrip('\n\r')))
                    proc.wait()
                    q.put(('done', proc.returncode))
                except Exception as e:
                    q.put(('error', str(e)))
            t = threading.Thread(target=target, daemon=True)
            t.start()
            return q, t

        q, thread = await loop.run_in_executor(None, run_stream)
        
        line_count = 0
        while thread.is_alive() or not q.empty():
            try:
                import queue as _q
                kind, data = q.get(timeout=0.3)
                if kind == 'out':
                    clean = strip_ansi(data.strip())
                    if clean:
                        # Parse JSON to extract meaningful content
                        try:
                            obj = json.loads(clean)
                            formatted = self._format_json_output(obj)
                            if formatted:
                                for line in formatted.split('\n'):
                                    if line.strip():
                                        line_count += 1
                                        self._send(writers, 'output', line.strip())
                        except json.JSONDecodeError:
                            if clean:
                                line_count += 1
                                self._send(writers, 'output', clean)
                elif kind == 'err':
                    # stderr has verbose tool info
                    clean = data.strip()
                    if clean and not clean.startswith('info '):
                        line_count += 1
                        self._send(writers, 'output', clean)
                elif kind == 'done':
                    break
                elif kind == 'error':
                    self._send(writers, 'error', data)
                    break
            except _q.Empty:
                await asyncio.sleep(0.05)
        
        print(f"[tunnel] {pid} exec: {line_count} lines", flush=True)

    def _format_json_output(self, obj: dict) -> str:
        """Format JSON exec output for mobile display."""
        parts = []
        if 'output' in obj:
            parts.append(obj['output'])
        if 'tools' in obj:
            for tool in obj['tools']:
                name = tool.get('name', '?')
                success = '✅' if tool.get('success') else '❌'
                out = tool.get('output', '')[:200]
                parts.append(f'[{success} tool:{name}] {out}')
        return '\n'.join(parts)

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
