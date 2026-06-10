from __future__ import annotations

import argparse
import asyncio
import json
import base64
import contextlib
import io
import mimetypes
import os
import re
import signal
import socket
import subprocess
import sys
import threading
import time
import urllib.request
import urllib.error
import uuid
from pathlib import Path
from typing import Any, Callable, Iterable, Iterator

from agent_policy import (
    PROTECTED_COMMANDS,
    command_allowed_by_policy,
    validate_policy_ticket,
)


RECONNECT_DELAY_SECONDS = 5
TUNNEL_HEARTBEAT_SECONDS = 30
MAX_TUNNEL_LINE_BYTES = 32 * 1024 * 1024
ALLOWED_CODEWHALE_PROVIDERS = {
    "",
    "deepseek",
    "nvidia-nim",
    "openai",
    "atlascloud",
    "wanjie-ark",
    "openrouter",
    "novita",
    "fireworks",
    "moonshot",
    "sglang",
    "vllm",
    "ollama",
    "xiaomi",
}
ALLOWED_CODEWHALE_APPROVAL_POLICIES = {"", "untrusted", "on-failure", "on-request", "never"}
ALLOWED_CODEWHALE_SANDBOX_MODES = {"", "read-only", "workspace-write", "danger-full-access"}
CODEWHALE_BUILTIN_SKILLS = {
    "cost-first-hybrid": "use local Ollama first, escalate to DeepSeek",
    "delegate": "strategic multi-step delegation via sub-agents",
    "documents": "create/edit/inspect DOCX files",
    "feishu": "Feishu/Lark bots, docs, sheets, bitables",
    "mcp-builder": "build MCP servers for CodeWhale",
    "pdf": "read/extract/split/merge PDFs",
    "plugin-creator": "scaffold local CodeWhale plugins",
    "presentations": "create/edit PPTX decks",
    "skill-creator": "create or improve CodeWhale skills",
    "skill-installer": "install community skills from GitHub",
    "spreadsheets": "create/edit XLSX, CSV, TSV",
    "superpowers-lite": "coding tasks: plan, draft, review, verify",
    "v4-best-practices": "rules for DeepSeek V4 multi-step tasks",
    "vision": "inspect screenshots via local Ollama vision",
    "web-screenshot": "capture web pages to vision/ folder",
}
CODEWHALE_PROCESS_NAMES = {
    "cmd.exe",
    "node.exe",
    "codewhale.exe",
    "codewhale-tui.exe",
}


def _background_creation_flags() -> int:
    if sys.platform != "win32":
        return 0
    return (
        getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
        | getattr(subprocess, "CREATE_NO_WINDOW", 0)
    )


