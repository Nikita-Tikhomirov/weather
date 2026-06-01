# Mobile App Debt Bugfix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** устранить критичный технический долг и баги Family Todo Mobile без большого rewrite.

**Architecture:** двигаться маленькими проверяемыми блоками: сначала безопасность deploy-контура, затем lifecycle-баги Flutter, затем стабильность тестов, затем analyzer debt и split крупных файлов. Существующие фасады, `part`-файлы и тесты сохраняются; новые границы вводятся только рядом с уже выделенными доменами.

**Tech Stack:** Flutter 3.x/Dart, Android/Kotlin, PowerShell deploy scripts, Python paramiko, Laravel/PHP backend на VPS Ubuntu 24.04.

---

## File Structure

- Modify: `deploy_vps.ps1` — убрать пароль из файла, читать VPS credentials из env/params, включить `-SkipMigration`.
- Modify: `deploy_backend_api.ps1` — убрать пароль из файла, читать VPS credentials и API key из env/params.
- Modify: `README.md` — описать безопасные deploy env vars и локальную команду тестов.
- Create: `docs/superpowers/specs/2026-06-01-mobile-app-debt-bugfix-design.md` — ТЗ и результаты анализа.
- Create: `docs/superpowers/plans/2026-06-01-mobile-app-debt-bugfix.md` — этот план работ.
- Future modify: `mobile_app/lib/features/home/home_page.dart` — исправить async context usage.
- Future modify: `mobile_app/lib/features/home/home_profile_init.dart` — исправить async context usage.
- Future modify: `mobile_app/lib/features/home/home_share_receiver.dart` — исправить async context usage.
- Future modify: `mobile_app/analysis_options.yaml` and Dart files — закрывать analyzer issues доменными пакетами.

---

### Task 1: Secure VPS Deploy Scripts

**Files:**
- Modify: `deploy_vps.ps1`
- Modify: `deploy_backend_api.ps1`
- Modify: `README.md`

- [x] **Step 1: Confirm leak locations**

Run:

```powershell
rg -n "literal VPS password|WEATHER_VPS_PASSWORD|dev-local-key" deploy_vps.ps1 deploy_backend_api.ps1
```

Expected before fix: a literal VPS password appears in both deploy scripts.

- [x] **Step 2: Remove hardcoded password from `deploy_vps.ps1`**

Implementation shape:

```powershell
param(
    [switch]$DryRun,
    [switch]$SkipMigration,
    [string]$HostIp = $(if ($env:WEATHER_VPS_HOST) { $env:WEATHER_VPS_HOST } else { "31.129.97.211" }),
    [string]$HostUser = $(if ($env:WEATHER_VPS_USER) { $env:WEATHER_VPS_USER } else { "root" }),
    [string]$HostPassword = $env:WEATHER_VPS_PASSWORD,
    [string]$RemoteBase = $(if ($env:WEATHER_VPS_REMOTE_BASE) { $env:WEATHER_VPS_REMOTE_BASE } else { "/var/www/adebechigef" })
)

if (-not $DryRun -and [string]::IsNullOrWhiteSpace($HostPassword)) {
    throw "Set WEATHER_VPS_PASSWORD or pass -HostPassword before deploying."
}
```

- [x] **Step 3: Pass credentials to Python via env**

Implementation shape:

```python
host = os.environ["WEATHER_VPS_HOST"]
user = os.environ["WEATHER_VPS_USER"]
password = os.environ["WEATHER_VPS_PASSWORD"]
remote_base = os.environ["WEATHER_VPS_REMOTE_BASE"]
```

- [x] **Step 4: Remove hardcoded password from `deploy_backend_api.ps1`**

Implementation shape:

