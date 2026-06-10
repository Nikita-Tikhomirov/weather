# Mobile App Debt Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** stabilize local verification for `mobile_app` and document the next safe debt-reduction steps.

**Architecture:** keep production Flutter behavior unchanged in this phase. Add a small PowerShell verification wrapper around the existing Flutter SDK, update docs to use it, and record the current root-cause evidence for the native test runner crash.

**Tech Stack:** Flutter 3.41.7, Dart 3.11.5, PowerShell, Windows Event Log, existing Flutter tests.

---

## File Structure

- Create: `mobile_app/tool/run_flutter_checks.ps1` — sequential mobile verification wrapper with optional suite-by-suite fallback.
- Modify: `README.md` — root project mobile verification command.
- Modify: `mobile_app/README.md` — mobile-local verification guidance and fallback.
- Create: `docs/superpowers/specs/2026-06-10-mobile-app-debt-stability-design.md` — current technical debt spec.
- Create: `docs/superpowers/plans/2026-06-10-mobile-app-debt-stability.md` — this implementation plan.

## Tasks

### Task 1: Capture Current Baseline

- [x] Run preflight: `powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\user\.codex\scripts\local-first-preflight.ps1`.
- [x] Confirm working Flutter SDK: `C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat --version`.
- [x] Run analyzer: `C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat analyze`.
- [x] Run format check: `C:\Users\user\.puro\envs\stable\flutter\bin\dart.bat format --set-exit-if-changed lib test`.
- [x] Run full tests: `C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat test --concurrency=1`.
- [x] Inspect Windows Event Log for `flutter_tester.exe` crashes.

### Task 2: Add Sequential Verification Runner

- [x] Create `mobile_app/tool/run_flutter_checks.ps1`.
- [x] Default to `FLUTTER_BIN` when set, otherwise Puro stable Flutter.
- [x] Run `flutter analyze` unless `-SkipAnalyze` is passed.
- [x] Run `flutter test --concurrency=1` unless `-SkipTests` is passed.
- [x] Add `-SuiteBySuite` mode for local infrastructure fallback.
- [x] Add `-TestPattern` for narrow suite-by-suite checks.
- [x] Retry only infrastructure failures: `Connection closed before test suite loaded`, `0xc0000005`, or process exit `-1073741819`.
- [x] Fail immediately on compile errors or assertion failures.

### Task 3: Update Documentation

- [x] Update root `README.md` mobile verification command.
- [x] Update `mobile_app/README.md` with `FLUTTER_BIN`, runner usage, and suite-by-suite fallback.
- [x] Explain that suite-by-suite mode is not a replacement for fixing real test failures.

### Task 4: Verify and Publish

- [x] Run `.\tool\run_flutter_checks.ps1 -SkipTests`.
- [x] Run targeted representative tests:

```powershell
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test test\agent_launch_plan_test.dart test\chat_api_client_upload_test.dart --concurrency=1
```

- [x] Run `git diff --check`.
- [ ] Commit with `fix: stabilize mobile verification workflow`.
- [ ] Push `master`.
- [ ] Check GitHub Actions status after push.

## Deferred Follow-Up

- Split `task_editor_sheet.dart` only after adding behavior-focused tests around agent launch, comments, attachments, and autosave.
- Replace `invalid_use_of_protected_member` home extensions with smaller widgets/services in separate PR-sized tasks.
- Isolate sqflite tests from global `databaseFactory` mutation before trying to restore parallel local test execution.
