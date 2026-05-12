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
import json
import os
import re
import subprocess
import sys
import threading
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


class ProjectSession:
    """Serializes DeepSeek exec prompts for one project."""

    def __init__(self, project_id: str, project_dir: str):
        self.project_id = project_id
        self.project_dir = project_dir
        self.running = False
        self.writers: list = []
        self._lock = threading.Lock()
        self._memory_path = self._build_memory_path(project_id)

    def start(self) -> bool:
        if not self._get_deepseek_exe():
            print(f"[session] deepseek-tui not found for {self.project_id}", flush=True)
            return False
        if not Path(self.project_dir).exists():
            print(
                f"[session] Project path missing for {self.project_id}: {self.project_dir}",
                flush=True,
            )
            return False
        self.running = True
        print(f"[session] Ready {self.project_id}", flush=True)
        return True

    def write(self, text: str) -> None:
        prompt = text.strip()
        if not prompt or not self.running:
            return
        worker = threading.Thread(target=self._run_prompt, args=(prompt,), daemon=True)
        worker.start()

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
            argv = [exe, "-w", self.project_dir, "exec", "--auto", exec_prompt]
            print(f"[session] {self.project_id} exec: {prompt[:80]}", flush=True)
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
                    print(
                        f"[session] {self.project_id} out: {clean[:120]}",
                        flush=True,
                    )
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
            print(f"[session] Memory save failed for {self.project_id}: {exc}", flush=True)

    def _load_memory(self) -> list:
        try:
            if not self._memory_path.exists():
                return []
            data = json.loads(self._memory_path.read_text(encoding="utf-8"))
            return data if isinstance(data, list) else []
        except Exception as exc:
            print(f"[session] Memory load failed for {self.project_id}: {exc}", flush=True)
            return []

    @staticmethod
    def _build_memory_path(project_id: str) -> Path:
        safe_id = re.sub(r"[^A-Za-z0-9_.-]+", "_", project_id).strip("._")
        if not safe_id:
            safe_id = "project"
        return Path(".deepseek") / "state" / f"bridge_memory_{safe_id}.json"

    def _broadcast(self, msg_type: str, text: str) -> None:
        if not self.writers:
            print(
                f"[session] {self.project_id} broadcast with 0 writers!",
                flush=True,
            )
            return
        msg = json.dumps({"type": msg_type, "text": text}, ensure_ascii=False) + "\n"
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

    @staticmethod
    def _get_deepseek_exe() -> str | None:
        import shutil

        exe = shutil.which("deepseek-tui") or shutil.which("deepseek-tui.cmd")
        if exe:
            return exe

        npm = Path(os.path.expandvars(r"%APPDATA%\npm"))
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
        print(f"Tunnel -> {self.tunnel_host}:{self.tunnel_port}", flush=True)
        for project in projects:
            task = asyncio.create_task(self._register_project(project))
            self._tasks.append(task)
        if self._tasks:
            await asyncio.gather(*self._tasks, return_exceptions=True)

    async def _register_project(self, project: dict) -> None:
        project_id = str(project["id"])
        project_dir = str(project["path"])
        while True:
            try:
                reader, writer = await asyncio.wait_for(
                    asyncio.open_connection(self.tunnel_host, self.tunnel_port),
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
                print(f"[tunnel] {project_id} registered", flush=True)

                session = self._sessions.get(project_id)
                if not session or not session.running:
                    session = ProjectSession(project_id, project_dir)
                    if session.start():
                        self._sessions[project_id] = session

                if session and session.running and writer not in session.writers:
                    session.writers.append(writer)

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
                    if msg.get("type") == "send":
                        text = str(msg.get("text", ""))
                        if text and session and session.running:
                            print(
                                f"[tunnel] {project_id} <- {text[:80]}",
                                flush=True,
                            )
                            session.write(text)
            except Exception as exc:
                print(f"[tunnel] {project_id} err: {exc}. Retry 10s...", flush=True)
            await asyncio.sleep(10)

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
