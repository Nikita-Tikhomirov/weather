from __future__ import annotations

import json
import re
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
