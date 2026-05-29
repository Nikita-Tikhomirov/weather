# CodeWhale Workspaces Mobile Design

## Goal

Replace project chats with Russian-language workspaces backed only by CodeWhale. The mobile app must let the user create or connect local desktop folders, create chat-like sessions inside each workspace, watch sessions live, reopen them later, and reliably stop or kill a stuck session without breaking other sessions or workspaces.

## Decisions

- The old `deepseek-tui` bridge is not the target runtime. New bridge work uses `codewhale` only.
- UI language is Russian.
- User-facing name is **Рабочие пространства**. A workspace maps to a local folder on the Windows desktop.
- A workspace can be created as a new desktop folder or connected to an existing desktop folder.
- Sessions are visible as chat rows inside a workspace. A session can be opened while running or after completion.
- Chat screens stay clean. Session controls, modes, skills, tools, diagnostics, and recovery actions live in a separate **Управление сессией** screen.
- Stability takes priority over resource usage. Active sessions run as isolated workers, so one stuck session can be killed without killing other sessions.

## CodeWhale Facts Used

CodeWhale v0.8.47 is installed on the PC. The official README documents `codewhale`, `codewhale-tui`, `codewhale serve --http`, `codewhale exec`, `codewhale sessions`, `codewhale resume`, `codewhale fork`, MCP, skills, sub-agents, and `/restore`/`revert_turn`. The architecture doc states that the runtime API exposes durable threads, turns, items, replayable event timelines, interrupt/steer operations for active turns, background tasks, MCP, skills, and a local-first HTTP/SSE API.

## Architecture

```text
Mobile app
  |
  | JSON lines over VPS relay
  v
VPS tunnel_server.py
  |
  | JSON lines to PC
  v
PC codewhale_bridge.py
  |
  +-- WorkspaceRegistry
  +-- SessionRegistry
  +-- CodeWhaleWorker per active session
  +-- EventLog per session
  +-- Health/diagnostics endpoints
```

The VPS relay stays intentionally dumb. It forwards messages between mobile and the PC bridge. It must not know how CodeWhale sessions work and must not restart PC workers by itself.

The PC bridge owns all workspace/session state. It stores metadata in:

```text
<repo>/.codewhale_bridge/
  workspaces.json
  sessions/
    <workspace_id>/
      <session_id>.json
      <session_id>.jsonl
      <session_id>.worker.log
      <session_id>.worker.err.log
```

Each active session gets its own worker process. The preferred worker is `codewhale serve --http` bound to a unique localhost port, one port per active session. If CodeWhale's runtime API cannot safely support one server per session on Windows, the bridge falls back to `codewhale exec --output-format stream-json` per turn, still isolated by process and workspace.

## Workspace Model

```json
{
  "id": "weather",
  "name": "Погода",
  "path": "C:\\Users\\user\\Desktop\\weather",
  "status": "available",
  "created_at": 1779990000,
  "updated_at": 1779990000
}
```

Workspace statuses:

- `available`: folder exists and bridge can access it.
- `missing`: folder path no longer exists.
- `starting`: bridge is starting or reconnecting worker infrastructure.
- `error`: workspace metadata or folder access failed.

Workspace commands:

- `workspace_list`
- `workspace_create`
- `workspace_attach`
- `workspace_rename`
- `workspace_remove`
- `workspace_health`

`workspace_create` only creates folders under `C:\Users\user\Desktop` unless later explicitly expanded. `workspace_attach` only accepts folders under `C:\Users\user\Desktop` for the first version.

## Session Model

```json
{
  "id": "20260529_153000_ab12cd34",
  "workspace_id": "weather",
  "title": "Новая сессия",
  "status": "ready",
  "mode": "agent",
  "worker_pid": 1234,
  "port": 7921,
  "codewhale_thread_id": "",
  "created_at": 1779990000,
  "updated_at": 1779990000,
  "last_error": ""
}
```

Session statuses:

- `ready`: session exists and can accept a prompt.
- `running`: a turn is active.
- `stopping`: soft stop requested.
- `stopped`: no active worker; history remains readable.
- `hung`: timeout or failed health probe.
- `killing`: hard kill in progress.
- `error`: worker or CodeWhale runtime failed.

