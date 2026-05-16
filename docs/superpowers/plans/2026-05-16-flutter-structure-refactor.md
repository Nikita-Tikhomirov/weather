# Flutter Structure Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the oversized Flutter `main.dart` into focused app, feature, and shared modules without changing runtime behavior.

**Architecture:** Keep existing services, models, repositories, domain, and state APIs stable. Move app-level constants/theme into `lib/app`, independent UI widgets into `lib/features/*`, and leave the state-heavy `HomePage` wiring in `main.dart` until the UI extraction is stable.

**Tech Stack:** Flutter, Dart 3, existing `flutter_lints`, existing unit tests.

---

### Task 1: App Theme And Labels

**Files:**
- Create: `mobile_app/lib/app/app_labels.dart`
- Create: `mobile_app/lib/app/app_theme.dart`
- Modify: `mobile_app/lib/main.dart`

- [ ] Move profile/workflow labels and theme option definitions out of `main.dart`.
- [ ] Import the new app modules from `main.dart`.
- [ ] Keep public names stable where widgets depend on them.
- [ ] Run `dart format mobile_app/lib`.
- [ ] Run `flutter analyze` from `mobile_app`.

### Task 2: Independent Task UI

**Files:**
- Create: `mobile_app/lib/features/tasks/dashboard_view.dart`
- Create: `mobile_app/lib/features/tasks/calendar_view.dart`
- Create: `mobile_app/lib/features/tasks/tasks_board.dart`
- Create: `mobile_app/lib/features/tasks/task_card.dart`
- Modify: `mobile_app/lib/main.dart`

- [ ] Move independent task/dashboard/calendar/card widgets out of `main.dart`.
- [ ] Keep constructor signatures unchanged so `HomePage` callers stay mechanical.
- [ ] Run `dart format mobile_app/lib`.
- [ ] Run `flutter analyze` from `mobile_app`.

### Task 3: Family And Project File UI

**Files:**
- Create: `mobile_app/lib/features/family/family_view.dart`
- Create: `mobile_app/lib/features/projects/project_file_browser.dart`
- Modify: `mobile_app/lib/main.dart`

- [ ] Move family view and project file browser widgets out of `main.dart`.
- [ ] Keep file click/link callbacks unchanged.
- [ ] Run `dart format mobile_app/lib`.
- [ ] Run `flutter analyze` from `mobile_app`.

### Task 4: Chat UI Extraction

**Files:**
- Create: `mobile_app/lib/features/chat/chat_messages_list.dart`
- Create: `mobile_app/lib/features/chat/chat_message_bubble.dart`
- Modify: `mobile_app/lib/main.dart`

- [ ] Move chat message list and chat bubble widgets out of `main.dart`.
- [ ] Keep callbacks and rendering behavior unchanged.
- [ ] Run `dart format mobile_app/lib`.
- [ ] Run `flutter test` from `mobile_app`.
