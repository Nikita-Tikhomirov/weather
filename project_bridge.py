"""
Project Bridge - runs DeepSeek TUI prompts for project chats.

The bridge spawns deepseek-tui in a PTY (pseudo-terminal) via wexpect,
maintaining one persistent process per project. Messages are typed into
the TUI and responses are streamed back. Full session continuity.

Usage: python project_bridge.py [--tunnel 31.129.97.211:9877]
"""
import argparse
import asyncio
import base64
import json
import os
import re
import subprocess
import sys
import threading
import time
import wexpect
import uuid
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Dict

if sys.platform == "win32":
    asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())

ANSI_RE = re.compile(
    r"\x1b\[[0-9;]*[a-zA-Z]"
    r"|\x1b\].*?\x07"
    r"|\x1b\[[0-9]+[A-K]"
    r"|\x1b\[\?[0-9]+[hl]"
    r"|\x1b\[\?[0-9]+h"
    r"|\x1b\[\?[0-9]+l"
)


_FRAME_CHARS = set("─│┌└┐┘├┤┬┴┼╭╮╰╯═║╒╓╔╕╖╗╘╙╚╛╜╝╞╟╠╡╢╣╤╥╦╧╨╩╪╫╬")

def clean_line(text: str) -> str:
    """Strip terminal control sequences and cosmetic frame-only lines."""
    s = ANSI_RE.sub("", text).strip()
    if not s:
        return ""
    # Skip pure frame-drawing lines
    if all(c in _FRAME_CHARS or c == ' ' for c in s):
        return ""
    return s


DEFAULT_PROJECTS = [
    {
        "id": "tudushka",
        "name": "Тудушка",
        "path": r"C:\Users\user\Desktop\weather",
        "icon": "terminal",
    },
    {
        "id": "cifra",
        "name": "Цифра",
        "path": r"C:\Users\user\Desktop\depseeker_test",
        "icon": "code",
    },
    {
        "id": "stylish-house",
        "name": "Stylysh-house",
        "path": r"C:\Users\user\Desktop\stylish-house",
        "icon": "code",
    },
    {
        "id": "nousro",
        "name": "Nousro",
        "path": r"C:\Users\user\Desktop\nousro",
        "icon": "folder",
    },
]

RECONNECT_DELAY_SECONDS = 1
MAX_UPLOAD_BYTES = 15 * 1024 * 1024
MAX_TUNNEL_LINE_BYTES = 32 * 1024 * 1024
HISTORY_REPLAY_LIMIT = 300
IMAGE_EXTENSIONS = {
    "image/jpeg": ".jpg",
    "image/jpg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "image/gif": ".gif",
}
RUNTIME_HOST = "127.0.0.1"
RUNTIME_PORT = 7879
RUNTIME_URL = f"http://{RUNTIME_HOST}:{RUNTIME_PORT}"