Session commands:

- `session_list`
- `session_create`
- `session_open`
- `session_send`
- `session_stop`
- `session_kill`
- `session_restart_worker`
- `session_delete`
- `session_health`
- `session_update_settings`

`session_create` must always work if the workspace folder exists, even if another session in that workspace is hung. It creates metadata and an empty event log before starting a worker.

## Worker Lifecycle

Each active session owns:

- process PID;
- process tree kill handle on Windows;
- localhost port;
- session event log;
- stdout/stderr log files;
- health state;
- last-seen event sequence.

Soft stop:

1. If the worker runtime API exposes active turn interrupt, call it with a short timeout.
2. Mark the session `stopping`.
3. If the worker does not confirm stopped within the timeout, mark `hung`.

Hard kill:

1. Kill the process tree for the session worker only.
2. Mark session `stopped` or `error`.
3. Keep event history readable.
4. Do not touch other session workers.

New session:

1. Create session metadata and event log immediately.
2. Return it to mobile immediately.
3. Start worker in background.
4. Update status through events.

## Mobile UI

Bottom navigation keeps **Мессенджер** separate from **Рабочие пространства**.

Workspace list screen:

- `+` create workspace.
- folder icon attach existing desktop folder.
- row shows name, path, status, last activity.

Workspace detail screen:

- header with workspace name/path/status.
- tabs: `Сессии`, `Файлы`, `Настройки`.
- `Сессии` shows chat-like rows with status chips.

Session chat screen:

- message stream.
- input.
- small status indicator.
- no dense toolbar.

Session management screen:

- status, PID, port, current mode, current turn, last error.
- mode selector: `План`, `Агент`, `Авто`, `YOLO`.
- skills/functions list when bridge can read them from CodeWhale config.
- MCP/tools list when available.
- actions:
  - `Остановить ход`;
  - `Жестко убить сессию`;
  - `Перезапустить worker`;
  - `Новая сессия`;
  - `Открыть логи`;
  - `Диагностика`.

## Error Handling

- VPS outage: mobile shows `Нет связи с мостом`, PC workers continue running.
- PC bridge restart: mobile reconnects and reloads workspace/session lists.
- CodeWhale worker hang: only that session becomes `hung`; other sessions stay usable.
- GitHub/VPS/tool command failure inside CodeWhale: displayed as a turn error item, not as bridge failure.
- Mobile disconnect: worker continues unless user explicitly stops/kills the session.

## Migration

Existing project chat code remains during the first implementation phase but is no longer the product target. New CodeWhale files use new names:

- `codewhale_bridge.py`
- `codewhale_launcher.py`
- `start_codewhale_bridge.ps1`
- `install_codewhale_bridge_task.ps1`
- `mobile_app/lib/features/workspaces/...`
- `mobile_app/lib/services/codewhale_bridge_service.dart`

After CodeWhale workspaces pass acceptance tests, old `project_bridge.py` and `ProjectBridgeService` can be retired in a separate cleanup.

## Testing

Python:

- workspace create/attach/list validation;
- session create/list/open metadata;
- soft stop timeout;
- hard kill only kills target worker;
- event replay after bridge restart;
- VPS reconnect does not kill workers.

Flutter:

- workspace list renders statuses;
- session list renders running/hung/stopped states;
- chat opens existing session history;
- management screen sends stop/kill/restart/new-session commands;
- empty or error events do not create blank bubbles.

Integration:

- start two sessions in one workspace;
- hang one fake worker;
- hard kill it;
- verify the second remains running;
- create a third session while the first is hung.

## Acceptance Criteria

- User can create a workspace folder on the desktop from mobile.
- User can attach an existing desktop folder as a workspace.
- User can create multiple sessions inside a workspace.
- User can open a running session and see live output.
- User can open an old session and read history.
- User can soft stop a running turn.
- User can hard kill a hung session without killing other sessions.
- User can create a new session even while an old one is hung.
- Chat UI stays clean; detailed controls live on a separate management screen.
- No DeepSeek TUI fallback remains in the new workspace path.
