from __future__ import annotations

import json
import os
import re
import signal
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any


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


class WorkspaceRegistry:
    def __init__(self, desktop_root: Path, state_dir: Path) -> None:
        self.desktop_root = desktop_root.resolve()
        self.state_dir = state_dir.resolve()
        self.path = self.state_dir / "workspaces.json"
        self.desktop_root.mkdir(parents=True, exist_ok=True)
        self.state_dir.mkdir(parents=True, exist_ok=True)

    def list_workspaces(self) -> list[dict[str, Any]]:
        return [dict(item) for item in self._load()]

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
        allowed = {"title", "status", "worker_pid", "worker_port", "last_event_seq"}
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
        return dict(data)

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
            f"127.0.0.1:{port}",
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
        process = self._workers.get(key)
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=timeout_seconds)
            except Exception:
                return self.kill_worker(workspace_id, session_id)
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
        )

    def kill_worker(self, workspace_id: str, session_id: str) -> dict[str, Any]:
        key = self._key(workspace_id, session_id)
        process = self._workers.pop(key, None)
        if process is not None and process.poll() is None:
            self._kill_process_tree(process)
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
        )

    def health(self, workspace_id: str, session_id: str) -> dict[str, Any]:
        key = self._key(workspace_id, session_id)
        process = self._workers.get(key)
        session = self.sessions.get_session(workspace_id, session_id)
        if process is None:
            return {**session, "worker_alive": False}
        return {**session, "worker_alive": process.poll() is None}

    def _open_worker_logs(self, workspace_id: str, session_id: str):
        logs_dir = self.state_dir / "sessions" / workspace_id
        logs_dir.mkdir(parents=True, exist_ok=True)
        return (logs_dir / f"{session_id}.worker.log").open("a", encoding="utf-8")

    def _kill_process_tree(self, process: subprocess.Popen) -> None:
        if sys.platform == "win32":
            subprocess.run(
                ["taskkill", "/T", "/F", "/PID", str(process.pid)],
                capture_output=True,
                timeout=10,
                check=False,
            )
        else:
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except Exception:
                process.kill()
        if process.poll() is None:
            process.kill()
            try:
                process.wait(timeout=5)
            except Exception:
                pass

    def _creation_flags(self) -> int:
        if sys.platform != "win32":
            return 0
        return getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)

    def _key(self, workspace_id: str, session_id: str) -> tuple[str, str]:
        return (
            self.sessions._require_key(workspace_id, "workspace_id"),
            self.sessions._require_key(session_id, "session_id"),
        )
