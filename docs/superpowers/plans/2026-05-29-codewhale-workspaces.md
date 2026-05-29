# CodeWhale Workspaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Russian-language mobile workspace/session system backed only by isolated CodeWhale workers, with reliable stop/kill/new-session controls.

**Architecture:** Add a new CodeWhale bridge path alongside the existing project bridge. The PC bridge owns workspace/session metadata and runs one isolated worker per active session; VPS only relays JSON lines; mobile gets new workspace screens and a clean chat plus separate session management screen.

**Tech Stack:** Python 3.10, CodeWhale v0.8.47, Windows PowerShell, asyncio JSON-line relay, Flutter/Dart, pytest, GitHub Actions mobile APK workflow.

---

## File Structure

- Create: `codewhale_bridge.py` — PC-side workspace/session bridge and JSON protocol handler.
- Create: `codewhale_launcher.py` — lightweight launcher that keeps the CodeWhale bridge registered with VPS.
- Create: `start_codewhale_bridge.ps1` — starts the launcher with resolved Python.
- Create: `install_codewhale_bridge_task.ps1` — Windows scheduled task installer.
- Create: `tests/test_codewhale_bridge.py` — manager, metadata, and process lifecycle tests.
- Modify: `tunnel_server.py` — add separate `codewhale_launcher` and `codewhale_workspace` message types without breaking old bridge.
- Modify: `tests/test_tunnel_server_launcher.py` — relay tests for CodeWhale path.
- Create: `mobile_app/lib/models/workspace_item.dart`.
- Create: `mobile_app/lib/models/workspace_session.dart`.
- Create: `mobile_app/lib/services/codewhale_bridge_service.dart`.
- Create: `mobile_app/lib/features/workspaces/workspace_list_view.dart`.
- Create: `mobile_app/lib/features/workspaces/workspace_detail_view.dart`.
- Create: `mobile_app/lib/features/workspaces/session_chat_view.dart`.
- Create: `mobile_app/lib/features/workspaces/session_management_view.dart`.
- Modify: `mobile_app/lib/features/home/home_page.dart` and related navigation files only after service/model tests are in place.
- Modify: `README.md` after command behavior is stable.

---

### Task 1: PC Workspace Registry

**Files:**
- Create: `codewhale_bridge.py`
- Create: `tests/test_codewhale_bridge.py`

- [ ] **Step 1: Write failing tests**

```python
import json
import tempfile
import unittest
from pathlib import Path

from codewhale_bridge import WorkspaceRegistry


class WorkspaceRegistryTests(unittest.TestCase):
    def test_create_workspace_under_desktop(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            desktop = Path(tmp) / "Desktop"
            state = Path(tmp) / "state"
            registry = WorkspaceRegistry(desktop, state)

            workspace = registry.create_workspace("Мой проект")

            self.assertEqual(workspace["name"], "Мой проект")
            self.assertTrue(Path(workspace["path"]).exists())
            self.assertTrue(Path(workspace["path"]).is_dir())
            self.assertEqual(workspace["status"], "available")
            self.assertEqual(len(registry.list_workspaces()), 1)

    def test_attach_rejects_path_outside_desktop(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            desktop = Path(tmp) / "Desktop"
            outside = Path(tmp) / "Outside"
            outside.mkdir(parents=True)
            registry = WorkspaceRegistry(desktop, Path(tmp) / "state")

            with self.assertRaises(ValueError):
                registry.attach_workspace("Внешний", outside)

    def test_registry_persists_workspaces(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            desktop = Path(tmp) / "Desktop"
            state = Path(tmp) / "state"
            first = WorkspaceRegistry(desktop, state)
            created = first.create_workspace("Persisted")

            second = WorkspaceRegistry(desktop, state)
            loaded = second.list_workspaces()

            self.assertEqual(loaded[0]["id"], created["id"])
            self.assertEqual(loaded[0]["name"], "Persisted")
```

