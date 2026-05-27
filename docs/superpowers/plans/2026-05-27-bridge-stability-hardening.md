# Bridge Stability Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make project chats recover from DeepSeek/runtime/VPS/GitHub failures without freezing stop, new session, or unrelated projects.

**Architecture:** Replace the current global "restart the whole bridge" behavior with isolated project workers, bounded runtime operations, explicit health states, and controlled restart scopes. Keep the VPS relay and Windows autostart, but make each layer fail independently and report actionable state to mobile.

**Tech Stack:** Python 3.10, asyncio, subprocess, Windows PowerShell scheduled tasks, deepseek-tui HTTP runtime, Flutter/Dart mobile client, pytest, flutter test/analyze via GitHub Actions.

---

## Evidence From Current System

- `bridge_launcher.log` shows repeated full `project_bridge.py` restarts after `start_bridge`.
- `bridge_launcher_project_bridge.log` shows repeated registration of all projects every few seconds, which means bridge connections are churny and not treated as long-lived workers.
- `deepseek_runtime.err.log` contains repeated `Failed to bind 127.0.0.1:7879`, showing multiple runtime start attempts against the same global port.
- `bridge_launcher_watchdog.log` shows many launcher restarts when VPS is temporarily unavailable. This restarts the PC side even when the local bridge process may still be healthy.
- Current `start_bridge` kills all `project_bridge.py` instances for the tunnel, so a phone action or VPS recovery can drop every project.
- `ProjectSession.stop_current_prompt()` depends on a responsive runtime interrupt call. If the runtime HTTP server is wedged, stop/new session cannot reliably recover.

---

## File Structure

- Modify `bridge_launcher.py`: make start requests idempotent, add scoped restart commands, stop killing a healthy bridge by default.
- Modify `project_bridge.py`: introduce per-project worker state, operation timeouts, runtime restart escalation, and health reporting.
- Modify `tunnel_server.py`: distinguish "ensure bridge exists" from "force restart bridge"; avoid broad restarts from mobile attach.
- Modify `mobile_app/lib/services/project_bridge_service.dart`: add control message types for health, force restart current project, force restart runtime.
- Modify `mobile_app/lib/features/projects/project_chat_view.dart`: expose state-aware recovery controls and disable misleading actions while a recovery is in progress.
- Add tests in `tests/test_bridge_launcher.py`, `tests/test_project_bridge_upload.py`, `tests/test_tunnel_server_launcher.py`.
- Add docs in `README.md`: operator commands and recovery behavior.

---

### Task 1: Make Launcher Start Idempotent

**Files:**
- Modify: `bridge_launcher.py`
- Test: `tests/test_bridge_launcher.py`

- [ ] **Step 1: Write failing test**

Add a test proving `start_bridge()` does not kill an already healthy `project_bridge.py` when the command is only an "ensure started" request.

```python
def test_start_bridge_is_idempotent_when_bridge_exists(self) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        launcher = BridgeLauncher("31.129.97.211", 9877, Path(tmp))
        with (
            patch.object(launcher, "_find_bridge_pids", return_value=[1234]),
            patch.object(launcher, "_kill_stale_bridge") as kill_stale,
            patch.object(launcher, "_spawn_bridge", return_value=True) as spawn_bridge,
        ):
            self.assertTrue(launcher.start_bridge(force=False))
        kill_stale.assert_not_called()
        spawn_bridge.assert_not_called()
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```powershell
python -m pytest tests\test_bridge_launcher.py::BridgeLauncherTests::test_start_bridge_is_idempotent_when_bridge_exists -q
```

Expected: fail because `start_bridge()` has no `force` option and always kills stale bridge.

- [ ] **Step 3: Implement minimal launcher change**

Change `start_bridge`:

```python
def start_bridge(self, force: bool = False) -> bool:
    """Ensure project_bridge.py is running; force restarts only when requested."""
    if not force and self.ensure_bridge_running():
        return True
    self._kill_stale_bridge()
    return self._spawn_bridge()
```

Handle messages:

```python
force = bool(msg.get("force"))
started = self.start_bridge(force=force)
```

- [ ] **Step 4: Run launcher tests**

Run:

```powershell
python -m pytest tests\test_bridge_launcher.py -q
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```powershell
git add bridge_launcher.py tests/test_bridge_launcher.py
git commit -m "fix: make bridge launcher start idempotent"
```

---

### Task 2: Stop VPS From Forcing Full Restarts On Normal Mobile Attach

**Files:**
- Modify: `tunnel_server.py`
- Test: `tests/test_tunnel_server_launcher.py`

