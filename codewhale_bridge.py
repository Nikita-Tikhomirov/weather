from __future__ import annotations

import argparse
import asyncio
import json
import base64
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
import uuid
from pathlib import Path
from typing import Any, Callable, Iterable, Iterator


RECONNECT_DELAY_SECONDS = 5
TUNNEL_HEARTBEAT_SECONDS = 30
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
        return {"path": target.relative_to(base).as_posix(), "text": text, "size": len(raw)}

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

    def create_session(self, workspace_id: str, title: str) -> dict[str, Any]:
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
    ) -> None:
        self.sessions = sessions
        self.state_dir = state_dir.resolve()
        self.codewhale_cmd = codewhale_cmd
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
        self._active_execs: dict[tuple[str, str], subprocess.Popen] = {}
        self._session_stream_locks: dict[tuple[str, str], threading.Lock] = {}
        self._session_stream_locks_guard = threading.Lock()
        self._next_port = 43100
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
            return {
                "type": "session_list",
                "workspace_id": self._workspace_id(message),
                "sessions": self.sessions.list_sessions(self._workspace_id(message)),
            }
        if msg_type == "session_create":
            session = self.sessions.create_session(
                self._workspace_id(message),
                str(message.get("title") or ""),
            )
            return {"type": "session", "session": session}
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
        for workspace in self.workspaces.list_workspaces():
            if workspace["id"] == workspace_id:
                return workspace
        raise KeyError(f"workspace not found: {workspace_id}")

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
    reader, writer = await asyncio.open_connection(tunnel_host, tunnel_port)
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