- [ ] **Step 2: Run tests to verify failure**

```powershell
python -m pytest tests\test_codewhale_bridge.py -q
```

Expected: import failure because `codewhale_bridge.py` does not exist.

- [ ] **Step 3: Implement registry**

```python
from __future__ import annotations

import json
import re
import time
from pathlib import Path


def _now() -> int:
    return int(time.time())


def _safe_id(name: str) -> str:
    base = re.sub(r"[^A-Za-z0-9_.-]+", "-", name.strip()).strip("-").lower()
    return base or f"workspace-{_now()}"


class WorkspaceRegistry:
    def __init__(self, desktop_root: Path, state_dir: Path):
        self.desktop_root = desktop_root.resolve()
        self.state_dir = state_dir
        self.path = state_dir / "workspaces.json"
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.desktop_root.mkdir(parents=True, exist_ok=True)

    def list_workspaces(self) -> list[dict]:
        return self._load()

    def create_workspace(self, name: str) -> dict:
        clean_name = name.strip()
        if not clean_name:
            raise ValueError("workspace name is required")
        folder = self.desktop_root / clean_name
        folder.mkdir(parents=True, exist_ok=True)
        return self._upsert(clean_name, folder)

    def attach_workspace(self, name: str, folder: Path) -> dict:
        target = folder.resolve()
        target.relative_to(self.desktop_root)
        if not target.exists() or not target.is_dir():
            raise ValueError("workspace folder does not exist")
        return self._upsert(name.strip() or target.name, target)

    def _upsert(self, name: str, folder: Path) -> dict:
        items = self._load()
        wid = _safe_id(name)
        existing_ids = {item["id"] for item in items}
        if wid in existing_ids:
            suffix = 2
            while f"{wid}-{suffix}" in existing_ids:
                suffix += 1
            wid = f"{wid}-{suffix}"
        item = {
            "id": wid,
            "name": name,
            "path": str(folder.resolve()),
            "status": "available",
            "created_at": _now(),
            "updated_at": _now(),
        }
        items.append(item)
        self._save(items)
        return item

    def _load(self) -> list[dict]:
        if not self.path.exists():
            return []
        data = json.loads(self.path.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []

    def _save(self, items: list[dict]) -> None:
        self.path.write_text(
            json.dumps(items, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
```

- [ ] **Step 4: Run registry tests**

```powershell
python -m pytest tests\test_codewhale_bridge.py -q
```

Expected: 3 passed.

- [ ] **Step 5: Commit**

```powershell
git add codewhale_bridge.py tests/test_codewhale_bridge.py
git commit -m "feat: add codewhale workspace registry"
```

---

### Task 2: Session Registry And Event Replay

**Files:**
- Modify: `codewhale_bridge.py`
- Modify: `tests/test_codewhale_bridge.py`

- [ ] **Step 1: Write failing tests**

```python
from codewhale_bridge import SessionRegistry


class SessionRegistryTests(unittest.TestCase):
    def test_create_session_is_independent_of_worker(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            registry = SessionRegistry(Path(tmp) / "state")

            session = registry.create_session("weather", "Новая сессия")

            self.assertEqual(session["workspace_id"], "weather")
            self.assertEqual(session["status"], "ready")
            self.assertEqual(registry.list_sessions("weather")[0]["id"], session["id"])

    def test_append_and_replay_events(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            registry = SessionRegistry(Path(tmp) / "state")
            session = registry.create_session("weather", "Chat")

            registry.append_event("weather", session["id"], {"type": "output", "text": "Привет"})

            events = registry.load_events("weather", session["id"])
            self.assertEqual(events[0]["text"], "Привет")
```

- [ ] **Step 2: Run tests to verify failure**

```powershell
python -m pytest tests\test_codewhale_bridge.py::SessionRegistryTests -q
```

Expected: import failure for `SessionRegistry`.