- [ ] **Step 1: Write failing test**

Add a test that mobile connect with missing project bridge sends an idempotent start request, not a force restart.

```python
async def test_mobile_missing_bridge_requests_idempotent_start(self) -> None:
    launcher_reader, launcher_writer = await asyncio.open_connection("127.0.0.1", self.port)
    launcher_writer.write(json.dumps({"type": "launcher", "project_id": "launcher"}).encode("utf-8") + b"\n")
    await launcher_writer.drain()
    self.assertEqual((await _read_json(launcher_reader))["type"], "status")

    mobile_reader, mobile_writer = await asyncio.open_connection("127.0.0.1", self.port)
    mobile_writer.write(json.dumps({"type": "connect", "project_id": "cifra"}).encode("utf-8") + b"\n")
    await mobile_writer.drain()

    ping = await _read_json(launcher_reader)
    launcher_writer.write(json.dumps({"type": "pong", "ping_id": ping["ping_id"]}).encode("utf-8") + b"\n")
    await launcher_writer.drain()
    command = await _read_json(launcher_reader)
    self.assertEqual(command["type"], "start_bridge")
    self.assertFalse(command.get("force", False))

    mobile_writer.close()
    launcher_writer.close()
    await mobile_writer.wait_closed()
    await launcher_writer.wait_closed()
```

- [ ] **Step 2: Run test to verify it fails if current payload lacks explicit force state**

Run:

```powershell
python -m pytest tests\test_tunnel_server_launcher.py::TunnelServerLauncherTests::test_mobile_missing_bridge_requests_idempotent_start -q
```

Expected: fail until payload explicitly carries `force: false`.

- [ ] **Step 3: Implement explicit command types**

Change `_request_bridge_start(project_id, force=False)` and payload:

```python
payload = json.dumps(
    {"type": "start_bridge", "project_id": project_id, "force": force},
    ensure_ascii=False,
).encode("utf-8") + b"\n"
```

Use `force=False` from `_handle_mobile`. Reserve `force=True` for explicit mobile "restart bridge" command.

- [ ] **Step 4: Run tunnel tests**

```powershell
python -m pytest tests\test_tunnel_server_launcher.py -q
```

Expected: all pass.

- [ ] **Step 5: Deploy VPS relay and verify**

Upload `tunnel_server.py`, restart `project-tunnel.service`, then run:

```powershell
python - <<'PY'
import json, socket
s = socket.create_connection(("31.129.97.211", 9877), timeout=5)
s.sendall(json.dumps({"type": "launcher_ping", "project_id": "launcher"}).encode() + b"\n")
print(s.recv(4096).decode())
PY
```

Expected: `Bridge launcher is connected`.

- [ ] **Step 6: Commit**

```powershell
git add tunnel_server.py tests/test_tunnel_server_launcher.py
git commit -m "fix: avoid full bridge restart on mobile attach"
```

---

### Task 3: Add Runtime Operation Timeouts And Recovery States

**Files:**
- Modify: `project_bridge.py`
- Test: `tests/test_project_bridge_upload.py`

- [ ] **Step 1: Write failing test**

Add a fake runtime whose stream never yields completion. Verify session emits a recoverable error and clears `_current_turn_id`.

```python
class _HangingRuntime:
    def ensure_running(self, cwd: str) -> None:
        pass
    def create_thread(self, workspace: str, title: str) -> str:
        return "thread_1"
    def send_turn(self, thread_id: str, prompt: str) -> str:
        return "turn_1"
    def stream_events(self, thread_id: str, since_seq: int):
        while True:
            time.sleep(0.1)

def test_runtime_turn_timeout_clears_busy_state(self) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        session = ProjectSession("cifra", tmp)
        session.running = True
        session.session_id = "s1"
        writer = _CollectingWriter()
        session.writers.append(writer)
        with patch("project_bridge.RUNTIME_TURN_TIMEOUT_SECONDS", 0.2):
            with patch("project_bridge._RUNTIME", _HangingRuntime()):
                session._run_prompt("prompt")
        self.assertEqual(session._current_turn_id, "")
        self.assertTrue(any(msg["type"] == "error" for msg in writer.messages))
```

- [ ] **Step 2: Run failing test**

```powershell
python -m pytest tests\test_project_bridge_upload.py::ProjectBridgeUploadTests::test_runtime_turn_timeout_clears_busy_state -q
```

Expected: fail because there is no per-turn timeout.

- [ ] **Step 3: Implement timeout boundary**

Add constants:

```python
RUNTIME_TURN_TIMEOUT_SECONDS = 600
RUNTIME_STREAM_IDLE_TIMEOUT_SECONDS = 90
```

