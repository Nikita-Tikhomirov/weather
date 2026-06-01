# Project Task Collaboration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a full-screen, tabbed project task editor with Trello-like collaboration tools.

**Architecture:** Add a structured task collaboration model, persist it through existing task JSON/SQLite/sync paths, then replace the bottom sheet editor with a full-screen route. Keep callers using `showTaskEditorSheet` for compatibility.

**Tech Stack:** Flutter/Dart, sqflite, image_picker, file_picker, PHP sync backend, Laravel sync backend, flutter_test.

---

### Task 1: Collaboration Data Contract

**Files:**
- Create: `mobile_app/lib/models/task_collaboration.dart`
- Modify: `mobile_app/lib/models/task_item.dart`
- Modify: `mobile_app/lib/services/local_db.dart`
- Modify: `mobile_app/lib/services/sync_service.dart`
- Test: `mobile_app/test/task_item_test.dart`
- Test: `mobile_app/test/sync_service_test.dart`

- [ ] Add immutable model classes for comments, attachments, checklist items, checklists, activity entries, and the aggregate `TaskCollaboration`.
- [ ] Add `collaboration` to `TaskItem` JSON, DB rows, copyWith, equality, and hash code.
- [ ] Add SQLite `collaboration_json` column in DB version 11 and migration path.
- [ ] Include collaboration in family task upsert payloads.
- [ ] Add tests that JSON/DB round-trip preserves comments, attachments, and checklists.
- [ ] Add sync test proving family task pending payload includes collaboration.

### Task 2: Backend Sync Pass-Through

**Files:**
- Modify: `backend_api/sql/schema.sql`
- Modify: `backend_api/src/repository.php`
- Create: `laravel_backend_vps/database/migrations/2026_06_01_000900_add_task_collaboration_json.php`
- Modify: `laravel_backend_vps/app/Domain/Sync/SyncRepository.php`

- [ ] Add `collaboration_json` columns for personal and family tasks.
- [ ] Normalize incoming collaboration payloads as JSON-safe objects.
- [ ] Store collaboration on upsert for both task tables.
- [ ] Return collaboration from all changed task query paths.

### Task 3: Full-Screen Editor Shell

**Files:**
- Modify: `mobile_app/lib/features/tasks/task_editor_sheet.dart`
- Test: `mobile_app/test/task_editor_sheet_test.dart`

- [ ] Keep `showTaskEditorSheet` API but navigate to a new full-screen `TaskEditorScreen`.
- [ ] Add `AppBar`, save action, `DefaultTabController`, and two tabs.
- [ ] Move existing settings controls into the first tab without changing save behavior.
- [ ] Move the description field to the second tab.
- [ ] Update widget tests to assert route, tabs, and moved description.

### Task 4: Collaboration UI

**Files:**
- Modify: `mobile_app/lib/features/tasks/task_editor_sheet.dart`
- Modify: `mobile_app/lib/features/tasks/task_card.dart`
- Test: `mobile_app/test/task_editor_sheet_test.dart`
- Test: `mobile_app/test/tasks_board_test.dart`

- [ ] Add chat-like comment composer.
- [ ] Add photo picker and file picker actions with staged attachment chips.
- [ ] Add image preview cards and full-screen viewer.
- [ ] Add file attachment rows with captions.
- [ ] Add checklist creation, item adding, item toggling, and progress display.
- [ ] Add compact card indicators for comments, attachments, and checklist progress.

### Task 5: Verification And Publish

**Commands:**
- `cd mobile_app; flutter test test/task_item_test.dart test/sync_service_test.dart test/task_editor_sheet_test.dart`
- `cd mobile_app; flutter test`
- `python -m pytest -q`
- `git add -A`
- `git commit -m "feat: add project task collaboration screen"`
- `git push`

- [ ] Run targeted Flutter tests first.
- [ ] Run full Flutter tests if targeted tests pass.
- [ ] Run Python tests if environment allows.
- [ ] Commit and push.
- [ ] Check GitHub Actions status and fix failures if any.