- [ ] **Step 3: Implement session registry**

Add `SessionRegistry` with:

- `create_session(workspace_id, title)`;
- `list_sessions(workspace_id)`;
- `get_session(workspace_id, session_id)`;
- `update_session(workspace_id, session_id, **patch)`;
- `append_event(workspace_id, session_id, event)`;
- `load_events(workspace_id, session_id, limit=300)`.

Use:

```text
<state_dir>/sessions/<workspace_id>/<session_id>.json
<state_dir>/sessions/<workspace_id>/<session_id>.jsonl
```

- [ ] **Step 4: Run tests**

```powershell
python -m pytest tests\test_codewhale_bridge.py -q
```

Expected: all pass.

- [ ] **Step 5: Commit**

```powershell
git add codewhale_bridge.py tests/test_codewhale_bridge.py
git commit -m "feat: add codewhale session registry"
```

---

### Task 3: Isolated CodeWhale Worker Lifecycle

**Files:**
- Modify: `codewhale_bridge.py`
- Modify: `tests/test_codewhale_bridge.py`

- [ ] **Step 1: Write failing test for hard kill scope**

```python
class FakeProcess:
    def __init__(self, pid: int):
        self.pid = pid
        self.killed = False
    def poll(self):
        return None if not self.killed else 1
    def kill(self):
        self.killed = True


def test_kill_session_only_kills_target_worker(self) -> None:
    manager = CodeWhaleWorkerManager(Path("C:/Users/user/Desktop"))
    first = FakeProcess(1)
    second = FakeProcess(2)
    manager._workers["s1"] = first
    manager._workers["s2"] = second

    manager.kill_worker("s1")

    self.assertTrue(first.killed)
    self.assertFalse(second.killed)
```

- [ ] **Step 2: Run test to verify failure**

```powershell
python -m pytest tests\test_codewhale_bridge.py::test_kill_session_only_kills_target_worker -q
```

Expected: missing `CodeWhaleWorkerManager`.

- [ ] **Step 3: Implement worker manager**

Add:

- `start_worker(workspace_path, session_id, port)`;
- `health(session_id)`;
- `stop_turn(session_id)`;
- `kill_worker(session_id)`;
- `restart_worker(...)`.

Start command:

```python
[
    "codewhale",
    "serve",
    "--http",
    "--host",
    "127.0.0.1",
    "--port",
    str(port),
]
```

Run it with `cwd=workspace_path`. Write stdout/stderr to the session log files. Keep process handles in memory.

- [ ] **Step 4: Add Windows process-tree kill**

Use PowerShell/taskkill for real processes:

```python
subprocess.run(["taskkill", "/F", "/T", "/PID", str(pid)], check=False)
```

Use fake process `.kill()` in tests.

- [ ] **Step 5: Run tests**

```powershell
python -m pytest tests\test_codewhale_bridge.py -q
```

Expected: pass.

- [ ] **Step 6: Commit**

```powershell
git add codewhale_bridge.py tests/test_codewhale_bridge.py
git commit -m "feat: manage isolated codewhale workers"
```

---

### Task 4: CodeWhale Bridge JSON Protocol

**Files:**
- Modify: `codewhale_bridge.py`
- Create/modify: `tests/test_codewhale_bridge.py`

- [ ] **Step 1: Define protocol handler tests**

Test commands:

- `workspace_list`
- `workspace_create`
- `workspace_attach`
- `session_list`
- `session_create`
- `session_open`
- `session_kill`
- `session_health`

Example:

```python
def test_handle_workspace_create_returns_workspace_event(self) -> None:
    bridge = CodeWhaleBridge(desktop_root=desktop, state_dir=state)
    reply = bridge.handle_message({"type": "workspace_create", "name": "Demo"})
    self.assertEqual(reply["type"], "workspace")
    self.assertEqual(reply["workspace"]["name"], "Demo")
```

- [ ] **Step 2: Run tests to verify failure**