Wrap runtime stream loop with elapsed and idle checks. On timeout:

```python
self._broadcast("error", "DeepSeek завис. Сессия разблокирована, можно повторить или перезапустить runtime.")
self._current_turn_id = ""
raise TimeoutError("deepseek runtime turn timeout")
```

- [ ] **Step 4: Run tests**

```powershell
python -m pytest tests\test_project_bridge_upload.py -q
```

Expected: pass.

- [ ] **Step 5: Commit**

```powershell
git add project_bridge.py tests/test_project_bridge_upload.py
git commit -m "fix: bound deepseek runtime turns"
```

---

### Task 4: Make Stop And New Session Work Even When Runtime Is Wedged

**Files:**
- Modify: `project_bridge.py`
- Test: `tests/test_project_bridge_upload.py`

- [ ] **Step 1: Write failing test**

Add a fake runtime whose `interrupt_turn` hangs. Verify `stop_current_prompt()` does not block forever and marks session recoverable.

```python
class _HangingInterruptRuntime:
    def interrupt_turn(self, thread_id: str, turn_id: str) -> None:
        time.sleep(5)

def test_stop_current_prompt_times_out_when_runtime_interrupt_hangs(self) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        session = ProjectSession("cifra", tmp)
        session.running = True
        session.session_id = "s1"
        session._runtime_thread_id = "thread_1"
        session._current_turn_id = "turn_1"
        writer = _CollectingWriter()
        session.writers.append(writer)
        with patch("project_bridge.RUNTIME_INTERRUPT_TIMEOUT_SECONDS", 0.2):
            with patch("project_bridge._RUNTIME", _HangingInterruptRuntime()):
                self.assertFalse(session.stop_current_prompt())
        self.assertEqual(session._current_turn_id, "")
        self.assertTrue(any("перезапустить" in msg["text"] for msg in writer.messages))
```

- [ ] **Step 2: Run failing test**

```powershell
python -m pytest tests\test_project_bridge_upload.py::ProjectBridgeUploadTests::test_stop_current_prompt_times_out_when_runtime_interrupt_hangs -q
```

Expected: fail or hang before implementation.

- [ ] **Step 3: Implement interrupt timeout**

Run interrupt in a short-lived thread or executor and join with timeout:

```python
RUNTIME_INTERRUPT_TIMEOUT_SECONDS = 5
```

If timeout, clear `_current_turn_id`, broadcast recovery message, and return `False`.

- [ ] **Step 4: Make new session local-first**

`start_new_session()` must clear local state and current turn immediately before any runtime call. It must not depend on a live runtime process.

- [ ] **Step 5: Run tests**

```powershell
python -m pytest tests\test_project_bridge_upload.py -q
```

Expected: pass.

- [ ] **Step 6: Commit**

```powershell
git add project_bridge.py tests/test_project_bridge_upload.py
git commit -m "fix: make project stop and new session nonblocking"
```

---

### Task 5: Isolate Runtime Failures From Other Projects

**Files:**
- Modify: `project_bridge.py`
- Test: new tests in `tests/test_project_bridge_upload.py`

- [ ] **Step 1: Decide isolation strategy**

Use one of these two strategies:

1. Preferred: one deepseek runtime port per project, derived from stable project index.
2. Minimum viable: one global runtime process but per-project locks and a runtime circuit breaker that fails only the active session and does not restart `project_bridge.py`.

Pick strategy 1 unless deepseek-tui cannot safely run multiple runtime servers.

- [ ] **Step 2: Write failing test for circuit breaker**

```python
def test_runtime_failure_does_not_mark_other_project_session_dead(self) -> None:
    with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
        first = ProjectSession("cifra", a)
        second = ProjectSession("tudushka", b)
        first.running = True
        second.running = True
        first.session_id = "s1"
        second.session_id = "s2"
        with patch("project_bridge._RUNTIME", _FailingRuntime()):
            first._run_prompt("bad")
        self.assertTrue(second.running)
```

- [ ] **Step 3: Implement runtime circuit breaker**

Track:

```python
self._runtime_failed_at: float | None = None
self._runtime_failure_count = 0
```

If one project fails, broadcast only to that project's writers. Do not terminate `project_bridge.py`. Do not clear other sessions.

- [ ] **Step 4: Add optional per-project runtime ports**

If using per-project runtime:

```python
RUNTIME_BASE_PORT = 7879
port = RUNTIME_BASE_PORT + project_index
```

Runtime files:

```text
.deepseek/state/runtime/<project_id>/deepseek_runtime.log
.deepseek/state/runtime/<project_id>/deepseek_runtime.err.log
```

- [ ] **Step 5: Run tests**

```powershell
python -m pytest tests\test_project_bridge_upload.py tests\test_project_bridge_file_listing.py -q
```

Expected: pass.

- [ ] **Step 6: Commit**

```powershell
git add project_bridge.py tests/test_project_bridge_upload.py
git commit -m "fix: isolate project runtime failures"
```

---

### Task 6: Add Explicit Recovery Controls To Mobile

**Files:**
- Modify: `mobile_app/lib/services/project_bridge_service.dart`
- Modify: `mobile_app/lib/features/projects/project_chat_view.dart`
- Test: `mobile_app/test/project_bridge_service_test.dart`

- [ ] **Step 1: Add service methods**

```dart
void restartCurrentProjectBridge() {
  _sendRaw('${jsonEncode({'type': 'restart_project_bridge'})}\n');
}

void restartDeepseekRuntime() {
  _sendRaw('${jsonEncode({'type': 'restart_deepseek_runtime'})}\n');
}
```

- [ ] **Step 2: Add tests**

In `project_bridge_service_test.dart`, verify commands are sent as JSON lines.

- [ ] **Step 3: Add UI actions**

In `ProjectChatView`, distinguish:

- power icon: ensure bridge exists
- restart icon: force restart current project bridge
- stop icon: interrupt current turn
- new session icon: local session reset

- [ ] **Step 4: Run mobile checks**

Run in GitHub Actions or local Flutter environment:

```powershell
flutter analyze
flutter test
```

Expected: pass.

- [ ] **Step 5: Commit**

```powershell
git add mobile_app/lib/services/project_bridge_service.dart mobile_app/lib/features/projects/project_chat_view.dart mobile_app/test/project_bridge_service_test.dart
git commit -m "feat: add project bridge recovery controls"
```

---

### Task 7: Add Health Snapshots And Diagnostics

**Files:**
- Modify: `project_bridge.py`
- Modify: `bridge_launcher.py`
- Modify: `tunnel_server.py`
- Modify: `README.md`
- Test: Python tests for health payload shape

- [ ] **Step 1: Define health message**

```json
{
  "type": "bridge_health",
  "project_id": "cifra",
  "bridge_pid": 123,
  "runtime_pid": 456,
  "runtime_healthy": true,
  "busy": false,
  "current_turn_id": "",
  "last_error": "",
  "vps_connected": true
}
```

- [ ] **Step 2: Add mobile command**

Handle:

```json
{"type": "health"}
```

Return `bridge_health` without touching runtime state.

- [ ] **Step 3: Add watchdog log rotation**

Rotate logs larger than 10 MB:

```python
def rotate_log(path: Path, max_bytes: int = 10 * 1024 * 1024) -> None:
    if path.exists() and path.stat().st_size > max_bytes:
        path.rename(path.with_suffix(path.suffix + ".1"))
```

- [ ] **Step 4: Add README operator commands**

Document:

```powershell
Get-ScheduledTask BridgeLauncherAtLogon
Get-Process deepseek-tui
Invoke-RestMethod http://127.0.0.1:7879/health
```

- [ ] **Step 5: Commit**

```powershell
git add project_bridge.py bridge_launcher.py tunnel_server.py README.md
git commit -m "feat: add bridge health diagnostics"
```

---

## Acceptance Criteria

- Phone can press stop during a hung prompt and the UI becomes usable again within 5 seconds.
- New session works without requiring runtime HTTP server to respond.
- Opening one project never restarts all other project sessions.
- VPS outage does not kill local `project_bridge.py`; it only reconnects.
- GitHub/VPS command failure inside DeepSeek produces an error item for that turn, not a dead bridge.
- No repeated `Failed to bind 127.0.0.1:7879` spam under normal operation.
- No repeated full project registration loop every 2-3 seconds after stable startup.
- `python -m pytest tests\test_bridge_launcher.py tests\test_tunnel_server_launcher.py tests\test_project_bridge_upload.py tests\test_project_bridge_file_listing.py -q` passes.
- GitHub mobile workflow passes when mobile files are touched.

---

## Execution Order

1. Task 1: idempotent launcher start.
2. Task 2: VPS no longer triggers full restarts on mobile attach.
3. Task 3: runtime turn timeout.
4. Task 4: nonblocking stop/new session.
5. Task 5: isolate runtime failures.
6. Task 6: mobile recovery controls.
7. Task 7: health diagnostics.

Do not start with mobile UI. The root reliability bug is on PC/VPS process boundaries.
