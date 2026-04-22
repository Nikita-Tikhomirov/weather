# Telegram Routing And Fast Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Telegram task notifications reliable and profile-scoped (personal private, family shared), remove backend push delivery path, and speed up desktop/mobile sync feedback.

**Architecture:** Keep current sync transport (`/sync/push`, `/sync/changes`, `/sync/pull`) but switch notification delivery to Telegram outbox processing on every write request. Unify personal visibility to owner-only in backend and local notifier, while family remains visible to all four profiles. Reduce polling intervals on desktop/mobile to improve perceived realtime behavior.

**Tech Stack:** PHP backend, Python desktop runtime, Flutter desktop/mobile client, unittest.

---

### Task 1: Backend notification routing and immediate Telegram delivery

**Files:**
- Modify: `backend_api/public/index.php`
- Modify: `backend_api/src/auth.php`

- [ ] Update routing contract in auth helpers: personal task recipients = owner only; family task recipients = all profiles.
- [ ] In `/sync/push`, call `process_outbox(...)` after applying events; return telegram processing status in response payload.
- [ ] Disable backend push outbox invocation from sync endpoints (`enqueue_push_notifications`, `process_push_outbox`) to leave Telegram-only messaging path.
- [ ] Preserve endpoint compatibility fields while adding `telegram` status and `push.disabled=true`.

### Task 2: Local desktop notifier visibility parity

**Files:**
- Modify: `notifier.py`

- [ ] Change local Telegram visibility helper for personal events to owner-only.
- [ ] Keep family fallback route for events without owner.
- [ ] Leave desktop toast behavior intact.

### Task 3: Faster sync cadence on desktop and mobile

**Files:**
- Modify: `desktop_app.py`
- Modify: `mobile_app/lib/main.dart`

- [ ] Reduce desktop delta poll interval (current 15s) to a lower value for faster updates.
- [ ] Keep full sync at 10 minutes as safety fallback.
- [ ] Reduce Flutter periodic delta interval (current 30s) to a lower value.
- [ ] Keep Flutter full sync interval at 10 minutes.

### Task 4: Tests and docs updates

**Files:**
- Modify: `tests/test_backend_push_routing_unittest.py`
- Modify: `tests/test_sync_stability_unittest.py`
- Modify: `backend_api/README.md`

- [ ] Update routing tests for new personal owner-only rule.
- [ ] Update stability assertions to match disabled backend push path and Telegram-first behavior.
- [ ] Document delivery contract and sync behavior in backend README.

### Task 5: Verification and release artifacts

**Files:**
- Modify: build artifacts only (no source change expected)

- [ ] Run `python -m unittest discover -s tests -p "*_unittest.py"`.
- [ ] Run Flutter analysis.
- [ ] Rebuild desktop EXE using `desktop_flutter_build.ps1`.
- [ ] Commit and push focused code changes.