class DeepseekRuntime:
    """Local DeepSeek runtime API supervisor used instead of terminal key scraping."""

    def __init__(self) -> None:
        self._process: subprocess.Popen | None = None
        self._lock = threading.Lock()

    def ensure_running(self, cwd: str) -> None:
        if self._health_ok():
            return
        with self._lock:
            if self._health_ok():
                return
            exe = self._find_deepseek_binary()
            if not exe:
                raise RuntimeError("deepseek runtime binary not found")
            state_dir = Path(cwd) / ".deepseek" / "state"
            state_dir.mkdir(parents=True, exist_ok=True)
            out = (state_dir / "deepseek_runtime.log").open("a", encoding="utf-8")
            err = (state_dir / "deepseek_runtime.err.log").open("a", encoding="utf-8")
            self._process = subprocess.Popen(
                [
                    exe,
                    "serve",
                    "--http",
                    "--host",
                    RUNTIME_HOST,
                    "--port",
                    str(RUNTIME_PORT),
                ],
                cwd=cwd,
                stdout=out,
                stderr=err,
                text=True,
            )
            deadline = time.time() + 10
            while time.time() < deadline:
                if self._health_ok():
                    return
                time.sleep(0.25)
            raise RuntimeError("deepseek runtime did not become healthy")

    def create_thread(self, workspace: str, title: str) -> str:
        payload = {
            "workspace": workspace,
            "mode": "agent",
            "auto_approve": True,
            "allow_shell": True,
            "title": title,
        }
        data = self._request_json("POST", "/v1/threads", payload)
        thread_id = str(data.get("id", "")).strip()
        if not thread_id:
            raise RuntimeError("deepseek runtime did not return thread id")
        return thread_id

    def send_turn(self, thread_id: str, prompt: str) -> str:
        data = self._request_json(
            "POST",
            f"/v1/threads/{thread_id}/turns",
            {"prompt": prompt},
        )
        turn = data.get("turn") if isinstance(data, dict) else None
        turn_id = str((turn or {}).get("id", "")).strip()
        if not turn_id:
            raise RuntimeError("deepseek runtime did not return turn id")
        return turn_id

    def interrupt_turn(self, thread_id: str, turn_id: str) -> None:
        self._request_json(
            "POST",
            f"/v1/threads/{thread_id}/turns/{turn_id}/interrupt",
            {},
        )

    def stream_events(self, thread_id: str, since_seq: int):
        request = urllib.request.Request(
            f"{RUNTIME_URL}/v1/threads/{thread_id}/events?since_seq={since_seq}",
            method="GET",
        )
        with urllib.request.urlopen(request, timeout=300) as response:
            event_name = ""
            data_lines: list[str] = []
            while True:
                raw = response.readline()
                if not raw:
                    break
                line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
                if line.startswith("event:"):
                    event_name = line.split(":", 1)[1].strip()
                elif line.startswith("data:"):
                    data_lines.append(line.split(":", 1)[1].strip())
                elif line == "" and data_lines:
                    try:
                        event = json.loads("\n".join(data_lines))
                    except json.JSONDecodeError:
                        event = {}
                    if event_name:
                        event["event"] = event_name
                    yield event
                    event_name = ""
                    data_lines = []

    def _request_json(self, method: str, path: str, payload: dict | None = None) -> dict:
        body = None
        headers = {}
        if payload is not None:
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            f"{RUNTIME_URL}{path}",
            data=body,
            headers=headers,
            method=method,
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8", errors="replace"))

    def _health_ok(self) -> bool:
        try:
            data = self._request_json("GET", "/health")
            return data.get("status") == "ok"
        except Exception:
            return False

    @staticmethod
    def _find_deepseek_binary() -> str | None:
        npm = Path(os.path.expandvars(r"%APPDATA%\npm"))
        downloaded = npm / "node_modules" / "deepseek-tui" / "bin" / "downloads" / "deepseek-tui.exe"
        if downloaded.exists():
            return str(downloaded)
        import shutil

        return shutil.which("deepseek-tui.exe") or shutil.which("deepseek-tui")


_RUNTIME = DeepseekRuntime()


def _ts() -> str:
    return datetime.now().strftime("%H:%M:%S")


def _log(tag: str, msg: str) -> None:
    line = f"[{_ts()}] [{tag}] {msg}"
    try:
        print(line, flush=True)
    except UnicodeEncodeError:
        safe_line = line.encode(
            getattr(sys.stdout, "encoding", None) or "utf-8",
            errors="backslashreplace",
        ).decode(
            getattr(sys.stdout, "encoding", None) or "utf-8",
            errors="replace",
        )
        print(safe_line, flush=True)