```powershell
python -m pytest tests\test_codewhale_bridge.py -q
```

Expected: missing `CodeWhaleBridge`.

- [ ] **Step 3: Implement protocol handler**

`CodeWhaleBridge.handle_message(msg)` returns JSON-serializable replies and never throws to caller. Errors return:

```json
{"type": "error", "text": "...", "request_type": "..."}
```

- [ ] **Step 4: Add CLI skeleton**

`python codewhale_bridge.py --tunnel 31.129.97.211:9877` registers with VPS as `codewhale_bridge` and handles JSON lines.

- [ ] **Step 5: Run tests**

```powershell
python -m pytest tests\test_codewhale_bridge.py -q
```

Expected: pass.

- [ ] **Step 6: Commit**

```powershell
git add codewhale_bridge.py tests/test_codewhale_bridge.py
git commit -m "feat: add codewhale bridge protocol"
```

---

### Task 5: VPS Relay Support For CodeWhale Bridge

**Files:**
- Modify: `tunnel_server.py`
- Modify: `tests/test_tunnel_server_launcher.py`

- [ ] **Step 1: Write relay tests**

Add tests proving:

- mobile `codewhale_connect` pairs with PC `codewhale_register`;
- messages relay both directions;
- old `project_bridge` tests still pass.

- [ ] **Step 2: Run failing tests**

```powershell
python -m pytest tests\test_tunnel_server_launcher.py -q
```

Expected: new tests fail.

- [ ] **Step 3: Implement relay**

Add new first-message types:

- `codewhale_register`
- `codewhale_connect`
- `codewhale_launcher`

Keep separate maps from old project bridge maps:

```python
self._codewhale_bridge = None
self._codewhale_mobiles = []
```

- [ ] **Step 4: Run tunnel tests**

```powershell
python -m pytest tests\test_tunnel_server_launcher.py -q
```

Expected: old and new tests pass.

- [ ] **Step 5: Deploy VPS**

Upload `tunnel_server.py`, restart `project-tunnel.service`, verify active.

- [ ] **Step 6: Commit**

```powershell
git add tunnel_server.py tests/test_tunnel_server_launcher.py
git commit -m "feat: relay codewhale workspace bridge"
```

---

### Task 6: Windows Autostart For CodeWhale Bridge

**Files:**
- Create: `codewhale_launcher.py`
- Create: `start_codewhale_bridge.ps1`
- Create: `install_codewhale_bridge_task.ps1`
- Test: `tests/test_codewhale_bridge.py` for process discovery helpers

- [ ] **Step 1: Implement launcher**

Launcher keeps `codewhale_bridge.py --tunnel ...` alive and answers VPS health pings.

- [ ] **Step 2: Implement PowerShell start script**

Resolve Python and verify `codewhale --version` before starting.

- [ ] **Step 3: Implement scheduled task installer**

Task name:

```text
CodeWhaleBridgeAtLogon
```

Use `Restart=always` equivalent settings and Startup fallback.