def _resolve_codewhale_cmd(command: str) -> str:
    if command and (Path(command).exists() or "\\" in command or "/" in command):
        return command
    candidates = [
        Path(os.environ.get("APPDATA", "")) / "npm" / "codewhale.cmd",
        Path.home() / "AppData" / "Roaming" / "npm" / "codewhale.cmd",
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    return command


def _resolve_ollama_cmd(command: str = "ollama") -> str:
    configured = str(os.environ.get("OLLAMA_CMD") or "").strip()
    if configured:
        return configured
    if command and (Path(command).exists() or "\\" in command or "/" in command):
        return command
    candidates = [
        Path.home() / "AppData" / "Local" / "Programs" / "Ollama" / "ollama.exe",
        Path.home() / "AppData" / "Local" / "Microsoft" / "WindowsApps" / "ollama.cmd",
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    return command


def _quote_powershell_string(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def _find_codewhale_process_ids(tokens: list[str]) -> list[int]:
    cleaned_tokens = [str(token).strip() for token in tokens if str(token).strip()]
    if not cleaned_tokens or sys.platform != "win32":
        return []
    token_array = ", ".join(_quote_powershell_string(token) for token in cleaned_tokens)
    name_array = ", ".join(
        _quote_powershell_string(name) for name in sorted(CODEWHALE_PROCESS_NAMES)
    )
    script = f"""
$tokens = @({token_array})
$names = @({name_array})
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
  Where-Object {{
    $cmd = $_.CommandLine
    if (-not $cmd) {{ return $false }}
    if ($names -notcontains $_.ProcessName) {{ return $false }}
    foreach ($token in $tokens) {{
      if ($cmd -notlike ('*' + $token + '*')) {{ return $false }}
    }}
    return $true
  }} |
  ForEach-Object {{ $_.ProcessId }}
"""
    try:
        result = subprocess.run(
            [
                os.path.join(
                    os.environ.get("SystemRoot", r"C:\Windows"),
                    "System32",
                    "WindowsPowerShell",
                    "v1.0",
                    "powershell.exe",
                ),
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-Command",
                script,
            ],
            capture_output=True,
            text=True,
            timeout=10,
            check=False,
        )
    except Exception:
        return []
    pids: list[int] = []
    for line in result.stdout.splitlines():
        text = line.strip()
        if text.isdigit():
            pids.append(int(text))
    return pids


def _now_ms() -> int:
    return int(time.time() * 1000)


def _safe_id(name: str) -> str:
    base = re.sub(r"[^a-z0-9]+", "-", name.strip().lower())
    base = base.strip("-")
    return base or f"workspace-{_now_ms()}"


def _safe_folder_name(name: str) -> str:
    cleaned = re.sub(r'[<>:"/\\|?*\x00-\x1f]', " ", name.strip())
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    if not cleaned:
        raise ValueError("workspace name is required")
    return cleaned


def _safe_upload_name(filename: str, mime_type: str) -> str:
    cleaned = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", filename.strip())
    cleaned = cleaned.strip(" ._") or "file"
    stem = Path(cleaned).stem or "file"
    suffix = Path(cleaned).suffix
    if not suffix:
        suffix = mimetypes.guess_extension(mime_type.split(";")[0].strip()) or ".bin"
    return f"{_safe_id(stem)}-{uuid.uuid4().hex[:8]}{suffix.lower()}"


def _guess_mime_type(filename: str) -> str:
    lower = filename.lower()
    if lower.endswith(".md"):
        return "text/markdown"
    if lower.endswith(".txt"):
        return "text/plain"
    if lower.endswith(".png"):
        return "image/png"
    if lower.endswith(".jpg") or lower.endswith(".jpeg"):
        return "image/jpeg"
    if lower.endswith(".pdf"):
        return "application/pdf"
    return mimetypes.guess_type(filename)[0] or "application/octet-stream"


class WorkspaceRegistry:
    def __init__(self, desktop_root: Path, state_dir: Path) -> None:
        self.desktop_root = desktop_root.resolve()
        self.state_dir = state_dir.resolve()
        self.path = self.state_dir / "workspaces.json"
        self.desktop_root.mkdir(parents=True, exist_ok=True)
        self.state_dir.mkdir(parents=True, exist_ok=True)

    def list_workspaces(self) -> list[dict[str, Any]]:
        return [dict(item) for item in self._load()]

    def list_folders(self, folder: Path | None = None) -> dict[str, Any]:
        target = (folder or self.desktop_root).resolve()
        self._assert_under_desktop(target)
        if not target.exists() or not target.is_dir():
            raise ValueError("folder does not exist")

        folders = []
        for child in sorted(target.iterdir(), key=lambda item: item.name.lower()):
            if not child.is_dir() or child.name.startswith("."):
                continue
            folders.append({"name": child.name, "path": str(child.resolve())})

        parent = None
        if target != self.desktop_root:
            parent = str(target.parent.resolve())
        return {
            "path": str(target),
            "parent": parent,
            "folders": folders,
        }

    def discover_workspaces(self) -> list[dict[str, Any]]:
        """Scan desktop for existing CodeWhale workspace folders and auto-register them."""
        discovered: list[dict[str, Any]] = []
        existing_paths = {Path(item["path"]).resolve() for item in self._load()}

        try:
            for child in sorted(self.desktop_root.iterdir()):
                if not child.is_dir() or child.name.startswith("."):
                    continue
                dot_dir = child / ".deepseek"
                if not dot_dir.exists() or not dot_dir.is_dir():
                    continue
                resolved = child.resolve()
                if resolved in existing_paths:
                    continue
                try:
                    workspace = self._new_workspace(name=child.name, folder=resolved)
                    items = self._load()
                    items.append(workspace)
                    self._save(items)
                    discovered.append(dict(workspace))
                except Exception:
                    continue
        except OSError:
            pass

        return discovered

    def create_workspace(self, name: str) -> dict[str, Any]:
        folder_name = _safe_folder_name(name)
        folder = self._unique_folder(self.desktop_root / folder_name)
        folder.mkdir(parents=True, exist_ok=False)
        workspace = self._new_workspace(name=folder_name, folder=folder)
        items = self._load()
        items.append(workspace)
        self._save(items)
        return dict(workspace)

    def attach_workspace(self, name: str, folder: Path) -> dict[str, Any]:
        target = folder.resolve()
        if not target.exists() or not target.is_dir():
            raise ValueError("workspace folder does not exist")
        self._assert_under_desktop(target)

        display_name = _safe_folder_name(name)
        workspace = self._new_workspace(name=display_name, folder=target)
        items = self._load()
        items.append(workspace)
        self._save(items)
        return dict(workspace)

    def list_files(self, workspace_id: str, rel_path: str = "") -> dict[str, Any]:
        workspace = self.get_workspace(workspace_id)
        base = Path(workspace["path"]).resolve()
        target = (base / rel_path.strip().lstrip("/\\")).resolve() if rel_path else base
        self._assert_under_base(base, target)
        if not target.exists():
            raise ValueError("path does not exist")
        if target.is_file():
            return {"path": target.relative_to(base).as_posix(), "files": [self._file_node(base, target)]}
        nodes = []
        for child in sorted(target.iterdir(), key=lambda item: (not item.is_dir(), item.name.lower())):
            if child.name.startswith(".") and child.name != ".gitignore":
                continue
            if child.name in {"__pycache__", "node_modules", ".dart_tool", "build"}:
                continue
            nodes.append(self._file_node(base, child))
        return {"path": "" if target == base else target.relative_to(base).as_posix(), "files": nodes}

    def read_file(self, workspace_id: str, rel_path: str) -> dict[str, Any]:
        workspace = self.get_workspace(workspace_id)
        base = Path(workspace["path"]).resolve()
        target = (base / rel_path.strip().lstrip("/\\")).resolve()
        self._assert_under_base(base, target)
        if not target.exists() or not target.is_file():
            raise ValueError("file does not exist")
        raw = target.read_bytes()
        text = raw[:128 * 1024].decode("utf-8", "replace")
        if len(raw) > 128 * 1024:
            text += "\n... (truncated)"
        mime_type = _guess_mime_type(target.name)
        return {
            "path": target.relative_to(base).as_posix(),
            "text": text,
            "data_base64": base64.b64encode(raw).decode("ascii"),
            "mime_type": mime_type,
            "size": len(raw),
        }

    def save_upload(
        self,
        workspace_id: str,
        filename: str,
        mime_type: str,
        data_base64: str,
    ) -> dict[str, Any]:
        workspace = self.get_workspace(workspace_id)
        base = Path(workspace["path"]).resolve()
        upload_dir = base / "vision"
        upload_dir.mkdir(parents=True, exist_ok=True)
        data = base64.b64decode(data_base64, validate=True)
        if len(data) > 15 * 1024 * 1024:
            raise ValueError("file is larger than 15 MB")
        target = upload_dir / _safe_upload_name(filename, mime_type)
        target.write_bytes(data)
        return {
            "path": target.relative_to(base).as_posix(),
            "name": target.name,
            "original_name": filename,
            "size": len(data),
            "mime_type": mime_type or "application/octet-stream",
        }

    def get_workspace(self, workspace_id: str) -> dict[str, Any]:
        workspace_key = self._unique_lookup_key(workspace_id)
        for item in self._load():
            if item["id"] == workspace_key:
                return dict(item)
        raise KeyError(f"workspace not found: {workspace_key}")

    def _new_workspace(self, name: str, folder: Path) -> dict[str, Any]:
        created_at = _now_ms()
        return {
            "id": self._unique_id(name),
            "name": name,
            "path": str(folder.resolve()),
            "status": "available",
            "created_at": created_at,
            "updated_at": created_at,
        }

    def _unique_folder(self, base: Path) -> Path:
        if not base.exists():
            return base
        for index in range(2, 10_000):
            candidate = base.with_name(f"{base.name} {index}")
            if not candidate.exists():
                return candidate
        raise RuntimeError("could not allocate workspace folder")

    def _unique_id(self, name: str) -> str:
        existing = {item["id"] for item in self._load()}
        base = _safe_id(name)
        if base not in existing:
            return base
        for index in range(2, 10_000):
            candidate = f"{base}-{index}"
            if candidate not in existing:
                return candidate
        return f"{base}-{uuid.uuid4().hex[:8]}"

    def _assert_under_desktop(self, folder: Path) -> None:
        try:
            folder.relative_to(self.desktop_root)
        except ValueError as exc:
            raise ValueError("workspace folder must be under desktop") from exc

    def _assert_under_base(self, base: Path, target: Path) -> None:
        try:
            target.relative_to(base)
        except ValueError as exc:
            raise ValueError("path must stay inside workspace") from exc

    def _file_node(self, base: Path, path: Path) -> dict[str, Any]:
        try:
            rel_path = path.relative_to(base).as_posix()
        except ValueError:
            rel_path = path.name
        return {
            "name": path.name,
            "path": rel_path,
            "is_dir": path.is_dir(),
            "size": 0 if path.is_dir() else path.stat().st_size,
        }

    def _unique_lookup_key(self, value: str) -> str:
        key = str(value or "").strip()
        if not key:
            raise ValueError("workspace_id is required")
        return key

    def _load(self) -> list[dict[str, Any]]:
        if not self.path.exists():
            return []
        with self.path.open("r", encoding="utf-8") as file:
            data = json.load(file)
        if not isinstance(data, list):
            raise ValueError("workspace registry must contain a JSON list")
        return [dict(item) for item in data]

    def _save(self, items: list[dict[str, Any]]) -> None:
        tmp = self.path.with_suffix(".json.tmp")
        with tmp.open("w", encoding="utf-8") as file:
            json.dump(items, file, ensure_ascii=False, indent=2)
            file.write("\n")
        tmp.replace(self.path)


class SessionRegistry:
    def __init__(self, state_dir: Path) -> None:
        self.state_dir = state_dir.resolve()
        self.sessions_root = self.state_dir / "sessions"
        self.sessions_root.mkdir(parents=True, exist_ok=True)

    def create_session(
        self,
        workspace_id: str,
        title: str,
        *,
        task_card: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        workspace_key = self._require_key(workspace_id, "workspace_id")
        display_title = title.strip() or "Новая сессия"
        created_at = _now_ms()
        session = {
            "id": self._unique_session_id(workspace_key),
            "workspace_id": workspace_key,
            "title": display_title,
            "status": "idle",
            "worker_pid": None,
            "worker_port": None,
            "runtime_session_id": None,
            "active_pid": None,
            "provider": "",
            "model": "",
            "approval_policy": "",
            "sandbox_mode": "",
            "auto_mode": False,
            "task_card": dict(task_card or {}),
            "created_at": created_at,
            "updated_at": created_at,
            "last_event_seq": 0,
        }
        self._save_session(session)
        self._events_path(workspace_key, session["id"]).touch(exist_ok=True)
        return dict(session)

    def list_sessions(self, workspace_id: str) -> list[dict[str, Any]]:
        workspace_key = self._require_key(workspace_id, "workspace_id")
        folder = self._workspace_sessions_dir(workspace_key)
        if not folder.exists():
            return []
        sessions = [
            self._load_session_file(path)
            for path in folder.glob("*.json")
            if path.name != "workspaces.json"
        ]
        return sorted(sessions, key=lambda item: (item["updated_at"], item["id"]), reverse=True)

    def find_reusable_project_chat_session(
        self,
        workspace_id: str,
        task_card: dict[str, Any],
    ) -> dict[str, Any] | None:
        if str(task_card.get("scope") or "").strip() != "project_chat":
            return None
        project_id = str(task_card.get("project_id") or "").strip()
        conversation_key = str(task_card.get("conversation_key") or "").strip()
        if not project_id or not conversation_key:
            return None
        for session in self.list_sessions(workspace_id):
            if str(session.get("status") or "") in {"killed", "stopped", "error"}:
                continue
            existing = session.get("task_card")
            if not isinstance(existing, dict):
                continue
            if str(existing.get("scope") or "").strip() != "project_chat":
                continue
            if str(existing.get("project_id") or "").strip() != project_id:
                continue
            if str(existing.get("conversation_key") or "").strip() != conversation_key:
                continue
            return dict(session)
        return None

    def get_session(self, workspace_id: str, session_id: str) -> dict[str, Any]:
        workspace_key = self._require_key(workspace_id, "workspace_id")
        session_key = self._require_key(session_id, "session_id")
        path = self._session_path(workspace_key, session_key)
        if not path.exists():
            raise KeyError(f"session not found: {session_key}")
        return self._load_session_file(path)

    def update_session(
        self,
        workspace_id: str,
        session_id: str,
        **patch: Any,
    ) -> dict[str, Any]:
        session = self.get_session(workspace_id, session_id)
        allowed = {
            "title",
            "status",
            "worker_pid",
            "worker_port",
            "runtime_session_id",
            "active_pid",
            "provider",
            "model",
            "approval_policy",
            "sandbox_mode",
            "auto_mode",
            "last_event_seq",
        }
        for key, value in patch.items():
            if key not in allowed:
                raise ValueError(f"unsupported session field: {key}")
            session[key] = value
        session["updated_at"] = _now_ms()
        self._save_session(session)
        return dict(session)

    def update_task_card(
        self,
        workspace_id: str,
        session_id: str,
        task_card: dict[str, Any],
    ) -> dict[str, Any]:
        session = self.get_session(workspace_id, session_id)
        session["task_card"] = dict(task_card)
        session["updated_at"] = _now_ms()
        self._save_session(session)
        return dict(session)

    def append_event(
        self,
        workspace_id: str,
        session_id: str,
        event: dict[str, Any],
    ) -> dict[str, Any]:
        session = self.get_session(workspace_id, session_id)
        seq = int(session.get("last_event_seq") or 0) + 1
        record = {
            "seq": seq,
            "ts": _now_ms(),
            **event,
        }
        events_path = self._events_path(session["workspace_id"], session["id"])
        events_path.parent.mkdir(parents=True, exist_ok=True)
        with events_path.open("a", encoding="utf-8") as file:
            file.write(json.dumps(record, ensure_ascii=False, separators=(",", ":")))
            file.write("\n")
        self.update_session(
            session["workspace_id"],
            session["id"],
            last_event_seq=seq,
        )
        return dict(record)

    def load_events(
        self,
        workspace_id: str,
        session_id: str,
        limit: int = 300,
    ) -> list[dict[str, Any]]:
        workspace_key = self._require_key(workspace_id, "workspace_id")
        session_key = self._require_key(session_id, "session_id")
        path = self._events_path(workspace_key, session_key)
        if not path.exists():
            return []
        with path.open("r", encoding="utf-8") as file:
            events = [json.loads(line) for line in file if line.strip()]
        if limit <= 0:
            return events
        return events[-limit:]

    def _unique_session_id(self, workspace_id: str) -> str:
        existing = {item["id"] for item in self.list_sessions(workspace_id)}
        while True:
            candidate = f"session-{_now_ms()}-{uuid.uuid4().hex[:6]}"
            if candidate not in existing:
                return candidate

    def _workspace_sessions_dir(self, workspace_id: str) -> Path:
        return self.sessions_root / workspace_id

    def _session_path(self, workspace_id: str, session_id: str) -> Path:
        return self._workspace_sessions_dir(workspace_id) / f"{session_id}.json"

    def _events_path(self, workspace_id: str, session_id: str) -> Path:
        return self._workspace_sessions_dir(workspace_id) / f"{session_id}.jsonl"

    def _save_session(self, session: dict[str, Any]) -> None:
        path = self._session_path(session["workspace_id"], session["id"])
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(".json.tmp")
        with tmp.open("w", encoding="utf-8") as file:
            json.dump(session, file, ensure_ascii=False, indent=2)
            file.write("\n")
        tmp.replace(path)

    def _load_session_file(self, path: Path) -> dict[str, Any]:
        with path.open("r", encoding="utf-8") as file:
            data = json.load(file)
        if not isinstance(data, dict):
            raise ValueError(f"session metadata must be a JSON object: {path}")
        session = dict(data)
        session.setdefault("provider", "")
        session.setdefault("model", "")
        session.setdefault("approval_policy", "")
        session.setdefault("sandbox_mode", "")
        session.setdefault("auto_mode", False)
        if not isinstance(session.get("task_card"), dict):
            session["task_card"] = {}
        else:
            session["task_card"] = dict(session["task_card"])
        return session

    def _require_key(self, value: str, field_name: str) -> str:
        key = value.strip()
        if not key:
            raise ValueError(f"{field_name} is required")
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", key):
            raise ValueError(f"{field_name} contains unsupported characters")
        return key


class CodeWhaleWorkerManager:
    def __init__(
        self,
        sessions: SessionRegistry,
        state_dir: Path,
        codewhale_cmd: str = "codewhale",
        skills_root: Path | None = None,
        global_task_card_bin: Path | None = None,
        persist_global_path: bool = True,
    ) -> None:
        self.sessions = sessions
        self.state_dir = state_dir.resolve()
        self.codewhale_cmd = codewhale_cmd
        self.skills_root = (
            skills_root.resolve()
            if skills_root is not None
            else (Path.home() / ".deepseek" / "skills").resolve()
        )
        self.global_task_card_bin = (
            global_task_card_bin.resolve()
            if global_task_card_bin is not None
            else self._default_global_task_card_bin()
        )
        self.persist_global_path = persist_global_path
        self._workers: dict[tuple[str, str], subprocess.Popen] = {}

    def start_worker(
        self,
        workspace_id: str,
        session_id: str,
        workspace_path: Path,
        port: int,
    ) -> dict[str, Any]:
        workspace = workspace_path.resolve()
        if not workspace.exists() or not workspace.is_dir():
            raise ValueError("workspace path does not exist")

        session = self.sessions.get_session(workspace_id, session_id)
        task_card = session.get("task_card") if isinstance(session.get("task_card"), dict) else {}
        task_card_runtime = None
        if task_card and str(task_card.get("scope") or "task").strip() != "project_chat":
            task_card_runtime = self._prepare_task_card_runtime(
                workspace,
                workspace_id,
                task_card,
            )

        key = self._key(workspace_id, session_id)
        existing = self._workers.get(key)
        if existing is not None and existing.poll() is None:
            return self.sessions.update_session(
                workspace_id,
                session_id,
                status="running",
                worker_pid=existing.pid,
                worker_port=port,
            )

        env = os.environ.copy()
        env.setdefault("PYTHONIOENCODING", "utf-8:backslashreplace")
        if task_card_runtime is not None:
            tool_dir, global_bin, task_card_env = task_card_runtime
            env.update(task_card_env)
            current_path = env.get("PATH") or env.get("Path") or ""
            env["PATH"] = self._prepend_path_entries(
                current_path,
                [tool_dir, global_bin],
            )
        command = [
            self.codewhale_cmd,
            "serve",
            "--http",
            "--host",
            "127.0.0.1",
            "--port",
            str(port),
            "--insecure",
        ]
        logs = self._open_worker_logs(workspace_id, session_id)
        try:
            process = subprocess.Popen(
                command,
                cwd=str(workspace),
                stdout=logs,
                stderr=subprocess.STDOUT,
                text=True,
                env=env,
                creationflags=self._creation_flags(),
            )
        finally:
            logs.close()
        self._workers[key] = process
        session = self.sessions.update_session(
            workspace_id,
            session_id,
            status="running",
            worker_pid=process.pid,
            worker_port=port,
        )
        self.sessions.append_event(
            workspace_id,
            session_id,
            {
                "type": "worker_status",
                "status": "running",
                "pid": process.pid,
                "port": port,
            },
        )
        return session

    def _prepare_task_card_runtime(
        self,
        workspace: Path,
        workspace_id: str,
        task_card: dict[str, Any],
    ) -> tuple[Path, Path, dict[str, str]]:
        tool_dir = self._materialize_task_card_tool(workspace, task_card)
        global_bin = self._materialize_global_task_card_tool()
        task_card_env = self._task_card_env(workspace, workspace_id, task_card)
        context_path = self._write_task_card_context(workspace, task_card_env)
        task_card_env["FAMILY_TASK_CARD_CONTEXT_FILE"] = str(context_path)
        return tool_dir, global_bin, task_card_env

    def refresh_task_card_runtime(
        self,
        workspace_id: str,
        session_id: str,
        workspace_path: Path,
    ) -> bool:
        workspace = workspace_path.resolve()
        if not workspace.exists() or not workspace.is_dir():
            raise ValueError("workspace path does not exist")
        session = self.sessions.get_session(workspace_id, session_id)
        task_card = session.get("task_card") if isinstance(session.get("task_card"), dict) else {}
        if not task_card:
            return False
        self._prepare_task_card_runtime(workspace, workspace_id, task_card)
        return True

    def _materialize_task_card_tool(
        self,
        workspace: Path,
        task_card: dict[str, Any],
    ) -> Path:
        tool_dir = workspace / ".family-task-card"
        tool_dir.mkdir(parents=True, exist_ok=True)
        cli_path = Path(__file__).resolve().parent / "family_task_card_cli.py"
        python_path = Path(sys.executable).resolve()
        self._write_task_card_wrappers(tool_dir, python_path, cli_path)
        return tool_dir

    def _write_task_card_context(
        self,
        workspace: Path,
        task_card_env: dict[str, str],
    ) -> Path:
        context_dir = workspace / ".family-task-card"
        context_dir.mkdir(parents=True, exist_ok=True)
        context_path = context_dir / "context.json"
        payload = {
            **task_card_env,
            "FAMILY_TASK_CARD_CONTEXT_FILE": str(context_path),
        }
        tmp = context_path.with_suffix(".json.tmp")
        with tmp.open("w", encoding="utf-8") as file:
            json.dump(payload, file, ensure_ascii=False, indent=2)
            file.write("\n")
        tmp.replace(context_path)
        return context_path

    def _materialize_global_task_card_tool(self) -> Path:
        cli_path = Path(__file__).resolve().parent / "family_task_card_cli.py"
        python_path = Path(sys.executable).resolve()
        self._write_task_card_wrappers(
            self.global_task_card_bin,
            python_path,
            cli_path,
        )
        self._materialize_task_card_skill()
        self._ensure_global_bin_on_path(self.global_task_card_bin)
        return self.global_task_card_bin

    def _write_task_card_wrappers(
        self,
        tool_dir: Path,
        python_path: Path,
        cli_path: Path,
    ) -> None:
        tool_dir.mkdir(parents=True, exist_ok=True)
        for command_name in ("family-task-card", "familly-task-card"):
            (tool_dir / f"{command_name}.cmd").write_text(
                (
                    "@echo off\r\n"
                    "set PYTHONIOENCODING=utf-8\r\n"
                    f'"{python_path}" "{cli_path}" %*\r\n'
                ),
                encoding="utf-8",
            )
            (tool_dir / f"{command_name}.ps1").write_text(
                (
                    '$env:PYTHONIOENCODING = "utf-8"\r\n'
                    f'& "{python_path}" "{cli_path}" @args\r\n'
                ),
                encoding="utf-8",
            )
            (tool_dir / command_name).write_text(
                (
                    "#!/usr/bin/env sh\n"
                    "export PYTHONIOENCODING=utf-8\n"
                    f'"{python_path}" "{cli_path}" "$@"\n'
                ),
                encoding="utf-8",
            )

    def _prepend_path_entries(
        self,
        current_path: str,
        entries: Iterable[Path],
    ) -> str:
        existing = [item for item in current_path.split(os.pathsep) if item]
        seen = {self._path_key(Path(item)) for item in existing}
        prefix = []
        for entry in entries:
            key = self._path_key(entry)
            if key in seen:
                continue
            prefix.append(str(entry))
            seen.add(key)
        return os.pathsep.join([*prefix, *existing])

    def _ensure_global_bin_on_path(self, bin_dir: Path) -> None:
        current = os.environ.get("PATH", "")
        os.environ["PATH"] = self._prepend_path_entries(current, [bin_dir])
        if not self.persist_global_path or sys.platform != "win32":
            return
        try:
            import winreg

            with winreg.OpenKey(
                winreg.HKEY_CURRENT_USER,
                "Environment",
                0,
                winreg.KEY_READ | winreg.KEY_WRITE,
            ) as key:
                try:
                    user_path, value_type = winreg.QueryValueEx(key, "Path")
                except FileNotFoundError:
                    user_path, value_type = "", winreg.REG_EXPAND_SZ
                next_path = self._prepend_path_entries(str(user_path), [bin_dir])
                if next_path != str(user_path):
                    winreg.SetValueEx(key, "Path", 0, value_type, next_path)
        except Exception:
            return

    def _path_key(self, path: Path) -> str:
        value = str(path)
        return value.lower() if sys.platform == "win32" else value

    def _default_global_task_card_bin(self) -> Path:
        if sys.platform == "win32":
            python_scripts = Path(sys.executable).resolve().parent / "Scripts"
            if python_scripts.exists():
                return python_scripts.resolve()
        return (Path.home() / ".family-task-card" / "bin").resolve()

    def _materialize_task_card_skill(self) -> Path:
        skill_dir = self.skills_root / "family-task-card"
        skill_dir.mkdir(parents=True, exist_ok=True)
        skill_md = skill_dir / "SKILL.md"
        skill_md.write_text(
            """---
name: family-task-card
description: Work with the current Family Todo task card through the family-task-card CLI
---

# Family Task Card

You are running from a Family Todo task card. The task card is not a file in the repository.

Use the `family-task-card` CLI to read and update the card. Do not type `/familly-task-card`, `/family-task-card`, or any other slash command. Do not type /familly-task-card. The slash command is only `/skill family-task-card` to load this skill.

First command for every task-card run:

```sh
family-task-card read
```

If `family-task-card read` fails, stop and report that the task card is unavailable. Do not continue with project work.

Do not ask the user to confirm moving the card. When the work is complete and no blocking answer is needed, immediately run:

```sh
family-task-card finish --summary "..." --result-status ready_for_review
```

If you cannot continue without the user's answer, do not ask in a normal chat message. Create a blocking task-card question instead:

```sh
family-task-card question ask --text "..." --blocking
```

Never answer with "Should I move it to ready_for_review?", "Move to review?", or similar confirmation prompts.

Use these commands for card updates:

```sh
family-task-card comment add --text "..."
family-task-card question ask --text "..." --blocking
family-task-card checklist create --title "..." --item "..."
family-task-card checklist item-add --checklist-id "..." --text "..."
family-task-card checklist item-done --checklist-id "..." --item-id "..."
family-task-card attachment add-from-workspace --path "reports/file.md" --caption "..."
family-task-card status set in_progress --reason "..."
family-task-card finish --summary "..." --result-status ready_for_review
```

Prefer adding items to existing checklists by ID from `family-task-card read`. Create a new checklist only when no existing checklist matches the work.
Always attach only files that really exist in the workspace.
""",
            encoding="utf-8",
        )
        return skill_md

    def _task_card_env(
        self,
        workspace: Path,
        workspace_id: str,
        task_card: dict[str, Any],
    ) -> dict[str, str]:
        api_key = (
            str(task_card.get("api_key") or "").strip()
            or os.environ.get("FAMILY_TASK_CARD_API_KEY", "").strip()
            or os.environ.get("TODO_BACKEND_API_KEY", "").strip()
            or "dev-local-key"
        )
        return {
            "FAMILY_TASK_CARD_API_URL": str(task_card.get("api_url") or ""),
            "FAMILY_TASK_CARD_API_KEY": api_key,
            "FAMILY_TASK_CARD_TICKET": str(task_card.get("policy_ticket") or ""),
            "FAMILY_TASK_CARD_TASK_ID": str(task_card.get("task_id") or ""),
            "FAMILY_TASK_CARD_WORKSPACE_ID": str(task_card.get("workspace_id") or workspace_id),
            "FAMILY_TASK_CARD_SESSION_ID": str(task_card.get("agent_session_id") or ""),
            "FAMILY_TASK_CARD_ACTOR_PROFILE": str(task_card.get("actor_profile") or ""),
            "FAMILY_TASK_CARD_ACTOR_PHONE": str(task_card.get("actor_phone") or ""),
            "FAMILY_TASK_CARD_TASK_TYPE": str(task_card.get("task_type") or "feature"),
            "FAMILY_TASK_CARD_MODE": str(task_card.get("mode") or "executor"),
            "FAMILY_TASK_CARD_WORKSPACE_PATH": str(workspace),
            "PYTHONIOENCODING": "utf-8",
        }

    def stop_worker(
        self,
        workspace_id: str,
        session_id: str,
        timeout_seconds: float = 5,
    ) -> dict[str, Any]:
        key = self._key(workspace_id, session_id)
        session = self.sessions.get_session(workspace_id, session_id)
        process = self._workers.get(key)
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=timeout_seconds)
            except Exception:
                return self.kill_worker(workspace_id, session_id)
        else:
            self._kill_persisted_worker_processes(session, force=False)
        self._workers.pop(key, None)
        self.sessions.append_event(
            workspace_id,
            session_id,
            {"type": "worker_status", "status": "stopped"},
        )
        return self.sessions.update_session(
            workspace_id,
            session_id,
            status="stopped",
            worker_pid=None,
            worker_port=None,
            active_pid=None,
        )

    def kill_worker(self, workspace_id: str, session_id: str) -> dict[str, Any]:
        key = self._key(workspace_id, session_id)
        session = self.sessions.get_session(workspace_id, session_id)
        process = self._workers.pop(key, None)
        if process is not None and process.poll() is None:
            self._kill_process_tree(process)
        self._kill_persisted_worker_processes(session, force=True)
        self.sessions.append_event(
            workspace_id,
            session_id,
            {"type": "worker_status", "status": "killed"},
        )
        return self.sessions.update_session(
            workspace_id,
            session_id,
            status="killed",
            worker_pid=None,
            worker_port=None,
            runtime_session_id=None,
            active_pid=None,
        )

    def health(self, workspace_id: str, session_id: str) -> dict[str, Any]:
        key = self._key(workspace_id, session_id)
        process = self._workers.get(key)
        session = self.sessions.get_session(workspace_id, session_id)
        if process is None:
            worker_alive = self._persisted_worker_alive(session)
            if not worker_alive and session.get("status") == "running":
                session = self.sessions.update_session(
                    workspace_id,
                    session_id,
                    status="stopped",
                    worker_pid=None,
                    worker_port=None,
                    active_pid=None,
                )
            return {**session, "worker_alive": worker_alive}
        return {**session, "worker_alive": process.poll() is None}

    def _open_worker_logs(self, workspace_id: str, session_id: str):
        logs_dir = self.state_dir / "sessions" / workspace_id
        logs_dir.mkdir(parents=True, exist_ok=True)
        return (logs_dir / f"{session_id}.worker.log").open("a", encoding="utf-8")

    def _kill_process_tree(self, process: subprocess.Popen) -> None:
        self._kill_pid_tree(process.pid, force=True)
        if process.poll() is None:
            process.kill()
            try:
                process.wait(timeout=5)
            except Exception:
                pass

    def _kill_persisted_worker_processes(
        self,
        session: dict[str, Any],
        *,
        force: bool,
    ) -> None:
        pids: list[int] = []
        worker_pid = int(session.get("worker_pid") or 0)
        if worker_pid:
            pids.append(worker_pid)
        worker_port = int(session.get("worker_port") or 0)
        if worker_port:
            pids.extend(
                self._find_codewhale_process_ids(["serve", "--port", str(worker_port)])
            )
        seen: set[int] = set()
        for pid in pids:
            if pid in seen:
                continue
            seen.add(pid)
            self._kill_pid_tree(pid, force=force)

    def _persisted_worker_alive(self, session: dict[str, Any]) -> bool:
        worker_pid = int(session.get("worker_pid") or 0)
        if worker_pid and self._pid_is_alive(worker_pid):
            return True
        worker_port = int(session.get("worker_port") or 0)
        if not worker_port:
            return False
        return bool(self._find_codewhale_process_ids(["serve", "--port", str(worker_port)]))

    def _pid_is_alive(self, pid: int) -> bool:
        if sys.platform == "win32":
            result = subprocess.run(
                ["tasklist", "/FI", f"PID eq {pid}", "/NH"],
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            return str(pid) in result.stdout
        try:
            os.kill(pid, 0)
        except OSError:
            return False
        return True

    def _kill_pid_tree(self, pid: int, *, force: bool) -> None:
        if sys.platform == "win32":
            command = ["taskkill", "/T", "/PID", str(pid)]
            if force:
                command.insert(2, "/F")
            subprocess.run(command, capture_output=True, timeout=10, check=False)
            return
        try:
            os.killpg(os.getpgid(pid), signal.SIGKILL if force else signal.SIGTERM)
        except Exception:
            try:
                os.kill(pid, signal.SIGKILL if force else signal.SIGTERM)
            except Exception:
                pass

    def _find_codewhale_process_ids(self, tokens: list[str]) -> list[int]:
        return _find_codewhale_process_ids(tokens)

    def _creation_flags(self) -> int:
        return _background_creation_flags()

    def _key(self, workspace_id: str, session_id: str) -> tuple[str, str]:
        return (
            self.sessions._require_key(workspace_id, "workspace_id"),
            self.sessions._require_key(session_id, "session_id"),
        )


class CodeWhaleRuntimeClient:
    def __init__(self, urlopen=urllib.request.urlopen, timeout_seconds: float = 10) -> None:
        self.urlopen = urlopen
        self.timeout_seconds = timeout_seconds

    def create_task(self, port: int, prompt: str) -> dict[str, Any]:
        return self._json_request(
            port,
            "POST",
            "/v1/tasks",
            {
                "prompt": prompt,
                "mode": "agent",
            },
        )

    def get_task(self, port: int, task_id: str) -> dict[str, Any]:
        return self._json_request(port, "GET", f"/v1/tasks/{task_id}")

    def _json_request(
        self,
        port: int,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        data = None
        headers = {}
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            f"http://127.0.0.1:{port}{path}",
            data=data,
            headers=headers,
            method=method,
        )
        with self.urlopen(request, timeout=self.timeout_seconds) as response:
            body = response.read().decode("utf-8", "replace")
        decoded = json.loads(body)
        if not isinstance(decoded, dict):
            raise ValueError("runtime API returned non-object JSON")
        return decoded


class ProjectChatLocalLLMClient:
    def __init__(
        self,
        urlopen=urllib.request.urlopen,
        popen: Callable[..., subprocess.CompletedProcess] = subprocess.run,
        timeout_seconds: float = 75,
        models: list[str] | None = None,
    ) -> None:
        configured = [
            item.strip()
            for item in str(os.environ.get("PROJECT_CHAT_OLLAMA_MODELS") or "").split(",")
            if item.strip()
        ]
        self.models = configured or models or ["qwen3:8b", "qwen2.5-coder:7b"]
        self.urlopen = urlopen
        self.popen = popen
        self.timeout_seconds = timeout_seconds
        self.ollama_cmd = _resolve_ollama_cmd()

    def generate(self, prompt: str) -> str:
        clean_prompt = prompt.strip()
        if not clean_prompt:
            raise ValueError("project chat prompt is empty")
        errors: list[str] = []
        for model in self.models:
            try:
                response = self._generate_http(model, clean_prompt)
                if response:
                    return response
            except Exception as exc:
                errors.append(f"{model}/http: {exc}")
        for model in self.models:
            try:
                response = self._generate_cli(model, clean_prompt)
                if response:
                    return response
            except Exception as exc:
                errors.append(f"{model}/cli: {exc}")
        detail = "; ".join(errors[-3:]) if errors else "no local model response"
        raise RuntimeError(f"local project-chat LLM is unavailable: {detail}")

    def _generate_http(self, model: str, prompt: str) -> str:
        payload = {
            "model": model,
            "prompt": prompt,
            "stream": False,
            "options": {
                "temperature": 0.2,
                "num_ctx": 4096,
            },
        }
        request = urllib.request.Request(
            "http://127.0.0.1:11434/api/generate",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with self.urlopen(request, timeout=self.timeout_seconds) as response:
                body = response.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", "replace")
            raise RuntimeError(body or str(exc)) from exc
        decoded = json.loads(body)
        if not isinstance(decoded, dict):
            raise ValueError("ollama returned non-object JSON")
        return str(decoded.get("response") or "").strip()

    def _generate_cli(self, model: str, prompt: str) -> str:
        result = self.popen(
            [self.ollama_cmd, "run", model],
            input=prompt,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=self.timeout_seconds,
            check=False,
            creationflags=_background_creation_flags(),
        )
        if result.returncode != 0:
            error = str(result.stderr or result.stdout or "").strip()
            raise RuntimeError(error or f"ollama exited with code {result.returncode}")
        return str(result.stdout or "").strip()


class CodeWhaleExecClient:
    def __init__(
        self,
        codewhale_cmd: str = "codewhale",
        popen: Callable[..., subprocess.Popen] = subprocess.Popen,
    ) -> None:
        self.codewhale_cmd = codewhale_cmd
        self.popen = popen

    def stream_prompt(
        self,
        workspace_path: Path,
        prompt: str,
        *,
        session_id: str | None = None,
        provider: str = "",
        model: str = "",
        approval_policy: str = "",
        sandbox_mode: str = "",
        auto_mode: bool = False,
        on_process_start: Callable[[tuple[str, str], subprocess.Popen], None] | None = None,
        on_process_end: Callable[[tuple[str, str]], None] | None = None,
        process_key: tuple[str, str] | None = None,
    ) -> Iterator[dict[str, Any]]:
        command = [
            self.codewhale_cmd,
        ]
        if provider.strip():
            command.extend(["--provider", provider.strip()])
        if model.strip():
            command.extend(["--model", model.strip()])
        if approval_policy.strip():
            command.extend(["--approval-policy", approval_policy.strip()])
        if sandbox_mode.strip():
            command.extend(["--sandbox-mode", sandbox_mode.strip()])
        command.extend([
            "exec",
            "--output-format",
            "stream-json",
        ])
        if auto_mode:
            command.append("--auto")
        if session_id:
            command.extend(["--resume", session_id])
        command.append(prompt)

        process = self.popen(
            command,
            cwd=str(workspace_path),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            text=True,
            encoding="utf-8",
            errors="replace",
            creationflags=_background_creation_flags(),
        )
        if process_key is not None and on_process_start is not None:
            on_process_start(process_key, process)
        try:
            assert process.stdout is not None
            yield from self._parse_stream_json_lines(process.stdout)
            exit_code = process.wait(timeout=5)
            if exit_code != 0:
                raise RuntimeError(f"codewhale exec exited with code {exit_code}")
        finally:
            if process_key is not None and on_process_end is not None:
                on_process_end(process_key)

    @staticmethod
    def _parse_stream_json_lines(lines: Iterable[str]) -> Iterator[dict[str, Any]]:
        for line in lines:
            start = line.find("{")
            if start < 0:
                continue
            payload = line[start:].strip()
            if not payload:
                continue
            try:
                decoded = json.loads(payload)
            except json.JSONDecodeError:
                continue
            if isinstance(decoded, dict):
                yield decoded


class CodeWhaleBridge:
    def __init__(
        self,
        desktop_root: Path,
        state_dir: Path,
        codewhale_cmd: str = "codewhale",
        require_policy_ticket: bool = False,
        policy_ticket_secret: str | None = None,
    ) -> None:
        codewhale_cmd = _resolve_codewhale_cmd(codewhale_cmd)
        self.workspaces = WorkspaceRegistry(desktop_root, state_dir)
        self.sessions = SessionRegistry(state_dir)
        self.workers = CodeWhaleWorkerManager(
            self.sessions,
            state_dir,
            codewhale_cmd=codewhale_cmd,
        )
        self.runtime = CodeWhaleRuntimeClient()
        self.exec_client = CodeWhaleExecClient(codewhale_cmd=codewhale_cmd)
        self.project_chat_llm = ProjectChatLocalLLMClient()
        self._active_execs: dict[tuple[str, str], subprocess.Popen] = {}
        self._session_stream_locks: dict[tuple[str, str], threading.Lock] = {}
        self._session_stream_locks_guard = threading.Lock()
        self._next_port = 43100
        self.require_policy_ticket = require_policy_ticket
        self.policy_ticket_secret = policy_ticket_secret or os.environ.get(
            "CODEWHALE_POLICY_SECRET",
            "",
        )
        self.workspaces.discover_workspaces()

    def handle_message(self, message: dict[str, Any]) -> dict[str, Any]:
        request_id = message.get("request_id")
        try:
            reply = self._handle_message(message)
        except Exception as exc:
            reply = {"type": "error", "error": str(exc)}
        if request_id is not None:
            reply["request_id"] = request_id
        return reply

    def _handle_message(self, message: dict[str, Any]) -> dict[str, Any]:
        msg_type = str(message.get("type") or "").strip()
        self._authorize_message(message, msg_type)
        if msg_type == "codewhale_command_list":
            return {
                "type": "codewhale_command_list",
                "commands": self._codewhale_command_catalog(),
            }
        if msg_type == "workspace_list":
            self.workspaces.discover_workspaces()
            return {
                "type": "workspace_list",
                "workspaces": self.workspaces.list_workspaces(),
            }
        if msg_type == "workspace_discover":
            discovered = self.workspaces.discover_workspaces()
            return {
                "type": "workspace_list",
                "workspaces": self.workspaces.list_workspaces(),
                "discovered": discovered,
            }
        if msg_type == "workspace_folder_list":
            raw_path = str(message.get("path") or "").strip()
            result = self.workspaces.list_folders(Path(raw_path) if raw_path else None)
            return {"type": "workspace_folder_list", **result}
        if msg_type == "workspace_file_list":
            workspace_id = self._workspace_id(message)
            result = self.workspaces.list_files(
                workspace_id,
                str(message.get("path") or ""),
            )
            return {"type": "workspace_file_list", "workspace_id": workspace_id, **result}
        if msg_type == "workspace_file_read":
            workspace_id = self._workspace_id(message)
            result = self.workspaces.read_file(
                workspace_id,
                str(message.get("path") or ""),
            )
            return {"type": "workspace_file_content", "workspace_id": workspace_id, **result}
        if msg_type == "workspace_create":
            workspace = self.workspaces.create_workspace(str(message.get("name") or ""))
            return {"type": "workspace", "workspace": workspace}
        if msg_type == "workspace_attach":
            workspace = self.workspaces.attach_workspace(
                str(message.get("name") or ""),
                Path(str(message.get("path") or "")),
            )
            return {"type": "workspace", "workspace": workspace}
        if msg_type == "session_list":
            workspace = self.workspaces.get_workspace(self._workspace_id(message))
            workspace_id = str(workspace["id"])
            return {
                "type": "session_list",
                "workspace_id": workspace_id,
                "sessions": self.sessions.list_sessions(workspace_id),
            }
        if msg_type == "session_create":
            workspace = self.workspaces.get_workspace(self._workspace_id(message))
            title = str(message.get("title") or "")
            task_card = self._task_card_metadata(message, str(workspace["id"]))
            existing = self.sessions.find_reusable_project_chat_session(
                str(workspace["id"]),
                task_card,
            )
            if existing is not None:
                if title.strip() and str(existing.get("title") or "") != title.strip():
                    existing = self.sessions.update_session(
                        str(workspace["id"]),
                        str(existing["id"]),
                        title=title.strip(),
                    )
                return {"type": "session", "session": existing}
            session = self.sessions.create_session(
                str(workspace["id"]),
                title,
                task_card=task_card,
            )
            return {"type": "session", "session": session}
        if msg_type == "session_update_task_card":
            workspace = self.workspaces.get_workspace(self._workspace_id(message))
            session_id = self._session_id(message)
            task_card = self._task_card_metadata(message, str(workspace["id"]))
            if not task_card:
                raise ValueError("task_card is required")
            session = self.sessions.update_task_card(
                str(workspace["id"]),
                session_id,
                task_card,
            )
            self.workers.refresh_task_card_runtime(
                str(workspace["id"]),
                session_id,
                Path(str(workspace["path"])),
            )
            return {"type": "session_task_card", "session": session}
        if msg_type == "session_open":
            session = self.sessions.get_session(
                self._workspace_id(message),
                self._session_id(message),
            )
            events = self.sessions.load_events(session["workspace_id"], session["id"])
            return {"type": "session_open", "session": session, "events": events}
        if msg_type == "session_update_settings":
            workspace_id = self._workspace_id(message)
            session_id = self._session_id(message)
            session = self.sessions.update_session(
                workspace_id,
                session_id,
                **self._session_settings_patch(message),
            )
            return {"type": "session", "session": session}
        if msg_type == "session_send":
            text = str(message.get("text") or "").strip()
            if not text:
                raise ValueError("message text is required")
            workspace_id = self._workspace_id(message)
            session_id = self._session_id(message)
            session = self.sessions.get_session(workspace_id, session_id)
            self.sessions.append_event(
                workspace_id,
                session_id,
                {"type": "user_message", "text": text},
            )
            port = session.get("worker_port")
            if not port:
                workspace = self._find_workspace(workspace_id)
                port = self._allocate_port()
                session = self.workers.start_worker(
                    workspace_id,
                    session_id,
                    Path(workspace["path"]),
                    port=int(port),
                )
                port = session.get("worker_port")
            if not port:
                raise ValueError("session worker failed to start")
            task = self.runtime.create_task(int(port), text)
            event = self.sessions.append_event(
                workspace_id,
                session_id,
                {
                    "type": "runtime_task",
                    "task_id": str(task.get("id") or ""),
                    "status": str(task.get("status") or "queued"),
                },
            )
            return {
                "type": "session_task",
                "workspace_id": workspace_id,
                "session_id": session_id,
                "task_id": event["task_id"],
                "status": event["status"],
                "event": event,
            }
        if msg_type == "session_upload_file":
            workspace_id = self._workspace_id(message)
            session_id = self._session_id(message)
            upload = self.workspaces.save_upload(
                workspace_id,
                str(message.get("filename") or "file.bin"),
                str(message.get("mime_type") or "application/octet-stream"),
                str(message.get("data_base64") or ""),
            )
            caption = str(message.get("caption") or "").strip()
            text = f"Файл прикреплен: {upload['path']}"
            if caption:
                text = f"{text}\n{caption}"
            event = self.sessions.append_event(
                workspace_id,
                session_id,
                {
                    "type": "file_attachment",
                    "text": text,
                    "path": upload["path"],
                    "filename": upload["name"],
                    "original_name": upload["original_name"],
                    "mime_type": upload["mime_type"],
                    "size": upload["size"],
                },
            )
            return {
                "type": "session_file_uploaded",
                "workspace_id": workspace_id,
                "session_id": session_id,
                "event": event,
                **upload,
            }
        if msg_type == "session_task_poll":
            workspace_id = self._workspace_id(message)
            session_id = self._session_id(message)
            task_id = str(message.get("task_id") or "").strip()
            if not task_id:
                raise ValueError("task_id is required")
            session = self.sessions.get_session(workspace_id, session_id)
            port = session.get("worker_port")
            if not port:
                raise ValueError("session worker is not running")
            task = self.runtime.get_task(int(port), task_id)
            status = str(task.get("status") or "")
            event = self.sessions.append_event(
                workspace_id,
                session_id,
                {
                    "type": "runtime_task",
                    "task_id": task_id,
                    "status": status,
                },
            )
            result_summary = str(task.get("result_summary") or "").strip()
            if status == "completed" and result_summary:
                self.sessions.append_event(
                    workspace_id,
                    session_id,
                    {
                        "type": "assistant_delta",
                        "task_id": task_id,
                        "text": result_summary,
                        "final": True,
                    },
                )
            return {
                "type": "session_task",
                "workspace_id": workspace_id,
                "session_id": session_id,
                "task_id": task_id,
                "status": status,
                "task": task,
                "event": event,
            }
        if msg_type == "session_health":
            session = self.workers.health(self._workspace_id(message), self._session_id(message))
            return {"type": "session_health", "session": session}
        if msg_type == "session_stop":
            self._stop_active_exec(self._workspace_id(message), self._session_id(message), force=False)
            session = self.workers.stop_worker(
                self._workspace_id(message),
                self._session_id(message),
            )
            return {"type": "session", "session": session}
        if msg_type == "session_kill":
            self._stop_active_exec(self._workspace_id(message), self._session_id(message), force=True)
            session = self.workers.kill_worker(
                self._workspace_id(message),
                self._session_id(message),
            )
            return {"type": "session", "session": session}
        if msg_type == "session_start":
            workspace = self._find_workspace(self._workspace_id(message))
            session = self.workers.start_worker(
                workspace["id"],
                self._session_id(message),
                Path(workspace["path"]),
                port=self._allocate_port(),
            )
            return {"type": "session", "session": session}
        raise ValueError(f"unsupported message type: {msg_type}")

    def stream_session_message(self, message: dict[str, Any]) -> Iterator[dict[str, Any]]:
        self._authorize_message(message, "session_send")
        text = str(message.get("text") or "").strip()
        if not text:
            raise ValueError("message text is required")
        workspace_id = self._workspace_id(message)
        session_id = self._session_id(message)
        with self._session_stream_lock(workspace_id, session_id):
            yield from self._stream_session_message_locked(
                message,
                workspace_id,
                session_id,
                text,
            )

    def _stream_session_message_locked(
        self,
        message: dict[str, Any],
        workspace_id: str,
        session_id: str,
        text: str,
    ) -> Iterator[dict[str, Any]]:
        session = self.sessions.get_session(workspace_id, session_id)
        if str(session.get("status") or "") in {"killed", "stopped"}:
            raise ValueError("session is stopped; press start a new run or create a new session")
        if self._is_project_chat_session(session):
            yield from self._stream_project_chat_message_locked(
                workspace_id,
                session_id,
                text,
            )
            return
        workspace = self._find_workspace(workspace_id)
        runtime_session_id = str(session.get("runtime_session_id") or "").strip() or None

        self.sessions.append_event(
            workspace_id,
            session_id,
            {"type": "user_message", "text": text},
        )
        yield {
            "type": "session_stream_started",
            "workspace_id": workspace_id,
            "session_id": session_id,
        }

        assistant_text: list[str] = []
        final_status = "completed"
        try:
            for item in self.exec_client.stream_prompt(
                Path(workspace["path"]),
                text,
                session_id=runtime_session_id,
                provider=str(session.get("provider") or ""),
                model=str(session.get("model") or ""),
                approval_policy=str(session.get("approval_policy") or ""),
                sandbox_mode=str(session.get("sandbox_mode") or ""),
                auto_mode=bool(session.get("auto_mode")),
                on_process_start=self._remember_exec_process,
                on_process_end=self._forget_exec_process,
                process_key=(workspace_id, session_id),
            ):
                item_type = str(item.get("type") or "")
                if item_type == "content":
                    chunk = str(item.get("content") or "")
                    if not chunk:
                        continue
                    assistant_text.append(chunk)
                    yield {
                        "type": "assistant_delta",
                        "workspace_id": workspace_id,
                        "session_id": session_id,
                        "text": chunk,
                        "final": False,
                    }
                    continue
                if item_type == "session_capture":
                    captured = str(item.get("content") or "").strip()
                    if captured:
                        runtime_session_id = captured
                        self.sessions.update_session(
                            workspace_id,
                            session_id,
                            runtime_session_id=captured,
                        )
                    continue
                if item_type == "metadata":
                    meta = item.get("meta")
                    if not isinstance(meta, dict):
                        continue
                    captured = str(meta.get("session_id") or "").strip()
                    if captured:
                        runtime_session_id = captured
                        self.sessions.update_session(
                            workspace_id,
                            session_id,
                            runtime_session_id=captured,
                        )
                    final_status = str(meta.get("status") or final_status)
                    process_text = self._process_event_text(item)
                    if process_text:
                        event = self.sessions.append_event(
                            workspace_id,
                            session_id,
                            {
                                "type": "session_process_event",
                                "text": process_text,
                                "event_type": item_type,
                            },
                        )
                        yield {
                            "type": "session_process_event",
                            "workspace_id": workspace_id,
                            "session_id": session_id,
                            "event": event,
                            "text": process_text,
                            "event_type": item_type,
                        }
                    continue
                process_text = self._process_event_text(item)
                if process_text:
                    event = self.sessions.append_event(
                        workspace_id,
                        session_id,
                        {
                            "type": "session_process_event",
                            "text": process_text,
                            "event_type": item_type,
                        },
                    )
                    yield {
                        "type": "session_process_event",
                        "workspace_id": workspace_id,
                        "session_id": session_id,
                        "event": event,
                        "text": process_text,
                        "event_type": item_type,
                    }
        except Exception:
            self.sessions.update_session(
                workspace_id,
                session_id,
                status="idle",
                active_pid=None,
            )
            raise

        full_text = "".join(assistant_text).strip()
        if full_text:
            self.sessions.append_event(
                workspace_id,
                session_id,
                {
                    "type": "assistant_delta",
                    "text": full_text,
                    "final": True,
                },
            )
        auto_finish_event = self._auto_finish_task_card_after_completed_reply(
            workspace,
            session,
            text,
            full_text,
        )
        if auto_finish_event is not None:
            yield {
                "type": "session_process_event",
                "workspace_id": workspace_id,
                "session_id": session_id,
                "event": auto_finish_event,
                "text": str(auto_finish_event.get("text") or ""),
                "event_type": str(auto_finish_event.get("event_type") or ""),
            }
        self.sessions.update_session(
            workspace_id,
            session_id,
            status="idle",
            active_pid=None,
        )
        yield {
            "type": "session_stream_done",
            "workspace_id": workspace_id,
            "session_id": session_id,
            "status": final_status,
            "runtime_session_id": runtime_session_id or "",
        }

    def _stream_project_chat_message_locked(
        self,
        workspace_id: str,
        session_id: str,
        text: str,
    ) -> Iterator[dict[str, Any]]:
        self.sessions.append_event(
            workspace_id,
            session_id,
            {"type": "user_message", "text": text},
        )
        self.sessions.update_session(
            workspace_id,
            session_id,
            status="running",
            active_pid=None,
        )
        yield {
            "type": "session_stream_started",
            "workspace_id": workspace_id,
            "session_id": session_id,
        }
        try:
            full_text = self.project_chat_llm.generate(text).strip()
            if not full_text:
                raise ValueError("local project-chat LLM returned empty response")
        except Exception:
            self.sessions.update_session(
                workspace_id,
                session_id,
                status="idle",
                active_pid=None,
            )
            raise

        self.sessions.append_event(
            workspace_id,
            session_id,
            {
                "type": "assistant_delta",
                "text": full_text,
                "final": True,
            },
        )
        yield {
            "type": "assistant_delta",
            "workspace_id": workspace_id,
            "session_id": session_id,
            "text": full_text,
            "final": True,
        }
        self.sessions.update_session(
            workspace_id,
            session_id,
            status="idle",
            active_pid=None,
        )
        yield {
            "type": "session_stream_done",
            "workspace_id": workspace_id,
            "session_id": session_id,
            "status": "completed",
            "runtime_session_id": "",
        }

    @staticmethod
    def _is_project_chat_session(session: dict[str, Any]) -> bool:
        task_card = session.get("task_card")
        return (
            isinstance(task_card, dict)
            and str(task_card.get("scope") or "").strip() == "project_chat"
        )

    def _auto_finish_task_card_after_completed_reply(
        self,
        workspace: dict[str, Any],
        session: dict[str, Any],
        user_text: str,
        full_text: str,
    ) -> dict[str, Any] | None:
        if not self._should_auto_finish_task_card_reply(user_text, full_text):
            return None
        task_card = session.get("task_card")
        if not isinstance(task_card, dict) or not task_card:
            return None
        workspace_id = str(session.get("workspace_id") or workspace.get("id") or "").strip()
        session_id = str(session.get("id") or "").strip()
        if not workspace_id or not session_id:
            return None
        env = self.workers._task_card_env(
            Path(str(workspace["path"])),
            workspace_id,
            task_card,
        )
        summary = self._task_card_finish_summary(full_text)
        try:
            import family_task_card_cli

            stdout = io.StringIO()
            stderr = io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                exit_code = family_task_card_cli.run(
                    [
                        "finish",
                        "--summary",
                        summary,
                        "--result-status",
                        "ready_for_review",
                    ],
                    env=env,
                )
        except Exception as exc:
            return self.sessions.append_event(
                workspace_id,
                session_id,
                {
                    "type": "session_process_event",
                    "text": f"Автоперевод карточки на проверку не выполнен: {exc}",
                    "event_type": "task_card_auto_finish_error",
                },
            )
        if exit_code != 0:
            error_text = stderr.getvalue().strip() or stdout.getvalue().strip()
            return self.sessions.append_event(
                workspace_id,
                session_id,
                {
                    "type": "session_process_event",
                    "text": (
                        "Автоперевод карточки на проверку не выполнен"
                        f"{': ' + error_text if error_text else ''}"
                    ),
                    "event_type": "task_card_auto_finish_error",
                },
            )
        return self.sessions.append_event(
            workspace_id,
            session_id,
            {
                "type": "session_process_event",
                "text": "Карточка автоматически переведена в На проверке без подтверждения.",
                "event_type": "task_card_auto_finish",
            },
        )

    @staticmethod
    def _should_auto_finish_task_card_reply(user_text: str, assistant_text: str) -> bool:
        if not assistant_text.strip():
            return False
        if CodeWhaleBridge._is_task_card_technical_prompt(user_text):
            return False
        if CodeWhaleBridge._looks_like_review_confirmation_prompt(assistant_text):
            return True
        if CodeWhaleBridge._looks_like_blocking_task_card_reply(assistant_text):
            return False
        return CodeWhaleBridge._looks_like_task_completion_report(assistant_text)

    @staticmethod
    def _is_task_card_technical_prompt(text: str) -> bool:
        normalized = re.sub(r"\s+", " ", text.strip().lower())
        if not normalized:
            return False
        if normalized.startswith(("/skill", "/mode", "/plugin")):
            return True
        technical_markers = (
            "family-task-card read",
            "familly-task-card read",
            "системный контекст family todo",
            "карточка задачи не файл в проекте",
            "task_card_actions_json",
        )
        return any(marker in normalized for marker in technical_markers)

    @staticmethod
    def _looks_like_review_confirmation_prompt(text: str) -> bool:
        normalized = re.sub(r"\s+", " ", text.strip().lower())
        if "?" not in normalized:
            return False
        has_review_target = any(
            token in normalized
            for token in ("ready_for_review", "на проверк", "review")
        )
        has_move_intent = any(
            token in normalized
            for token in (
                "перенести",
                "перевести",
                "переместить",
                "move",
                "send",
                "transfer",
            )
        )
        has_ready_signal = any(
            token in normalized
            for token in (
                "готов",
                "выполн",
                "ready",
                "complete",
                "done",
            )
        )
        has_blocker_signal = any(
            token in normalized
            for token in (
                "не готов",
                "не выполн",
                "не могу",
                "нельзя",
                "blocked",
                "blocker",
            )
        )
        return has_review_target and has_move_intent and has_ready_signal and not has_blocker_signal

    @staticmethod
    def _looks_like_blocking_task_card_reply(text: str) -> bool:
        normalized = re.sub(r"\s+", " ", text.strip().lower())
        neutral_phrases = (
            "блокирующих вопросов нет",
            "нет блокирующих вопросов",
            "блокеров нет",
            "ошибок нет",
            "без ошибок",
            "no blockers",
            "no blocking questions",
        )
        guarded = normalized
        for phrase in neutral_phrases:
            guarded = guarded.replace(phrase, "")
        blocker_markers = (
            "карточка задачи недоступна",
            "http 403",
            "forbidden",
            "не могу",
            "невозможно",
            "не удалось",
            "недоступ",
            "нужен ответ",
            "нужно уточнить",
            "требуется уточнение",
            "уточните",
            "что конкретно нужно сделать",
            "не хватает",
            "ожидаю ответ",
            "failed",
            "error",
            "blocked",
            "blocker",
        )
        return any(marker in guarded for marker in blocker_markers)

    @staticmethod
    def _looks_like_task_completion_report(text: str) -> bool:
        normalized = re.sub(r"\s+", " ", text.strip().lower())
        if not normalized:
            return False
        completion_markers = (
            "работа выполн",
            "вся работа выполн",
            "задача выполн",
            "задача готов",
            "задача по сути готов",
            "работа заверш",
            "задача заверш",
            "всё выполнено",
            "все выполнено",
            "перевожу на проверк",
            "можно проверять",
            "готово к проверк",
            "completed",
            "done",
        )
        if any(marker in normalized for marker in completion_markers):
            return True
        result_markers = (
            "создан",
            "создала",
            "добавлен",
            "добавила",
            "исправлен",
            "исправила",
            "реализован",
            "реализовала",
            "проверен",
            "проверила",
            "чек-лист",
            "чеклист",
            "отчёт",
            "отчет",
        )
        no_blocker_markers = (
            "блокирующих вопросов нет",
            "нет блокирующих вопросов",
            "блокеров нет",
            "no blockers",
            "no blocking questions",
        )
        return (
            any(marker in normalized for marker in result_markers)
            and any(marker in normalized for marker in no_blocker_markers)
        )

    @staticmethod
    def _task_card_finish_summary(text: str) -> str:
        cleaned = re.sub(r"\s+", " ", text.strip())
        if not cleaned:
            return "Агент завершил работу и перевел карточку на проверку."
        cut = re.split(
            r"(?i)\b(перенести|перевести|переместить|move|send|transfer)\b",
            cleaned,
            maxsplit=1,
        )[0].strip(" .?!")
        summary = cut or "Агент завершил работу и перевел карточку на проверку."
        return summary[:900]

    def _session_stream_lock(self, workspace_id: str, session_id: str) -> threading.Lock:
        key = (workspace_id, session_id)
        with self._session_stream_locks_guard:
            lock = self._session_stream_locks.get(key)
            if lock is None:
                lock = threading.Lock()
                self._session_stream_locks[key] = lock
            return lock

    @staticmethod
    def _process_event_text(item: dict[str, Any]) -> str:
        item_type = str(item.get("type") or "").strip()
        if item_type in {"content", "session_capture", "done"}:
            return ""
        if item_type == "metadata":
            meta = item.get("meta")
            if isinstance(meta, dict):
                status = str(meta.get("status") or "").strip()
                session_id = str(meta.get("session_id") or "").strip()
                parts = []
                if status:
                    parts.append(f"status={status}")
                if session_id:
                    parts.append(f"session={session_id}")
                return "CodeWhale metadata: " + ", ".join(parts) if parts else ""
            return ""
        for key in ("message", "text", "summary", "name", "command", "tool", "status"):
            value = str(item.get(key) or "").strip()
            if value:
                return f"{item_type}: {value}" if item_type else value
        return item_type

    def _remember_exec_process(
        self,
        process_key: tuple[str, str],
        process: subprocess.Popen,
    ) -> None:
        self._active_execs[process_key] = process
        self.sessions.update_session(
            process_key[0],
            process_key[1],
            status="running",
            active_pid=process.pid,
        )

    def _forget_exec_process(self, process_key: tuple[str, str]) -> None:
        self._active_execs.pop(process_key, None)
        try:
            self.sessions.update_session(
                process_key[0],
                process_key[1],
                active_pid=None,
            )
        except Exception:
            pass

    def _stop_active_exec(self, workspace_id: str, session_id: str, *, force: bool) -> None:
        key = (workspace_id, session_id)
        process = self._active_execs.pop(key, None)
        handled_pids: set[int] = set()
        if process is not None:
            handled_pids.add(process.pid)
            if force:
                self.workers._kill_process_tree(process)
            else:
                process.terminate()
                try:
                    process.wait(timeout=8)
                except Exception:
                    self.workers._kill_process_tree(process)
            self.sessions.update_session(
                workspace_id,
                session_id,
                status="idle",
                active_pid=None,
            )

        session = self.sessions.get_session(workspace_id, session_id)
        active_pid = int(session.get("active_pid") or 0)
        if active_pid and active_pid not in handled_pids:
            self._kill_pid_tree(active_pid, force=force)
            handled_pids.add(active_pid)
        runtime_session_id = str(session.get("runtime_session_id") or "").strip()
        if runtime_session_id:
            for pid in self._find_codewhale_process_ids(["exec", runtime_session_id]):
                if pid in handled_pids:
                    continue
                self._kill_pid_tree(pid, force=force)
                handled_pids.add(pid)
        self.sessions.update_session(workspace_id, session_id, status="idle", active_pid=None)

    def _kill_pid_tree(self, pid: int, *, force: bool) -> None:
        if sys.platform == "win32":
            command = ["taskkill", "/T", "/PID", str(pid)]
            if force:
                command.insert(2, "/F")
            subprocess.run(command, capture_output=True, timeout=10, check=False)
            return
        try:
            os.kill(pid, signal.SIGKILL if force else signal.SIGTERM)
        except ProcessLookupError:
            return

    def _find_codewhale_process_ids(self, tokens: list[str]) -> list[int]:
        return _find_codewhale_process_ids(tokens)

    def _find_workspace(self, workspace_id: str) -> dict[str, Any]:
        return self.workspaces.get_workspace(workspace_id)

    def _allocate_port(self) -> int:
        used_ports = self._known_worker_ports()
        for _ in range(300):
            self._next_port += 1
            if self._next_port > 43299:
                self._next_port = 43101
            if self._next_port in used_ports:
                continue
            if self._is_port_available(self._next_port):
                return self._next_port

        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.bind(("127.0.0.1", 0))
            return int(sock.getsockname()[1])

    def _known_worker_ports(self) -> set[int]:
        ports: set[int] = set()
        for workspace in self.workspaces.list_workspaces():
            workspace_id = str(workspace.get("id") or "")
            if not workspace_id:
                continue
            try:
                sessions = self.sessions.list_sessions(workspace_id)
            except Exception:
                continue
            for session in sessions:
                port = int(session.get("worker_port") or 0)
                if port:
                    ports.add(port)
        return ports

    @staticmethod
    def _is_port_available(port: int) -> bool:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            try:
                sock.bind(("127.0.0.1", port))
            except OSError:
                return False
        return True

    def _codewhale_command_catalog(self) -> list[dict[str, str]]:
        commands = [
            {
                "group": "Сессия",
                "label": "Помощь",
                "value": "/help",
                "description": "Показать встроенную справку CodeWhale",
            },
            {
                "group": "Сессия",
                "label": "Статус",
                "value": "/status",
                "description": "Состояние сессии, workspace и git",
            },
            {
                "group": "Сессия",
                "label": "Стоимость",
                "value": "/cost",
                "description": "Показать расход токенов",
            },
            {
                "group": "Сессия",
                "label": "Язык",
                "value": "/lang",
                "description": "Показать текущий язык сессии",
            },
            {
                "group": "Сессия",
                "label": "Русский язык",
                "value": "/lang ru",
                "description": "Переключить ответы сессии на русский",
            },
            {
                "group": "Сессия",
                "label": "Модель",
                "value": "/model",
                "description": "Показать текущую модель",
            },
            {
                "group": "Сессия",
                "label": "Текущий режим",
                "value": "/mode",
                "description": "Показать текущий режим CodeWhale",
            },
            {
                "group": "Режимы",
                "label": "Agent",
                "value": "/mode agent",
                "description": "Переключить сессию в agent mode",
            },
            {
                "group": "Режимы",
                "label": "Plan",
                "value": "/mode plan",
                "description": "Переключить сессию в plan mode",
            },
            {
                "group": "Режимы",
                "label": "YOLO",
                "value": "/mode yolo",
                "description": "Переключить сессию в yolo mode",
            },
            {
                "group": "Сессия",
                "label": "Сжать контекст",
                "value": "/compact",
                "description": "Сжать длинный контекст текущего диалога",
            },
            {
                "group": "Сессия",
                "label": "Версия",
                "value": "/version",
                "description": "Показать версию CodeWhale",
            },
            {
                "group": "Навыки",
                "label": "Список навыков",
                "value": "/skill",
                "description": "Показать все доступные навыки",
            },
            {
                "group": "Навыки",
                "label": "Карточка задачи",
                "value": "/skill family-task-card",
                "description": "Читать и обновлять карточку задачи через family-task-card",
            },
        ]
        commands.extend(self._list_skill_commands())
        return commands

    def _session_settings_patch(self, message: dict[str, Any]) -> dict[str, Any]:
        provider = str(message.get("provider") or "").strip()
        approval_policy = str(message.get("approval_policy") or "").strip()
        sandbox_mode = str(message.get("sandbox_mode") or "").strip()
        model = str(message.get("model") or "").strip()
        if provider not in ALLOWED_CODEWHALE_PROVIDERS:
            raise ValueError(f"unsupported provider: {provider}")
        if approval_policy not in ALLOWED_CODEWHALE_APPROVAL_POLICIES:
            raise ValueError(f"unsupported approval policy: {approval_policy}")
        if sandbox_mode not in ALLOWED_CODEWHALE_SANDBOX_MODES:
            raise ValueError(f"unsupported sandbox mode: {sandbox_mode}")
        return {
            "provider": provider,
            "model": model,
            "approval_policy": approval_policy,
            "sandbox_mode": sandbox_mode,
            "auto_mode": bool(message.get("auto_mode")),
        }

    def _task_card_metadata(
        self,
        message: dict[str, Any],
        workspace_id: str,
    ) -> dict[str, Any]:
        raw = message.get("task_card")
        if not isinstance(raw, dict):
            return {}
        allowed_keys = {
            "task_id",
            "agent_session_id",
            "actor_profile",
            "actor_phone",
            "api_url",
            "api_key",
            "policy_ticket",
            "scope",
            "project_id",
            "conversation_key",
            "task_type",
            "mode",
        }
        metadata = {
            key: str(raw.get(key) or "").strip()
            for key in allowed_keys
            if str(raw.get(key) or "").strip()
        }
        metadata["workspace_id"] = str(raw.get("workspace_id") or workspace_id).strip()
        return metadata

    def _list_skill_commands(self) -> list[dict[str, str]]:
        descriptions = dict(CODEWHALE_BUILTIN_SKILLS)
        skills_root = Path.home() / ".deepseek" / "skills"
        if skills_root.exists():
            for child in sorted(skills_root.iterdir(), key=lambda item: item.name.lower()):
                if not child.is_dir():
                    continue
                description = descriptions.get(child.name, "Загрузить навык CodeWhale")
                skill_md = child / "SKILL.md"
                if skill_md.exists():
                    try:
                        for line in skill_md.read_text(encoding="utf-8", errors="replace").splitlines():
                            if line.lower().startswith("description:"):
                                description = line.split(":", 1)[1].strip().strip('"')
                                break
                    except OSError:
                        pass
                descriptions[child.name] = description
        return [
            {
                "group": "Навыки",
                "label": name,
                "value": f"/skill {name}",
                "description": description,
            }
            for name, description in sorted(descriptions.items())
        ]

    def _authorize_message(self, message: dict[str, Any], msg_type: str) -> None:
        if not self.require_policy_ticket or msg_type not in PROTECTED_COMMANDS:
            return
        ticket = str(message.get("policy_ticket") or "").strip()
        if not ticket:
            raise ValueError("Нет прав на действие: требуется policy-ticket.")
        try:
            policy = validate_policy_ticket(
                ticket,
                secret=self.policy_ticket_secret,
            )
        except ValueError as exc:
            raise ValueError(f"Нет прав на действие: {exc}") from exc
        if not command_allowed_by_policy(msg_type, policy):
            raise ValueError("Нет прав на это действие в воркспейсе.")
        policy_workspace_id = str(policy.get("workspace_id") or "").strip()
        message_workspace_id = self._workspace_id(message)
        if (
            policy_workspace_id
            and message_workspace_id
            and policy_workspace_id != message_workspace_id
        ):
            raise ValueError("Нет прав на действие в выбранном воркспейсе.")

    def _workspace_id(self, message: dict[str, Any]) -> str:
        return str(message.get("workspace_id") or "").strip()

    def _session_id(self, message: dict[str, Any]) -> str:
        return str(message.get("session_id") or "").strip()


def _parse_tunnel(value: str) -> tuple[str, int]:
    host, sep, port_text = value.rpartition(":")
    if not sep or not host or not port_text.isdigit():
        raise ValueError("tunnel must be in host:port format")
    return host, int(port_text)


def _tunnel_registration_message(project_id: str, *, legacy: bool) -> dict[str, str]:
    return {
        "type": "register" if legacy else "codewhale_register",
        "project_id": project_id,
    }


def _is_tunnel_control_message(message: dict[str, Any]) -> bool:
    return str(message.get("type") or "") in {
        "codewhale_mobile_attached",
        "mobile_attached",
    }


async def run_tunnel_client(
    bridge: CodeWhaleBridge,
    tunnel_host: str,
    tunnel_port: int,
    project_id: str = "codewhale",
    *,
    legacy: bool = False,
) -> None:
    while True:
        try:
            await _run_tunnel_once(
                bridge,
                tunnel_host,
                tunnel_port,
                project_id,
                legacy=legacy,
            )
        except Exception as exc:
            print(f"[codewhale_bridge] tunnel error: {exc}", flush=True)
        await asyncio.sleep(RECONNECT_DELAY_SECONDS)


async def run_tunnel_clients(
    bridge: CodeWhaleBridge,
    tunnel_host: str,
    tunnel_port: int,
    project_id: str,
) -> None:
    await asyncio.gather(
        run_tunnel_client(
            bridge,
            tunnel_host,
            tunnel_port,
            project_id=project_id,
        ),
        run_tunnel_client(
            bridge,
            tunnel_host,
            tunnel_port,
            project_id=project_id,
            legacy=True,
        ),
    )


async def _run_tunnel_once(
    bridge: CodeWhaleBridge,
    tunnel_host: str,
    tunnel_port: int,
    project_id: str,
    *,
    legacy: bool = False,
) -> None:
    reader, writer = await asyncio.open_connection(
        tunnel_host,
        tunnel_port,
        limit=MAX_TUNNEL_LINE_BYTES,
    )
    write_lock = asyncio.Lock()

    async def send_json(payload: dict[str, Any]) -> None:
        async with write_lock:
            writer.write(json.dumps(payload, ensure_ascii=False).encode("utf-8") + b"\n")
            await writer.drain()

    async def stream_session(message: dict[str, Any]) -> None:
        queue: asyncio.Queue[dict[str, Any] | None] = asyncio.Queue()
        loop = asyncio.get_running_loop()

        def run_stream() -> None:
            try:
                for payload in bridge.stream_session_message(message):
                    loop.call_soon_threadsafe(queue.put_nowait, payload)
            except Exception as exc:
                loop.call_soon_threadsafe(
                    queue.put_nowait,
                    {
                        "type": "error",
                        "error": str(exc),
                        "workspace_id": bridge._workspace_id(message),
                        "session_id": bridge._session_id(message),
                    },
                )
            finally:
                loop.call_soon_threadsafe(queue.put_nowait, None)

        task = loop.run_in_executor(None, run_stream)
        try:
            while True:
                payload = await queue.get()
                if payload is None:
                    break
                await send_json(payload)
        finally:
            await task

    bridge.workspaces.discover_workspaces()

    writer.write(
        json.dumps(
            _tunnel_registration_message(project_id, legacy=legacy),
            ensure_ascii=False,
        ).encode("utf-8")
        + b"\n"
    )
    await writer.drain()
    print(
        f"[codewhale_bridge] connected to {tunnel_host}:{tunnel_port}",
        flush=True,
    )

    async def heartbeat_loop() -> None:
        """Send periodic pings to keep the tunnel connection alive."""
        while True:
            await asyncio.sleep(TUNNEL_HEARTBEAT_SECONDS)
            try:
                await send_json({"type": "codewhale_heartbeat"})
            except Exception:
                break

    heartbeat_task = asyncio.create_task(heartbeat_loop())
    try:
        while True:
            line = await reader.readline()
            if not line:
                break
            try:
                message = json.loads(line.decode("utf-8", "replace").strip())
            except json.JSONDecodeError:
                continue
            if _is_tunnel_control_message(message):
                continue
            if message.get("type") == "session_send":
                asyncio.create_task(stream_session(message))
                continue
            reply = bridge.handle_message(message)
            await send_json(reply)
    finally:
        heartbeat_task.cancel()
        try:
            await heartbeat_task
        except asyncio.CancelledError:
            pass
        writer.close()
        await writer.wait_closed()


def main() -> None:
    parser = argparse.ArgumentParser(description="CodeWhale workspace bridge")
    parser.add_argument("--tunnel", default="31.129.97.211:9877")
    parser.add_argument("--desktop", default=str(Path.home() / "Desktop"))
    parser.add_argument("--state-dir", default=".codewhale_bridge")
    parser.add_argument("--project-id", default="codewhale")
    args = parser.parse_args()

    tunnel_host, tunnel_port = _parse_tunnel(args.tunnel)
    bridge = CodeWhaleBridge(Path(args.desktop), Path(args.state_dir))
    asyncio.run(
        run_tunnel_clients(
            bridge,
            tunnel_host,
            tunnel_port,
            project_id=args.project_id,
        )
    )


if __name__ == "__main__":
    main()
