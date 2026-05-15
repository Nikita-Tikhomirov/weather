"""
Project Bridge - runs DeepSeek TUI prompts for project chats.

The full-screen TUI does not behave like a line-oriented shell when driven over
stdin: prompts stay in its Draft box and screen updates often have no newlines.
The bridge therefore uses DeepSeek TUI's exec mode, which reliably runs prompts
and tools for a workspace.

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
import uuid
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


def clean_line(text: str) -> str:
    """Strip terminal control sequences and cosmetic frame-only lines."""
    s = ANSI_RE.sub("", text).strip()
    if not s:
        return ""
    if s.startswith(("─", "│", "┌", "└")):
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

MAX_MEMORY_TURNS = 12
MAX_MEMORY_CHARS = 12000
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


def _ts() -> str:
    return datetime.now().strftime("%H:%M:%S")


def _log(tag: str, msg: str) -> None:
    print(f"[{_ts()}] [{tag}] {msg}", flush=True)


class ProjectSession:
    """Serializes DeepSeek exec prompts for one project."""

    def __init__(self, project_id: str, project_dir: str):
        self.project_id = project_id
        self.project_dir = project_dir
        self.running = False
        self.writers: list = []
        self._lock = threading.Lock()
        self._state_dir = Path(project_dir) / ".deepseek" / "state"
        self._memory_path = self._state_dir / f"bridge_memory_{self._safe_id(project_id)}.json"
        self._safe_project_id = self._safe_id(project_id)
        self._session_dir = self._state_dir / "sessions" / self._safe_project_id
        self._latest_session_path = self._session_dir / "latest.txt"
        self.session_id = ""
        self._current_proc: subprocess.Popen | None = None
        # Defer session-id loading to start() so we can report errors
        self._init_error: str | None = None

    def start(self) -> bool:
        if not self._get_deepseek_exe():
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
        self._broadcast("session_info", f"Новая сессия: {self.session_id}")
        return self.session_id

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
        proc = self._current_proc
        if not proc or proc.poll() is not None:
            self._broadcast("status", "Нет активного процесса DeepSeek.")
            return False
        proc.terminate()
        self._broadcast("status", "Останавливаю DeepSeek...")
        return True

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

    def _run_prompt(self, prompt: str) -> None:
        if not self._lock.acquire(blocking=False):
            self._broadcast(
                "status",
                "DeepSeek занят. Дождитесь завершения текущего запроса.",
            )
            return

        try:
            exe = self._get_deepseek_exe()
            if not exe:
                self._broadcast("error", "deepseek-tui не найден в PATH")
                return

            exec_prompt = self._compact_for_cli(self._build_prompt_with_memory(prompt))
            npm = Path(os.path.expandvars(r"%APPDATA%\npm"))
            js = npm / "node_modules" / "deepseek-tui" / "bin" / "deepseek-tui.js"
            is_node = exe.lower().endswith("node.exe") or exe.lower().endswith("node")
            if is_node and js.exists():
                argv = [exe, str(js), "--yolo", "-w", self.project_dir, "exec", "--auto", exec_prompt]
            else:
                argv = [exe, "--yolo", "-w", self.project_dir, "exec", "--auto", exec_prompt]
            _log("session", f"{self.project_id} exec: {prompt[:80]}")
            self._broadcast("status", "DeepSeek начал выполнение...")

            try:
                proc = subprocess.Popen(
                    argv,
                    cwd=self.project_dir,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    bufsize=1,
                )
                self._current_proc = proc
            except Exception as exc:
                self._broadcast("error", f"Не удалось запустить deepseek-tui: {exc}")
                return

            emitted = False
            output_lines = []
            assert proc.stdout is not None
            for raw_line in proc.stdout:
                clean = clean_line(raw_line)
                if clean:
                    emitted = True
                    output_lines.append(clean)
                    _log("session", f"{self.project_id} out: {clean[:120]}")
                    self._broadcast("output", clean)

            code = proc.wait()
            if code == 0:
                self._remember(prompt, "\n".join(output_lines))
                if not emitted:
                    self._broadcast(
                        "status",
                        "DeepSeek завершил выполнение без текстового вывода.",
                    )
                self._broadcast("status", "DeepSeek завершил выполнение.")
            else:
                self._broadcast("error", f"deepseek-tui завершился с кодом {code}")
        finally:
            self._current_proc = None
            self._lock.release()

    def _build_prompt_with_memory(self, prompt: str) -> str:
        turns = self._load_memory()
        if not turns:
            return prompt

        context_parts = []
        total_chars = 0
        for turn in reversed(turns[-MAX_MEMORY_TURNS:]):
            user_text = str(turn.get("user", "")).strip()
            assistant_text = str(turn.get("assistant", "")).strip()
            if not user_text and not assistant_text:
                continue
            block = f"Пользователь: {user_text}\nDeepSeek: {assistant_text}"
            total_chars += len(block)
            if total_chars > MAX_MEMORY_CHARS:
                break
            context_parts.append(block)

        if not context_parts:
            return prompt

        context = " || ".join(reversed(context_parts))
        return (
            "Ответь на текущий запрос пользователя. Используй память только как "
            "контекст, если текущий запрос ссылается на прошлые сообщения. "
            "Текущий запрос пользователя: "
            f"{prompt} "
            "Память предыдущих сообщений в этом проектном чате: "
            f"{context}"
        )

    @staticmethod
    def _compact_for_cli(text: str) -> str:
        return re.sub(r"\s+", " ", text).strip()

    def _remember(self, user_text: str, assistant_text: str) -> None:
        turns = self._load_memory()
        turns.append(
            {
                "user": user_text,
                "assistant": assistant_text,
                "ts": int(__import__("time").time()),
            }
        )
        turns = turns[-MAX_MEMORY_TURNS:]
        try:
            self._memory_path.parent.mkdir(parents=True, exist_ok=True)
            self._memory_path.write_text(
                json.dumps(turns, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )
        except Exception as exc:
            _log("session", f"Memory save failed for {self.project_id}: {exc}")

    def _load_memory(self) -> list:
        try:
            if not self._memory_path.exists():
                return []
            data = json.loads(self._memory_path.read_text(encoding="utf-8"))
            return data if isinstance(data, list) else []
        except Exception as exc:
            _log("session", f"Memory load failed for {self.project_id}: {exc}")
            return []

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

    def _broadcast(self, msg_type: str, text: str, **extra) -> None:
        event = self._append_event(msg_type, text, **extra)
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
        self.stop_current_prompt()

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

    def _append_event(self, msg_type: str, text: str, **extra) -> dict:
        event = {
            "type": msg_type,
            "text": text,
            "project_id": self.project_id,
            "session_id": self.session_id,
            "ts": int(time.time()),
        }
        event.update(extra)
        try:
            self._session_dir.mkdir(parents=True, exist_ok=True)
            with self._session_log_path().open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(event, ensure_ascii=False) + "\n")
        except Exception as exc:
            _log("session", f"History save failed for {self.project_id}: {exc}")
        return event

    def _session_log_path(self) -> Path:
        return self._session_dir / f"{self.session_id}.jsonl"

    def _load_or_create_session_id(self) -> str:
        try:
            if self._latest_session_path.exists():
                raw = self._latest_session_path.read_text(encoding="utf-8").strip()
                if re.fullmatch(r"[0-9]{8}_[0-9]{6}_[A-Za-z0-9_-]{8}", raw):
                    return raw
        except Exception as exc:
            _log("session", f"Latest session load failed for {self.project_id}: {exc}")
        session_id = self._new_session_id()
        try:
            self._session_dir.mkdir(parents=True, exist_ok=True)
            self._latest_session_path.write_text(session_id, encoding="utf-8")
        except Exception as exc:
            _log("session", f"Latest session save failed for {self.project_id}: {exc}")
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

        # Security: stay inside project directory
        try:
            target.relative_to(base)
        except ValueError:
            return {"type": "files", "project_id": project_id, "files": [], "path": rel}

        def _build_node(entry: Path, depth: int = 0) -> dict | None:
            # Skip hidden files and deepseek internal state
            name = entry.name
            if name.startswith(".") or name == "__pycache__":
                if name != ".gitignore":  # Keep .gitignore visible
                    return None
            try:
                rel_path = entry.relative_to(base).as_posix()
            except ValueError:
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