- [ ] **Step 4: Run installer**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install_codewhale_bridge_task.ps1
```

- [ ] **Step 5: Verify**

```powershell
Get-ScheduledTask -TaskName CodeWhaleBridgeAtLogon
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -like '*codewhale_bridge.py*' }
```

- [ ] **Step 6: Commit**

```powershell
git add codewhale_launcher.py start_codewhale_bridge.ps1 install_codewhale_bridge_task.ps1 tests/test_codewhale_bridge.py
git commit -m "feat: autostart codewhale bridge"
```

---

### Task 7: Mobile Models And Service

**Files:**
- Create: `mobile_app/lib/models/workspace_item.dart`
- Create: `mobile_app/lib/models/workspace_session.dart`
- Create: `mobile_app/lib/services/codewhale_bridge_service.dart`
- Test: `mobile_app/test/codewhale_bridge_service_test.dart`

- [ ] **Step 1: Add model tests**

Test JSON parse for workspace/session statuses.

- [ ] **Step 2: Add service tests**

Test outgoing JSON commands:

- `workspace_list`
- `workspace_create`
- `workspace_attach`
- `session_list`
- `session_create`
- `session_send`
- `session_stop`
- `session_kill`
- `session_health`

- [ ] **Step 3: Implement models and service**

Service mirrors current `ProjectBridgeService` framing but uses CodeWhale message types.

- [ ] **Step 4: Run Flutter tests**

```powershell
flutter test mobile_app\test\codewhale_bridge_service_test.dart
```

Expected: pass in local Flutter or GitHub Actions.

- [ ] **Step 5: Commit**

```powershell
git add mobile_app/lib/models/workspace_item.dart mobile_app/lib/models/workspace_session.dart mobile_app/lib/services/codewhale_bridge_service.dart mobile_app/test/codewhale_bridge_service_test.dart
git commit -m "feat: add mobile codewhale bridge service"
```

---

### Task 8: Mobile Workspace Screens

**Files:**
- Create: `mobile_app/lib/features/workspaces/workspace_list_view.dart`
- Create: `mobile_app/lib/features/workspaces/workspace_detail_view.dart`
- Create: `mobile_app/lib/features/workspaces/session_chat_view.dart`
- Create: `mobile_app/lib/features/workspaces/session_management_view.dart`
- Modify navigation in `mobile_app/lib/features/home/home_page.dart` or extracted home shell files.

- [ ] **Step 1: Build workspace list**

Russian labels:

- `Рабочие пространства`
- `Создать`
- `Подключить папку`
- statuses: `Доступно`, `Нет папки`, `Ошибка`, `Запускается`

- [ ] **Step 2: Build workspace detail**

Tabs:

- `Сессии`
- `Файлы`
- `Настройки`

- [ ] **Step 3: Build session chat**

Clean chat:

- messages;
- input;
- one menu/settings button leading to management.

- [ ] **Step 4: Build session management**

Controls:

- `Остановить ход`
- `Жестко убить сессию`
- `Перезапустить worker`
- `Новая сессия`
- `Диагностика`

- [ ] **Step 5: Run mobile checks**

```powershell
flutter analyze
flutter test
```

- [ ] **Step 6: Commit**

```powershell
git add mobile_app/lib/features/workspaces mobile_app/lib/features/home
git commit -m "feat: add codewhale workspace screens"
```

---

### Task 9: End-To-End Smoke

**Files:**
- Modify: `README.md`
- Add optional: `scripts/smoke_codewhale_bridge.ps1`

- [ ] **Step 1: Add smoke script**

Script verifies:

- `codewhale --version`;
- scheduled task exists;
- bridge process exists;
- VPS relay responds;
- workspace create command works;
- session create command works;
- hard kill only kills target worker.

- [ ] **Step 2: Run smoke**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke_codewhale_bridge.ps1
```

- [ ] **Step 3: Update README**

Document setup and recovery commands.

- [ ] **Step 4: Commit**

```powershell
git add README.md scripts/smoke_codewhale_bridge.ps1
git commit -m "docs: add codewhale bridge runbook"
```

---

## Acceptance Checklist

- [ ] `codewhale --version` works on PC.
- [ ] User can create a desktop workspace from mobile.
- [ ] User can attach an existing desktop folder.
- [ ] User can create multiple sessions inside one workspace.
- [ ] User can open a running session.
- [ ] User can open completed session history.
- [ ] User can stop active turn.
- [ ] User can hard kill a hung session.
- [ ] Killing one session does not kill another.
- [ ] New session works while an old session is hung.
- [ ] Chat UI is not crowded with management buttons.
- [ ] Management screen exposes modes, skills/functions placeholder, diagnostics, stop/kill/restart.
- [ ] Old DeepSeek bridge remains untouched until CodeWhale path is stable.
