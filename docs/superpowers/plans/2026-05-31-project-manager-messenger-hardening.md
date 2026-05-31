# Project Manager Messenger Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize project selection, chat media/scroll behavior, call controls, and family-group chat synchronization.

**Architecture:** Keep changes scoped to existing Flutter state/services/widgets and Laravel repositories/controllers. Add small seams for persistence and media state instead of rewriting screens.

**Tech Stack:** Flutter/Dart, sqflite, shared_preferences, flutter_webrtc, video_player, Laravel/PHPUnit.

---

### Task 1: Last Project Persistence

**Files:**
- Create: `mobile_app/lib/services/project_selection_storage.dart`
- Modify: `mobile_app/lib/state/task_store.dart`
- Test: `mobile_app/test/task_store_test.dart`

- [x] Add an injectable storage service with `readLastProjectId`, `saveLastProjectId`, and `clearLastProjectId`.
- [x] Write tests proving `TaskStore.initialize()` restores a valid saved project and falls back from a stale one.
- [x] Implement store restore/save logic after projects load.
- [x] Run `flutter test test/task_store_test.dart`.

### Task 1b: Last Workspace Persistence

**Files:**
- Create: `mobile_app/lib/features/workspaces/workspace_restore_policy.dart`
- Modify: `mobile_app/lib/features/workspaces/codewhale_workspaces_page.dart`
- Test: `mobile_app/test/workspace_restore_policy_test.dart`

- [x] Persist the last opened workspace and session in shared preferences.
- [x] Restore the workspace after the workspace list arrives.
- [x] Restore the session after the restored workspace's session list arrives.
- [x] Add pure policy tests for restore selection.

### Task 2: Chat Scroll and Video Preview Lifecycle

**Files:**
- Modify: `mobile_app/lib/features/chat/chat_messages_list.dart`
- Modify: `mobile_app/lib/features/chat/chat_media_bubble.dart`
- Test: `mobile_app/test/chat_messages_list_test.dart`

- [x] Extract scroll policy into testable functions.
- [x] Write tests for user near bottom, own outgoing message, and older-message prepend.
- [x] Replace repeated delayed animated bottom scroll with stable initial jump and guarded auto-scroll.
- [x] Stop video thumbnails from audible playback and dispose controllers on async cancellation.
- [x] Run `flutter test test/chat_scroll_policy_test.dart`.

### Task 3: Calls UX

**Files:**
- Modify: `mobile_app/lib/services/call_service.dart`
- Modify: `mobile_app/lib/features/chat/call_screen.dart`
- Test: `mobile_app/test/call_service_config_test.dart`

- [x] Publish local media stream from `CallService`.
- [x] Add helper route method for headset/Bluetooth preference.
- [x] Render draggable local preview in video calls within safe bounds above call buttons.
- [x] Add headset/Bluetooth control button.
- [x] Run `flutter analyze`.

### Task 4: Family Groups Create Group Chats

**Files:**
- Modify: `laravel_backend_vps/app/Domain/Chat/ChatRepository.php`
- Modify: `laravel_backend_vps/app/Http/Controllers/ProjectGroupController.php`
- Test: `laravel_backend_vps/tests/Feature/ProjectGroupChatSyncTest.php`

- [x] Write a Feature test proving family-group create creates `grp:family:<id>` and appears in chat bootstrap.
- [x] Write a Feature test proving group update adds the new member to the chat.
- [x] Add a Feature test proving member-only updates keep the chat title.
- [x] Implement `syncFamilyGroupConversation()`.
- [x] Call sync from create/update group endpoints.
- [ ] Run `php artisan test --filter=ProjectGroupChatSyncTest`.

### Task 5: Full Verification and Publish

**Files:**
- All changed files

- [x] Run relevant Flutter tests.
- [ ] Run Laravel feature tests. Blocked locally: `php` is not installed in this environment.
- [x] Run `flutter analyze`.
- [ ] Commit with `fix: harden project manager and messenger`.
- [ ] Push `master`.