```powershell
param(
    [switch]$DryRun,
    [string]$HostIp = $(if ($env:WEATHER_VPS_HOST) { $env:WEATHER_VPS_HOST } else { "31.129.97.211" }),
    [string]$HostUser = $(if ($env:WEATHER_VPS_USER) { $env:WEATHER_VPS_USER } else { "root" }),
    [string]$HostPassword = $env:WEATHER_VPS_PASSWORD,
    [string]$RemoteBase = $(if ($env:WEATHER_SIMPLE_API_REMOTE_BASE) { $env:WEATHER_SIMPLE_API_REMOTE_BASE } else { "/var/www/html" }),
    [string]$ApiKey = $(if ($env:TODO_BACKEND_API_KEY) { $env:TODO_BACKEND_API_KEY } else { "dev-local-key" })
)
```

- [x] **Step 5: Verify no tracked VPS password remains**

Run:

```powershell
rg -n "<redacted-old-vps-password>|literal VPS password" deploy_vps.ps1 deploy_backend_api.ps1 README.md docs mobile_app
```

Expected: no literal password value remains in tracked files.

- [x] **Step 6: Smoke deploy scripts in dry-run mode**

Run:

```powershell
.\deploy_vps.ps1 -DryRun
.\deploy_backend_api.ps1 -DryRun
```

Expected: both print planned uploads and do not require `WEATHER_VPS_PASSWORD`.

- [ ] **Step 7: Commit**

Run:

```powershell
git add deploy_vps.ps1 deploy_backend_api.ps1 README.md docs/superpowers/specs/2026-06-01-mobile-app-debt-bugfix-design.md docs/superpowers/plans/2026-06-01-mobile-app-debt-bugfix.md
git commit -m "fix: remove vps password from deploy scripts"
git push
```

---

### Task 2: Fix Async BuildContext Risks

**Files:**
- Modify: `mobile_app/lib/features/home/home_page.dart`
- Modify: `mobile_app/lib/features/home/home_profile_init.dart`
- Modify: `mobile_app/lib/features/home/home_share_receiver.dart`
- Test: relevant existing widget tests under `mobile_app/test/`

- [x] **Step 1: Locate analyzer issues**

Run:

```powershell
cd mobile_app
C:\Users\user\tools\flutter\bin\dart.bat analyze --format=machine . | Select-String "USE_BUILD_CONTEXT_SYNCHRONOUSLY"
```

Expected: 4 current locations.

- [x] **Step 2: Add mounted guards**

Pattern to apply after async gaps:

```dart
if (!mounted) {
  return;
}
```

For helper functions that receive `BuildContext`, use:

```dart
if (!context.mounted) {
  return;
}
```

- [x] **Step 3: Run targeted tests**

Run:

```powershell
cd mobile_app
C:\Users\user\tools\flutter\bin\flutter.bat test test\home_helpers_test.dart test\push_notification_test.dart --concurrency=1
```

Expected: all selected tests pass.

- [x] **Step 4: Run analyzer subset**

Run:

```powershell
cd mobile_app
C:\Users\user\tools\flutter\bin\dart.bat analyze --format=machine . | Select-String "USE_BUILD_CONTEXT_SYNCHRONOUSLY"
```

Expected: no output for this lint.

- [x] **Step 5: Commit**

Run:

```powershell
git add mobile_app/lib/features/home
git commit -m "fix: guard async home context usage"
git push
```

---

### Task 3: Stabilize Local Test Command

**Files:**
- Modify: `README.md`
- Modify: `mobile_app/README.md`

- [ ] **Step 1: Document the CI-equivalent command**

Add this command to mobile test instructions:

```powershell
cd C:\Users\user\Desktop\weather\mobile_app
C:\Users\user\tools\flutter\bin\flutter.bat test --concurrency=1
```

- [ ] **Step 2: Record the known parallel-run issue**

Document: full local `flutter test` without `--concurrency=1` can hit a transient suite-load failure while sqflite tests change the global factory.

- [ ] **Step 3: Verify**

Run:

```powershell
cd mobile_app
C:\Users\user\tools\flutter\bin\flutter.bat test --concurrency=1
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

Run:

```powershell
git add README.md mobile_app/README.md
git commit -m "docs: document stable mobile test command"
git push
```

---

### Task 4: Reduce Analyzer Debt

**Files:**
- Modify: Dart files reported by `flutter analyze`

- [x] **Step 1: Generate issue count**

Run:

```powershell
cd mobile_app
$out = C:\Users\user\tools\flutter\bin\dart.bat analyze --format=machine . 2>&1
$rows = $out | Where-Object { $_ -match '^INFO\|' }
$rows.Count
```

Expected before work: `359`.

- [x] **Step 2: Format Dart code**

Run:

```powershell
cd mobile_app
C:\Users\user\tools\flutter\bin\dart.bat format lib test
```

Expected: files are formatted and many trailing comma issues disappear.

- [x] **Step 3: Fix non-format lints by domain**

Order:

```text
1. USE_BUILD_CONTEXT_SYNCHRONOUSLY
2. UNNECESSARY_IMPORT
3. CURLY_BRACES_IN_FLOW_CONTROL_STRUCTURES
4. DANGLING_LIBRARY_DOC_COMMENTS
5. USE_SUPER_PARAMETERS
6. PREFER_CONST_* and UNNECESSARY_LAMBDAS
```

- [x] **Step 4: Verify**

Run:

```powershell
cd mobile_app
C:\Users\user\tools\flutter\bin\flutter.bat analyze
C:\Users\user\tools\flutter\bin\flutter.bat test --concurrency=1
```

Expected: analyzer issue count is lower; tests pass.

- [x] **Step 5: Commit**

Run:

```powershell
git add mobile_app/lib mobile_app/test
git commit -m "chore: reduce mobile analyzer debt"
git push
```

---

### Task 5: Move Production Defaults to Secrets

**Files:**
- Modify: `.github/workflows/mobile-apk.yml`
- Modify: `mobile_flutter_build.ps1`
- Modify: `mobile_app/android/app/src/main/kotlin/com/example/family_todo_mobile/PushPayloads.kt`
- Modify: `mobile_app/android/app/build.gradle`
- Modify: `mobile_app/lib/app/app_config.dart`

- [x] **Step 1: Make production secrets mandatory in CI release builds**

Expected workflow behavior:

```bash
test -n "${TODO_BACKEND_API_KEY:-}" || { echo "::error::TODO_BACKEND_API_KEY is required"; exit 1; }
test -n "${FIREBASE_API_KEY:-}" || { echo "::error::FIREBASE_API_KEY is required"; exit 1; }
```

- [x] **Step 2: Replace Kotlin constants with BuildConfig values**

Target shape:

```kotlin
const val PUSH_CHANNEL_ID = "family_updates"
val pushApiBaseUrl: String get() = BuildConfig.PUSH_API_BASE_URL
val pushApiKey: String get() = BuildConfig.PUSH_API_KEY
```

- [x] **Step 3: Add Gradle buildConfigFields**

Target shape:

```gradle
buildConfigField "String", "PUSH_API_BASE_URL", "\"${System.getenv("API_BASE_URL") ?: "http://31.129.97.211"}\""
buildConfigField "String", "PUSH_API_KEY", "\"${System.getenv("API_KEY") ?: "dev-local-key"}\""
```

- [x] **Step 4: Verify**

Run:

```powershell
cd mobile_app
C:\Users\user\tools\flutter\bin\flutter.bat test --concurrency=1
```

Expected: all tests pass.

---

### Task 6: Split Large Files Safely

**Files:**
- Modify: `mobile_app/lib/features/home/home_page.dart`
- Modify/create: files under `mobile_app/lib/features/home/`
- Modify: `mobile_app/lib/services/local_db.dart`
- Modify/create: files under `mobile_app/lib/services/`

- [ ] **Step 1: Split only one domain at a time**

First target: move remaining chat/project-only methods from `home_page.dart` into existing `home_chat_section.dart` and `projects_data.dart`.

- [ ] **Step 2: Run focused tests after each move**

Run:

```powershell
cd mobile_app
C:\Users\user\tools\flutter\bin\flutter.bat test test\home_helpers_test.dart test\push_notification_test.dart test\workspace_views_test.dart --concurrency=1
```

- [ ] **Step 3: Commit each successful split**

Run:

```powershell
git add mobile_app/lib/features/home mobile_app/test
git commit -m "refactor: split home chat responsibilities"
git push
```