class ProjectSession:
    """Maintains a persistent deepseek-tui PTY process for real session continuity."""

    def __init__(self, project_id: str, project_dir: str):
        self.project_id = project_id
        self.project_dir = project_dir
        self.running = False
        self.writers: list = []
        self._lock = threading.Lock()
        self._state_dir = Path(project_dir) / ".deepseek" / "state"
        self._safe_project_id = self._safe_id(project_id)
        self._session_dir = self._state_dir / "sessions" / self._safe_project_id
        self._latest_session_path = self._session_dir / "latest.txt"
        self.session_id = ""
        self._runtime_thread_id = ""
        self._runtime_seq = 0
        self._current_turn_id = ""
        self._pty_child = None  # wexpect spawn object (persistent PTY)
        self._pty_exe: str | None = None
        self._init_error: str | None = None
        self._fresh_session: bool = False

    def start(self) -> bool:
        if not _RUNTIME._find_deepseek_binary():
            _log("session", f"deepseek-tui not found for {self.project_id}")
            return False
        if not Path(self.project_dir).exists():
            _log("session", f"Project path missing for {self.project_id}: {self.project_dir}")
            return False
        try:
            self.session_id = self._load_or_create_session_id()
        except Exception as exc:
            _log("session", f"Session init failed for {self.project_id}: {exc}")
            self._init_error = str(exc)
            return False
        self.running = True
        _log("session", f"Ready {self.project_id} session={self.session_id}")
        return True

    def write(self, text: str) -> None:
        prompt = text.strip()
        if not prompt or not self.running:
            return
        self._append_event("send", prompt)
        worker = threading.Thread(target=self._run_prompt, args=(prompt,), daemon=True)
        worker.start()

    def start_new_session(self) -> str:
        self.session_id = self._new_session_id()
        self._session_dir.mkdir(parents=True, exist_ok=True)
        self._latest_session_path.write_text(self.session_id, encoding="utf-8")
        self._fresh_session = True
        self._runtime_thread_id = ""
        self._runtime_seq = 0
        self._save_runtime_thread()
        self._kill_pty()
        self._broadcast("session_info", f"Новая сессия: {self.session_id}")
        return self.session_id

    def resume_session(self, session_id: str) -> bool:
        """Resume a specific session by its id."""
        sid = str(session_id).strip()
        if not sid:
            return False
        # Validate session log exists
        expected_path = self._session_dir / f"{sid}.jsonl"
        if not expected_path.exists():
            _log("session", f"Session {sid} not found for {self.project_id}, keeping current")
            return False
        self.session_id = sid
        self._load_runtime_thread()
        try:
            self._latest_session_path.write_text(sid, encoding="utf-8")
        except Exception as exc:
            _log("session", f"Failed to save latest session for {self.project_id}: {exc}")
        _log("session", f"Resumed {self.project_id} session={sid}")
        return True

    def load_history(self, limit: int = HISTORY_REPLAY_LIMIT) -> list[dict]:
        path = self._session_log_path()
        if not path.exists():
            return []
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except Exception as exc:
            _log("session", f"History load failed for {self.project_id}: {exc}")
            return []
        items: list[dict] = []
        for line in lines[-limit:]:
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(item, dict):
                items.append(item)
        return items

    def stop_current_prompt(self) -> bool:
        """Interrupt the currently running DeepSeek turn."""
        if not self._runtime_thread_id or not self._current_turn_id:
            self._broadcast("status", "Нет активного процесса DeepSeek.")
            return False
        try:
            _RUNTIME.interrupt_turn(self._runtime_thread_id, self._current_turn_id)
            self._broadcast("status", "Останавливаю DeepSeek...")
            return True
        except Exception as exc:
            _log("session", f"{self.project_id} interrupt failed: {exc}")
            return False

    def save_upload(self, filename: str, mime_type: str, data_base64: str) -> Path:
        raw = base64.b64decode(data_base64, validate=True)
        if not raw:
            raise ValueError("empty file")
        if len(raw) > MAX_UPLOAD_BYTES:
            raise ValueError("file is too large")

        vision_dir = Path(self.project_dir) / "vision"
        vision_dir.mkdir(parents=True, exist_ok=True)
        target = vision_dir / self._safe_upload_name(filename, mime_type)
        target.write_bytes(raw)
        return target

    # ── PTY-based persistent process ────────────────────────────

    def _run_prompt(self, prompt: str) -> None:
        if not self._lock.acquire(blocking=False):
            self._broadcast("status", "DeepSeek занят. Дождитесь завершения.")
            return
        try:
            if self._fresh_session:
                self._fresh_session = False
                self._runtime_thread_id = ""
                self._runtime_seq = 0
                self._save_runtime_thread()
            _log("session", f"{self.project_id} send: {prompt[:80]}")
            self._broadcast("status", "DeepSeek выполняет...")
            self._run_runtime_turn(prompt)
            self._broadcast("status", "Готово.")
        finally:
            self._current_turn_id = ""
            self._lock.release()

    def _run_runtime_turn(self, prompt: str) -> None:
        _RUNTIME.ensure_running(self.project_dir)
        if not self._runtime_thread_id:
            self._runtime_thread_id = _RUNTIME.create_thread(
                self.project_dir,
                f"{self.project_id} bridge session {self.session_id}",
            )
            self._save_runtime_thread()
            _log("session", f"{self.project_id} runtime thread={self._runtime_thread_id}")

        self._current_turn_id = _RUNTIME.send_turn(self._runtime_thread_id, prompt)
        item_parts: dict[str, list[str]] = {}
        item_kinds: dict[str, str] = {}
        for event in _RUNTIME.stream_events(self._runtime_thread_id, self._runtime_seq):
            seq = int(event.get("seq") or 0)
            if seq > self._runtime_seq:
                self._runtime_seq = seq
            event_name = str(event.get("event") or "")
            item_id = str(event.get("item_id") or "")
            payload = event.get("payload") if isinstance(event.get("payload"), dict) else {}
            if event_name == "item.delta":
                kind = str(payload.get("kind") or "")
                delta = str(payload.get("delta") or "")
                if delta:
                    if item_id:
                        item_parts.setdefault(item_id, []).append(delta)
                        item_kinds[item_id] = kind
                    _log("session", f"{self.project_id} out: {delta[:120]}")
                    self._broadcast(
                        "output",
                        delta,
                        persist=False,
                        append=True,
                        stream_id=item_id or self._current_turn_id,
                        runtime_kind=kind,
                    )
            elif event_name == "item.completed":
                item = payload.get("item") if isinstance(payload.get("item"), dict) else {}
                kind = str(item.get("kind") or item_kinds.get(item_id) or "")
                if kind == "user_message":
                    continue
                final_text = str(
                    item.get("detail")
                    or item.get("summary")
                    or "".join(item_parts.get(item_id, []))
                )
                if final_text:
                    self._broadcast(
                        "output",
                        final_text,
                        append=False,
                        final=True,
                        stream_id=item_id or self._current_turn_id,
                        runtime_kind=kind,
                    )
            elif event_name == "item.failed":
                self._broadcast("error", str(payload.get("error") or "DeepSeek item failed"))
            elif event_name in ("turn.completed", "turn.interrupted", "turn.failed", "turn.canceled"):
                self._save_runtime_thread()
                if event_name == "turn.failed":
                    self._broadcast("error", "DeepSeek turn failed")
                break

    def _ensure_pty(self, exe: str) -> None:
        """Spawn the persistent deepseek-tui PTY process if not running."""
        if self._pty_child and self._pty_child.isalive():
            return
        self._kill_pty()
        self._pty_exe = exe
        npm = Path(os.path.expandvars(r"%APPDATA%\npm"))
        js = npm / "node_modules" / "deepseek-tui" / "bin" / "deepseek-tui.js"
        is_node = exe.lower().endswith("node.exe") or exe.lower().endswith("node")
        flags = f'--yolo --no-alt-screen --skip-onboarding -w "{self.project_dir}"'
        if is_node and js.exists():
            cmd = f'"{exe}" "{js}" {flags}'
        else:
            cmd = f'"{exe}" {flags}'
        _log("session", f"{self.project_id} spawning PTY: {cmd[:100]}")
        self._pty_child = wexpect.spawn(cmd, cwd=self.project_dir, timeout=300, encoding='utf-8', codec_errors='replace')
        time.sleep(2)
        if not self._pty_child.isalive():
            startup_output = clean_line(self._pty_child.before or "")
            if startup_output:
                _log("session", f"{self.project_id} PTY exited at startup: {startup_output[:500]}")

    def _read_pty_output(self) -> None:
        """Read TUI output after sending a message, streaming cleaned lines.

        wexpect.expect([TIMEOUT]) always raises wexpect.TIMEOUT — the data
        lands in child.before *before* the exception.  Process it inside the
        except handler so we don't silently discard every line.
        """
        child = self._pty_child
        if not child:
            return
        idle_count = 0
        while idle_count < 30 and child.isalive():
            try:
                child.expect([wexpect.TIMEOUT], timeout=1)
            except wexpect.TIMEOUT:
                pass
            except Exception as exc:
                _log("session", f"{self.project_id} read error: {exc}")
                break

            # child.before holds the data received during the last expect window
            raw = child.before or ""
            if raw:
                for line in raw.split("\n"):
                    clean = clean_line(line)
                    if clean and len(clean) > 1:
                        _log("session", f"{self.project_id} out: {clean[:120]}")
                        self._broadcast("output", clean)
                        idle_count = 0
            else:
                idle_count += 1
        _log("session", f"{self.project_id} response complete (idle={idle_count})")

    def _kill_pty(self) -> None:
        """Kill the PTY process."""
        child = self._pty_child
        if child:
            try:
                child.terminate(force=True)
            except Exception:
                pass
            self._pty_child = None

    @staticmethod
    def _safe_upload_name(filename: str, mime_type: str) -> str:
        original = Path(filename or "").name
        stem = Path(original).stem
        ext = Path(original).suffix.lower()
        if ext not in {".jpg", ".jpeg", ".png", ".webp", ".gif"}:
            ext = IMAGE_EXTENSIONS.get(mime_type.lower(), ".jpg")
        safe_stem = re.sub(r"[^A-Za-z0-9_.-]+", "_", stem).strip("._")
        if not safe_stem:
            safe_stem = "photo"
        stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        return f"{safe_stem}_{stamp}{ext}"

    def _broadcast(self, msg_type: str, text: str, persist: bool = True, **extra) -> None:
        event = (
            self._append_event(msg_type, text, **extra)
            if persist
            else self._make_event(msg_type, text, **extra)
        )
        if not self.writers:
            _log("session", f"{self.project_id} broadcast with 0 writers!")
            return
        msg = json.dumps(event, ensure_ascii=False) + "\n"
        data = msg.encode("utf-8")
        dead = []
        for writer in self.writers:
            try:
                writer.write(data)
            except Exception:
                dead.append(writer)
        for writer in dead:
            self.writers.remove(writer)

    def stop(self) -> None:
        self.running = False
        self._kill_pty()

    def send_session_info(self, writer) -> None:
        writer.write(
            json.dumps(
                {
                    "type": "session_info",
                    "text": f"Сессия: {self.session_id}",
                    "session_id": self.session_id,
                    "project_id": self.project_id,
                },
                ensure_ascii=False,
            ).encode("utf-8")
            + b"\n"
        )

    def send_history(self, writer, limit: int = HISTORY_REPLAY_LIMIT) -> None:
        writer.write(
            json.dumps(
                {
                    "type": "history",
                    "project_id": self.project_id,
                    "session_id": self.session_id,
                    "messages": self.load_history(limit=limit),
                },
                ensure_ascii=False,
            ).encode("utf-8")
            + b"\n"
        )

    def _make_event(self, msg_type: str, text: str, **extra) -> dict:
        event = {
            "type": msg_type,
            "text": text,
            "project_id": self.project_id,
            "session_id": self.session_id,
            "ts": int(time.time()),
        }
        event.update(extra)
        return event

    def _append_event(self, msg_type: str, text: str, **extra) -> dict:
        event = self._make_event(msg_type, text, **extra)
        try:
            self._session_dir.mkdir(parents=True, exist_ok=True)
            with self._session_log_path().open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(event, ensure_ascii=False) + "\n")
        except Exception as exc:
            _log("session", f"History save failed for {self.project_id}: {exc}")
        return event

    def _session_log_path(self) -> Path:
        return self._session_dir / f"{self.session_id}.jsonl"

    def _runtime_thread_path(self) -> Path:
        return self._session_dir / f"{self.session_id}.runtime.json"

    def _load_runtime_thread(self) -> None:
        self._runtime_thread_id = ""
        self._runtime_seq = 0
        path = self._runtime_thread_path()
        if not path.exists():
            return
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:
            _log("session", f"Runtime thread load failed for {self.project_id}: {exc}")
            return
        self._runtime_thread_id = str(data.get("thread_id") or "").strip()
        self._runtime_seq = int(data.get("seq") or 0)

    def _save_runtime_thread(self) -> None:
        if not self.session_id:
            return
        try:
            self._session_dir.mkdir(parents=True, exist_ok=True)
            self._runtime_thread_path().write_text(
                json.dumps(
                    {
                        "thread_id": self._runtime_thread_id,
                        "seq": self._runtime_seq,
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
        except Exception as exc:
            _log("session", f"Runtime thread save failed for {self.project_id}: {exc}")

    def _load_or_create_session_id(self) -> str:
        try:
            if self._latest_session_path.exists():
                raw = self._latest_session_path.read_text(encoding="utf-8").strip()
                if re.fullmatch(r"[0-9]{8}_[0-9]{6}_[A-Za-z0-9_-]{8}", raw):
                    self.session_id = raw
                    self._load_runtime_thread()
                    return raw
        except Exception as exc:
            _log("session", f"Latest session load failed for {self.project_id}: {exc}")
        session_id = self._new_session_id()
        try:
            self._session_dir.mkdir(parents=True, exist_ok=True)
            self._latest_session_path.write_text(session_id, encoding="utf-8")
        except Exception as exc:
            _log("session", f"Latest session save failed for {self.project_id}: {exc}")
        self.session_id = session_id
        self._load_runtime_thread()
        return session_id

    @staticmethod
    def _new_session_id() -> str:
        return f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:8]}"

    @staticmethod
    def _safe_id(value: str) -> str:
        safe_id = re.sub(r"[^A-Za-z0-9_.-]+", "_", value).strip("._")
        return safe_id or "project"

    @staticmethod
    def _get_deepseek_exe() -> str | None:
        import shutil

        # Prefer .exe (native, no encoding issues)
        exe = shutil.which("deepseek-tui.exe")
        if exe:
            return exe

        # .cmd wrapper breaks Cyrillic args — use node directly instead
        npm = Path(os.path.expandvars(r"%APPDATA%\npm"))
        js = npm / "node_modules" / "deepseek-tui" / "bin" / "deepseek-tui.js"
        node = shutil.which("node") or "node"
        if js.exists():
            return node  # Return 'node', js path handled elsewhere

        # Fallback to .cmd
        cmd = shutil.which("deepseek-tui.cmd") or shutil.which("deepseek-tui")
        if cmd:
            return cmd
        for name in ("deepseek-tui.cmd", "deepseek-tui.exe", "deepseek-tui"):
            candidate = npm / name
            if candidate.exists():
                return str(candidate)
        return None


class TunnelClient:
    def __init__(self, tunnel_host: str, tunnel_port: int = 9877):
        self.tunnel_host = tunnel_host
        self.tunnel_port = tunnel_port
        self._sessions: Dict[str, ProjectSession] = {}
        self._tasks: list = []

    def _load_projects(self) -> list:
        candidates = [
            Path("family_data/nik/projects.json"),
            Path(os.getcwd()) / "family_data/nik/projects.json",
        ]
        for path in candidates:
            if path.exists():
                try:
                    data = json.loads(path.read_text(encoding="utf-8"))
                    return data.get("projects", DEFAULT_PROJECTS)
                except Exception:
                    pass
        return DEFAULT_PROJECTS

    async def start(self) -> None:
        projects = self._load_projects()
        _log("tunnel", f"Connecting to {self.tunnel_host}:{self.tunnel_port} ({len(projects)} projects)")
        for project in projects:
            task = asyncio.create_task(self._register_project(project))
            self._tasks.append(task)
        if self._tasks:
            await asyncio.gather(*self._tasks, return_exceptions=True)

    async def _register_project(self, project: dict) -> None:
        project_id = str(project["id"])
        project_dir = str(project["path"])
        reconnect_attempt = 0
        session: ProjectSession | None = None
        while True:
            try:
                # Small delay before reconnecting so the tunnel server's
                # old relay task can finish its cleanup and avoid the
                # race condition that orphans the new registration.
                if reconnect_attempt > 0:
                    await asyncio.sleep(3.0)
                reader, writer = await asyncio.wait_for(
                    asyncio.open_connection(
                        self.tunnel_host,
                        self.tunnel_port,
                        limit=MAX_TUNNEL_LINE_BYTES,
                    ),
                    timeout=10,
                )
                writer.write(
                    json.dumps(
                        {"type": "register", "project_id": project_id},
                        ensure_ascii=False,
                    ).encode("utf-8")
                    + b"\n"
                )
                await writer.drain()
                _log("tunnel", f"{project_id} registered (attempt {reconnect_attempt + 1})")
                reconnect_attempt = 0

                session = self._sessions.get(project_id)
                if not session or not session.running:
                    try:
                        session = ProjectSession(project_id, project_dir)
                    except Exception as exc:
                        _log("tunnel", f"{project_id} session init crash: {exc}")
                        session = None
                    if session and session.start():
                        self._sessions[project_id] = session
                    elif session:
                        error_text = session._init_error or "неизвестная ошибка"
                        session._broadcast(
                            "error",
                            f"Не удалось запустить сессию проекта {project_id}: {error_text}",
                        )
                        session = None

                if session and session.running:
                    # Close old dead writers from previous connections
                    for old in list(session.writers):
                        try:
                            old.close()
                        except Exception:
                            pass
                    session.writers.clear()
                    session.writers.append(writer)

                # Send projects list to mobile so it can update its UI
                projects_data = self._load_projects()
                writer.write(
                    json.dumps(
                        {"type": "projects", "projects": projects_data},
                        ensure_ascii=False,
                    ).encode("utf-8")
                    + b"\n"
                )
                await writer.drain()

                while True:
                    line = await reader.readline()
                    if not line:
                        break
                    raw = line.decode("utf-8", "replace").strip()
                    if not raw:
                        continue
                    try:
                        msg = json.loads(raw)
                    except json.JSONDecodeError:
                        if session and session.running:
                            session.write(raw)
                        continue

                    if msg.get("type") in ("pong", "ping", "list", "status"):
                        continue
                    if msg.get("type") == "mobile_attached":
                        if session and session.running:
                            req_session_id = str(msg.get('session_id', '')).strip()
                            if req_session_id:
                                session.resume_session(req_session_id)
                            session.send_session_info(writer)
                            session.send_history(writer)
                        continue
                    if msg.get("type") == "new_session":
                        if session and session.running:
                            session.start_new_session()
                            session.send_history(writer)
                        continue
                    if msg.get("type") == "stop":
                        if session and session.running:
                            session.stop_current_prompt()
                        continue
                    if msg.get("type") == "upload_file":
                        if not session or not session.running:
                            continue
                        filename = str(msg.get("filename", "photo.jpg"))
                        mime_type = str(msg.get("mime_type", "image/jpeg"))
                        data_base64 = str(msg.get("data_base64", ""))
                        caption = str(msg.get("caption", "")).strip()
                        try:
                            saved = session.save_upload(filename, mime_type, data_base64)
                        except Exception as exc:
                            session._broadcast(
                                "error",
                                f"Не удалось сохранить фото в vision: {exc}",
                            )
                            continue
                        rel_path = saved.relative_to(Path(project_dir))
                        rel_text = rel_path.as_posix()
                        session._broadcast(
                            "status",
                            f"Фото сохранено: {rel_text}",
                        )
                        # Echo image data back so mobile can display it inline
                        session._broadcast(
                            "image",
                            str(saved.name),
                            data_base64=data_base64,
                            mime_type=mime_type,
                            filename=str(saved.name),
                        )
                        if caption:
                            session.write(f"{caption}\n\nФайл фото: {rel_text}")
                        continue
                    if msg.get("type") == "list_files":
                        writer.write(
                            json.dumps(
                                self._list_files(project_id, project_dir, msg),
                                ensure_ascii=False,
                            ).encode("utf-8")
                            + b"\n"
                        )
                        await writer.drain()
                        continue
                    if msg.get("type") == "read_file":
                        writer.write(
                            json.dumps(
                                self._read_file(project_id, project_dir, msg),
                                ensure_ascii=False,
                            ).encode("utf-8")
                            + b"\n"
                        )
                        await writer.drain()
                        continue
                    if msg.get("type") == "audio_zones":
                        try:
                            from audio_zones import handle_bridge_action

                            result = handle_bridge_action(msg)
                            writer.write(
                                json.dumps(
                                    {
                                        "type": "audio_zones_result",
                                        "project_id": project_id,
                                        "result": result,
                                    },
                                    ensure_ascii=False,
                                ).encode("utf-8")
                                + b"\n"
                            )
                            await writer.drain()
                        except Exception as exc:
                            _log("tunnel", f"audio_zones error: {exc}")
                            writer.write(
                                json.dumps(
                                    {
                                        "type": "audio_zones_result",
                                        "project_id": project_id,
                                        "result": {"error": str(exc)},
                                    },
                                    ensure_ascii=False,
                                ).encode("utf-8")
                                + b"\n"
                            )
                            await writer.drain()
                        continue
                    if msg.get("type") == "send":
                        text = str(msg.get("text", ""))
                        if text and session and session.running:
                            _log("tunnel", f"{project_id} <- {text[:80]}")
                            session.write(text)
            except Exception as exc:
                delay = min(8, RECONNECT_DELAY_SECONDS * (2 ** reconnect_attempt))
                _log("tunnel", f"{project_id} error: {exc}. Retry in {delay}s")
                await asyncio.sleep(delay)
                reconnect_attempt += 1
                continue
            reconnect_attempt = 0
            await asyncio.sleep(RECONNECT_DELAY_SECONDS)

    def _list_files(
        self, project_id: str, project_dir: str, msg: dict
    ) -> dict:
        """Return a ProjectFileNode tree for the requested path."""
        import os as _os

        base = Path(project_dir).resolve()
        rel = str(msg.get("path", "")).strip().lstrip("/").lstrip("\\")
        recursive = bool(msg.get("recursive", False))
        target = (base / rel).resolve() if rel else base

        # Directories to skip: dependency / build / cache folders
        # that are never interesting and slow down the file manager.
        _SKIP_DIRS: set[str] = {
            "node_modules",
            "vendor",
            ".venv",
            "venv",
            ".tox",
            ".eggs",
            "__pycache__",
            ".pytest_cache",
            ".mypy_cache",
            ".ruff_cache",
            ".git",
            ".dart_tool",
            "build",
            "dist",
            "target",
            ".next",
            ".nuxt",
            ".output",
            "bower_components",
            ".gradle",
            ".idea",
            ".vscode",
            ".vs",
            "packages",
            "Pods",
            ".symlinks",
            "storage",
            "coverage",
            ".nyc_output",
            ".sass-cache",
            ".parcel-cache",
            ".turbo",
            ".cache",
            "cache",
            ".angular",
            "tmp",
            ".serverless",
            ".terraform",
            ".cdk.staging",
            ".vercel",
            ".netlify",
        }
        _SKIP_PATHS: set[str] = {
            "bootstrap/cache",
        }

        # Security: stay inside project directory
        try:
            target.relative_to(base)
        except ValueError:
            return {"type": "files", "project_id": project_id, "files": [], "path": rel}

        def _build_node(entry: Path, depth: int = 0) -> dict | None:
            name = entry.name
            if name in _SKIP_DIRS:
                return None
            # Skip hidden files and deepseek internal state
            if name.startswith(".") or name == "__pycache__":
                if name != ".gitignore":  # Keep .gitignore visible
                    return None
            try:
                rel_path = entry.relative_to(base).as_posix()
            except ValueError:
                return None
            if rel_path in _SKIP_PATHS:
                return None
            if entry.is_dir():
                children = []
                if recursive:
                    try:
                        for child in sorted(entry.iterdir()):
                            node = _build_node(child, depth + 1)
                            if node is not None:
                                children.append(node)
                    except PermissionError:
                        pass
                return {
                    "name": name,
                    "path": rel_path,
                    "is_dir": True,
                    "size": 0,
                    "children": children,
                }
            else:
                try:
                    size = entry.stat().st_size
                except OSError:
                    size = 0
                return {
                    "name": name,
                    "path": rel_path,
                    "is_dir": False,
                    "size": size,
                }

        if not target.exists():
            return {"type": "files", "project_id": project_id, "files": [], "path": rel}

        if target.is_dir():
            nodes = []
            try:
                for child in sorted(target.iterdir()):
                    node = _build_node(child)
                    if node is not None:
                        nodes.append(node)
            except PermissionError:
                pass
            # Sort: directories first
            nodes.sort(key=lambda n: (not n["is_dir"], n["name"].lower()))
            return {"type": "files", "project_id": project_id, "files": nodes, "path": rel}
        else:
            node = _build_node(target)
            return {
                "type": "files",
                "project_id": project_id,
                "files": [node] if node else [],
                "path": rel,
            }

    def _read_file(
        self, project_id: str, project_dir: str, msg: dict
    ) -> dict:
        """Read a file's content and return it as text (up to 64 KB)."""
        base = Path(project_dir).resolve()
        rel = str(msg.get("path", "")).strip().lstrip("/").lstrip("\\")
        target = (base / rel).resolve() if rel else None
        if target is None or not target.exists() or not target.is_file():
            return {"type": "file_content", "project_id": project_id, "path": rel, "text": "", "error": "File not found"}
        try:
            target.relative_to(base)
        except ValueError:
            return {"type": "file_content", "project_id": project_id, "path": rel, "text": "", "error": "Access denied"}
        try:
            raw = target.read_bytes()
            # Try UTF-8 first, fallback to latin-1
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                text = raw.decode("latin-1")
            # Truncate to 64 KB
            if len(text) > 65536:
                text = text[:65536] + "\n... (truncated)"
            return {"type": "file_content", "project_id": project_id, "path": rel, "text": text, "size": len(raw)}
        except Exception as exc:
            return {"type": "file_content", "project_id": project_id, "path": rel, "text": "", "error": str(exc)}

    async def stop(self) -> None:
        for task in self._tasks:
            task.cancel()
        for session in self._sessions.values():
            session.stop()


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tunnel", default="", metavar="HOST:PORT")
    args = parser.parse_args()
    if args.tunnel:
        host, port = args.tunnel.split(":")
        client = TunnelClient(host, int(port) if port else 9877)
        try:
            await client.start()
        except KeyboardInterrupt:
            print("\nDone", flush=True)
        finally:
            await client.stop()
    else:
        print("Use --tunnel HOST:PORT")


if __name__ == "__main__":
    asyncio.run(main())
