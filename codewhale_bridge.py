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
