# Mobile Technical Debt Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use a task-by-task execution workflow. Track steps with checkbox syntax. Do not batch unrelated files into one large commit.

**Goal:** Continue removing mobile-app technical debt, starting with remaining hardcoded Russian user-facing UI strings and adding regression tests for every changed slice.

**Architecture:** Keep the existing Flutter architecture. Add localized strings to ARB files, regenerate Flutter l10n, and wire widgets through `AppLocalizations.of(context)` with Russian fallback strings. Avoid broad rewrites until localization debt is substantially reduced.

**Tech Stack:** Flutter, Dart, `flutter_test`, Flutter l10n ARB, Puro-managed Flutter SDK, GitHub Actions.

---

## Global Preconditions

- [ ] Open `C:\Users\user\Desktop\weather\AGENTS.md` and follow it.
- [ ] Open `C:\Users\user\Desktop\weather\DEEPSEEK_TECH_DEBT_SPEC.md` and follow it.
- [ ] Do not use local LLM/Ollama.
- [ ] Stop `ollama` if it is running.
- [ ] Work on `master`.
- [ ] Use TDD for every behavior/UI change.
- [ ] Commit and push after every logical slice.
- [ ] Check GitHub Actions after every push.

Commands:

```powershell
cd C:\Users\user\Desktop\weather
git status --short
git rev-parse --short HEAD
Get-Process | Where-Object { $_.ProcessName -like '*ollama*' } |
  Stop-Process -Force
```

Expected:

```text
git status --short
```

prints nothing before starting a slice, except for files intentionally created by the current task.

---

## Task 0: Rebuild Current Cyrillic Inventory

**Files:**

- Read: `mobile_app/lib/**/*.dart`
- Do not modify files in this task.

- [ ] **Step 1: Generate current Cyrillic count by file**

Run:

```powershell
cd C:\Users\user\Desktop\weather
$files = Get-ChildItem -Path mobile_app\lib -Recurse -Include *.dart |
  Where-Object { $_.FullName -notmatch '\\l10n\\app_localizations' }
$rows = foreach ($file in $files) {
  $matches = Select-String -Path $file.FullName -Pattern '[А-Яа-яЁё]' -AllMatches
  if ($matches) {
    [PSCustomObject]@{
      File = $file.FullName.Substring((Get-Location).Path.Length + 1)
      Lines = ($matches | Select-Object -ExpandProperty LineNumber -Unique).Count
    }
  }
}
$rows | Sort-Object Lines -Descending | Select-Object -First 40 | Format-Table -AutoSize
```

Expected:

```text
task_editor_sheet.dart is near the top.
home_page.dart, projects_and_groups_screen.dart, workspaces, agent files are visible.
```

- [ ] **Step 2: Pick exactly one next slice**

Pick one of these first:

```text
Task 1: task_editor_sheet comments/checklists visible labels
Task 2: task_editor_sheet agent panel visible labels
Task 3: home_page visible labels
Task 4: projects_and_groups_screen visible labels
Task 5: workspaces visible labels
```

Do not start with prompts, logs, stored activity text, or backend error matching.

---

## Task 1: Localize Task Editor Comments And Checklists UI

**Files:**

- Modify: `mobile_app/lib/features/tasks/task_editor_sheet.dart`
- Modify: `mobile_app/lib/l10n/app_en.arb`
- Modify: `mobile_app/lib/l10n/app_ru.arb`
- Generated: `mobile_app/lib/l10n/app_localizations.dart`
- Generated: `mobile_app/lib/l10n/app_localizations_en.dart`
- Generated: `mobile_app/lib/l10n/app_localizations_ru.dart`
- Test: `mobile_app/test/task_editor_sheet_test.dart`

Target visible strings:

```text
Комментарии
Комментариев нет
Чеклисты
Новый чеклист
Добавить чеклист
Чеклистов нет
Удалить чеклист
Удалить пункт
Редактировать пункт
Текст пункта
Удалить пункт?
Пункт будет удалён из чеклиста.
```

Suggested English keys:

```json
"taskComments": "Comments",
"taskNoComments": "No comments",
"taskChecklists": "Checklists",
"taskNewChecklist": "New checklist",
"taskAddChecklist": "Add checklist",
"taskNoChecklists": "No checklists",
"taskDeleteChecklist": "Delete checklist",
"taskDeleteChecklistItem": "Delete item",
"taskEditChecklistItem": "Edit item",
"taskChecklistItemText": "Item text",
"taskDeleteChecklistItemTitle": "Delete item?",
"taskDeleteChecklistItemMessage": "The item will be removed from the checklist."
```

Suggested Russian keys:

```json
"taskComments": "Комментарии",
"taskNoComments": "Комментариев нет",
"taskChecklists": "Чеклисты",
"taskNewChecklist": "Новый чеклист",
"taskAddChecklist": "Добавить чеклист",
"taskNoChecklists": "Чеклистов нет",
"taskDeleteChecklist": "Удалить чеклист",
"taskDeleteChecklistItem": "Удалить пункт",
"taskEditChecklistItem": "Редактировать пункт",
"taskChecklistItemText": "Текст пункта",
"taskDeleteChecklistItemTitle": "Удалить пункт?",
"taskDeleteChecklistItemMessage": "Пункт будет удалён из чеклиста."
```

- [ ] **Step 1: Find existing test helpers**

Run:

```powershell
cd C:\Users\user\Desktop\weather\mobile_app
Select-String -Path test\task_editor_sheet_test.dart -Pattern 'pump','TaskEditor','Checklist','Комментарии','Чеклисты' -CaseSensitive:$false
```

Use the existing test construction style. Do not create a second unrelated harness if a helper already exists.

- [ ] **Step 2: Add RED widget test**

Add a test named:

```text
uses localized comments and checklist labels
```

The test must:

1. Pump `TaskEditorSheet` or the existing test wrapper with `locale: const Locale('en')`.
2. Navigate/open the area where comments and checklists are visible.
3. Assert English labels are visible.
4. Assert Russian labels are not visible.

Minimum assertions:

```dart
expect(find.text('Comments'), findsOneWidget);
expect(find.text('Checklists'), findsOneWidget);
expect(find.text('New checklist'), findsOneWidget);
expect(find.byTooltip('Add checklist'), findsOneWidget);
expect(find.text('Комментарии'), findsNothing);
expect(find.text('Чеклисты'), findsNothing);
expect(find.text('Новый чеклист'), findsNothing);
```

- [ ] **Step 3: Run RED**

Run:

```powershell
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test --no-pub test\task_editor_sheet_test.dart --plain-name "uses localized comments and checklist labels"
```

Expected:

```text
FAIL because English labels are not found.
```

- [ ] **Step 4: Add ARB keys**

Modify:

```text
mobile_app/lib/l10n/app_en.arb
mobile_app/lib/l10n/app_ru.arb
```

Add the keys listed above. Keep nearby task/checklist keys grouped together.

- [ ] **Step 5: Generate l10n**

Run:

```powershell
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' gen-l10n
```

If this crashes with empty output or `-1073741819`, run it once more.

- [ ] **Step 6: Wire `task_editor_sheet.dart`**

At each build method that renders those labels:

```dart
final l10n = AppLocalizations.of(context);
```

Replace:

```dart
Text('Комментарии')
```

with:

```dart
Text(l10n?.taskComments ?? 'Комментарии')
```

Replace:

```dart
const InputDecoration(labelText: 'Новый чеклист')
```

with non-const:

```dart
InputDecoration(labelText: l10n?.taskNewChecklist ?? 'Новый чеклист')
```

Replace:

```dart
tooltip: 'Добавить чеклист'
```

with:

```dart
tooltip: l10n?.taskAddChecklist ?? 'Добавить чеклист'
```

- [ ] **Step 7: Format**

Run:

```powershell
& 'C:\Users\user\.puro\envs\stable\flutter\bin\dart.bat' format lib\features\tasks\task_editor_sheet.dart test\task_editor_sheet_test.dart lib\l10n\app_localizations.dart lib\l10n\app_localizations_en.dart lib\l10n\app_localizations_ru.dart
```

- [ ] **Step 8: Run GREEN**

Run:

```powershell
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test --no-pub test\task_editor_sheet_test.dart --plain-name "uses localized comments and checklist labels"
```

Expected:

```text
All tests passed!
```

- [ ] **Step 9: Run broader targeted test**

Run:

```powershell
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test --no-pub test\task_editor_sheet_test.dart
```

If this file is too slow or flaky, rerun the specific group around comments/checklists plus analyzer, and record the limitation in the final report.

- [ ] **Step 10: Run analyzer**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run_flutter_checks.ps1 -SkipTests -Retries 1
```

Expected:

```text
No issues found!
```

- [ ] **Step 11: Commit and push**

Run:

```powershell
cd C:\Users\user\Desktop\weather
git diff --check
git -c core.fsmonitor=false add -- mobile_app/lib/features/tasks/task_editor_sheet.dart mobile_app/lib/l10n/app_en.arb mobile_app/lib/l10n/app_ru.arb mobile_app/lib/l10n/app_localizations.dart mobile_app/lib/l10n/app_localizations_en.dart mobile_app/lib/l10n/app_localizations_ru.dart mobile_app/test/task_editor_sheet_test.dart
git commit -m "fix: localize task editor checklist labels"
git push
```

- [ ] **Step 12: Check GitHub Actions**

Use the CI polling script from `DEEPSEEK_TECH_DEBT_SPEC.md`.

Expected:

```text
Tests completed success
Mobile APK Build completed success
```

---

## Task 2: Localize Task Editor Agent Panel UI

**Files:**

- Modify: `mobile_app/lib/features/tasks/task_editor_sheet.dart`
- Modify: `mobile_app/lib/l10n/app_en.arb`
- Modify: `mobile_app/lib/l10n/app_ru.arb`
- Generated: `mobile_app/lib/l10n/app_localizations*.dart`
- Test: `mobile_app/test/task_editor_sheet_test.dart`

Target visible strings:

```text
Агент
Доступ есть
Нет доступа
Вопросы агента
Загружаю чаты
Подключить чат
Новый чат
Агентский чат
Чаты задачи
Агентские чаты не подключены
Очередь идет
```

Suggested keys:

```json
"taskAgent": "Agent",
"taskAgentAccessGranted": "Access granted",
"taskAgentNoAccess": "No access",
"taskAgentQuestions": "Agent questions",
"taskAgentLoadingChats": "Loading chats",
"taskAgentConnectChat": "Connect chat",
"taskAgentNewChat": "New chat",
"taskAgentChat": "Agent chat",
"taskAgentTaskChats": "Task chats",
"taskAgentNoChats": "No agent chats connected",
"taskAgentQueueRunning": "Queue running"
```

Russian:

```json
"taskAgent": "Агент",
"taskAgentAccessGranted": "Доступ есть",
"taskAgentNoAccess": "Нет доступа",
"taskAgentQuestions": "Вопросы агента",
"taskAgentLoadingChats": "Загружаю чаты",
"taskAgentConnectChat": "Подключить чат",
"taskAgentNewChat": "Новый чат",
"taskAgentChat": "Агентский чат",
"taskAgentTaskChats": "Чаты задачи",
"taskAgentNoChats": "Агентские чаты не подключены",
"taskAgentQueueRunning": "Очередь идет"
```

- [ ] **Step 1: Add RED test**

Test name:

```text
uses localized task agent panel labels
```

Minimum assertions:

```dart
expect(find.text('Agent'), findsOneWidget);
expect(find.text('Agent questions'), findsOneWidget);
expect(find.text('Connect chat'), findsOneWidget);
expect(find.text('New chat'), findsOneWidget);
expect(find.text('Task chats'), findsOneWidget);
expect(find.text('Агент'), findsNothing);
expect(find.text('Вопросы агента'), findsNothing);
```

- [ ] **Step 2: Run RED**

```powershell
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test --no-pub test\task_editor_sheet_test.dart --plain-name "uses localized task agent panel labels"
```

- [ ] **Step 3: Add keys, generate l10n, wire UI**

Use the same pattern as Task 1:

```dart
final l10n = AppLocalizations.of(context);
Text(l10n?.taskAgent ?? 'Агент')
```

Do not change agent prompt body strings in this task.

- [ ] **Step 4: Verify**

Run:

```powershell
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test --no-pub test\task_editor_sheet_test.dart --plain-name "uses localized task agent panel labels"
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run_flutter_checks.ps1 -SkipTests -Retries 1
```

- [ ] **Step 5: Commit**

```powershell
cd C:\Users\user\Desktop\weather
git diff --check
git -c core.fsmonitor=false add -- mobile_app/lib/features/tasks/task_editor_sheet.dart mobile_app/lib/l10n/app_en.arb mobile_app/lib/l10n/app_ru.arb mobile_app/lib/l10n/app_localizations.dart mobile_app/lib/l10n/app_localizations_en.dart mobile_app/lib/l10n/app_localizations_ru.dart mobile_app/test/task_editor_sheet_test.dart
git commit -m "fix: localize task editor agent labels"
git push
```

Check GitHub Actions.

---

## Task 3: Localize Task Editor Workspace And Launch Settings UI

**Files:**

- Modify: `mobile_app/lib/features/tasks/task_editor_sheet.dart`
- Modify: `mobile_app/lib/l10n/app_en.arb`
- Modify: `mobile_app/lib/l10n/app_ru.arb`
- Generated: `mobile_app/lib/l10n/app_localizations*.dart`
- Test: `mobile_app/test/task_editor_sheet_test.dart`

Target visible strings:

```text
Воркспейс
Не выбран
Список воркспейсов CodeWhale не загружен
Рабочее пространство
Обновить
Режим запуска
Авто
Ручной
Провайдер
Модель
Подтверждения
Авто-режим инструментов
Инструменты
Список инструментов загружается
Инструменты CodeWhale не загружены
Скиллы
Команды
Доступно: {count}
Очередь выполнения
Выберите инструменты; рабочий шаг пойдет последним
Выше
Ниже
Работа по задаче
Чеклисты, комментарии и файлы карточки обязательны
```

Reuse existing keys where present:

```text
workspaces
refreshWorkspaces
selectWorkspace
workspaceSettingLoading
```

Suggested new keys:

```json
"taskWorkspace": "Workspace",
"taskWorkspaceNotSelected": "Not selected",
"taskWorkspaceListNotLoaded": "CodeWhale workspace list is not loaded",
"taskLaunchMode": "Launch mode",
"taskLaunchAuto": "Auto",
"taskLaunchManual": "Manual",
"taskAgentProvider": "Provider",
"taskAgentModel": "Model",
"taskAgentConfirmations": "Confirmations",
"taskAgentToolAutoMode": "Tool auto mode",
"taskAgentTools": "Tools",
"taskAgentToolsLoading": "Tool list is loading",
"taskAgentToolsNotLoaded": "CodeWhale tools are not loaded",
"taskAgentSkills": "Skills",
"taskAgentCommands": "Commands",
"taskAgentAvailableCount": "Available: {count}",
"taskAgentQueue": "Execution queue",
"taskAgentQueueHint": "Select tools; the work step will run last",
"taskMoveUp": "Up",
"taskMoveDown": "Down",
"taskWorkStep": "Task work",
"taskWorkStepSubtitle": "Checklists, comments, and task files are required"
```

- [ ] **Step 1: Add RED test**

Test name:

```text
uses localized task workspace and launch settings labels
```

Minimum assertions:

```dart
expect(find.text('Workspace'), findsOneWidget);
expect(find.text('Launch mode'), findsOneWidget);
expect(find.text('Provider'), findsOneWidget);
expect(find.text('Model'), findsOneWidget);
expect(find.text('Tools'), findsOneWidget);
expect(find.text('Execution queue'), findsOneWidget);
expect(find.text('Воркспейс'), findsNothing);
expect(find.text('Режим запуска'), findsNothing);
```

- [ ] **Step 2: Run RED**

```powershell
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test --no-pub test\task_editor_sheet_test.dart --plain-name "uses localized task workspace and launch settings labels"
```

- [ ] **Step 3: Add keys and wire UI**

Use `AppLocalizations.of(context)`.
Remove `const` from widgets whose strings now depend on l10n.

- [ ] **Step 4: Verify and commit**

Same commands as Task 1, commit:

```powershell
git commit -m "fix: localize task editor workspace labels"
```

Check GitHub Actions.

---

## Task 4: Localize Home Page UI

**Files:**

- Modify: `mobile_app/lib/features/home/home_page.dart`
- Modify: `mobile_app/lib/features/home/home_chat_section.dart`
- Modify: `mobile_app/lib/l10n/app_en.arb`
- Modify: `mobile_app/lib/l10n/app_ru.arb`
- Generated: `mobile_app/lib/l10n/app_localizations*.dart`
- Test: existing `mobile_app/test/*home*test.dart`, create focused test only if no suitable one exists.

- [ ] **Step 1: Inventory home strings**

Run:

```powershell
cd C:\Users\user\Desktop\weather
Select-String -Path mobile_app\lib\features\home\home_page.dart,mobile_app\lib\features\home\home_chat_section.dart -Pattern '[А-Яа-яЁё]'
Get-ChildItem mobile_app\test -Filter '*home*test.dart'
```

- [ ] **Step 2: Choose one visible slice**

Choose one:

```text
Dashboard cards
Upcoming tasks section
Chat section
Empty states
Snackbars
```

- [ ] **Step 3: Add RED test**

Test must pump the home widget with English locale:

```dart
MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: HomePage(...),
)
```

Assert English visible labels and absence of old Russian labels.

- [ ] **Step 4: Add ARB keys, generate l10n, wire UI**

Use existing keys first:

```text
tasksTab
calendarTab
chatsTab
familyTab
dashboardOnDate
dashboardDone
dashboardFamily
dashboardOverdue
upcomingTasks
noTasks
```

- [ ] **Step 5: Verify**

Run targeted home test and analyzer:

```powershell
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test --no-pub test\<home_test>.dart
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run_flutter_checks.ps1 -SkipTests -Retries 1
```

- [ ] **Step 6: Commit**

```powershell
git commit -m "fix: localize home <specific slice>"
git push
```

Check GitHub Actions.

---

## Task 5: Localize Projects And Groups Screen

**Files:**

- Modify: `mobile_app/lib/features/projects/projects_and_groups_screen.dart`
- Modify related project/group sheet only if the selected slice requires it.
- Modify ARB and generated l10n.
- Test: existing project/group tests.

- [ ] **Step 1: Inventory strings**

Run:

```powershell
Select-String -Path mobile_app\lib\features\projects\projects_and_groups_screen.dart -Pattern '[А-Яа-яЁё]'
Get-ChildItem mobile_app\test -Filter '*project*test.dart'
Get-ChildItem mobile_app\test -Filter '*group*test.dart'
```

- [ ] **Step 2: Start with section labels and empty states**

Target existing keys first:

```text
projectsSection
groups
createProjectAction
createGroupAction
noProjectsYetAction
noGroupsYetAction
editProject
editGroup
delete
cancel
save
```

- [ ] **Step 3: Add RED test**

Test name:

```text
uses localized project and group screen labels
```

Assert:

```dart
expect(find.text('Projects'), findsOneWidget);
expect(find.text('Groups'), findsOneWidget);
expect(find.text('Проекты'), findsNothing);
expect(find.text('Группы'), findsNothing);
```

- [ ] **Step 4: Implement, verify, commit**

Use same command sequence:

```powershell
flutter test --no-pub <target>
run_flutter_checks.ps1 -SkipTests -Retries 1
git diff --check
git commit -m "fix: localize project group screen labels"
git push
```

Check GitHub Actions.

---

## Task 6: Localize Workspace Screens

**Files:**

```text
mobile_app/lib/features/workspaces/session_management_view.dart
mobile_app/lib/features/workspaces/codewhale_workspaces_page.dart
mobile_app/lib/features/workspaces/workspace_detail_view.dart
mobile_app/lib/features/workspaces/session_chat_view.dart
```

- [ ] **Step 1: Inventory strings**

```powershell
Select-String -Path mobile_app\lib\features\workspaces\*.dart -Pattern '[А-Яа-яЁё]'
Get-ChildItem mobile_app\test -Filter '*workspace*test.dart'
Get-ChildItem mobile_app\test -Filter '*session*test.dart'
```

- [ ] **Step 2: Start with one screen only**

Recommended first screen:

```text
session_management_view.dart
```

Choose labels, empty states, and buttons. Do not localize raw session messages from backend unless they are static UI copy.

- [ ] **Step 3: Add RED test**

Test name:

```text
uses localized workspace session management labels
```

- [ ] **Step 4: Implement and verify**

Use l10n pattern, targeted test, analyzer, commit, push, CI.

Commit:

```powershell
git commit -m "fix: localize workspace session labels"
```

---

## Task 7: Classify Agent Prompt And Domain Strings

**Files:**

```text
mobile_app/lib/features/tasks/agent_launch_plan.dart
mobile_app/lib/services/project_chat_agent_service.dart
mobile_app/lib/services/task_agent_automation_service.dart
mobile_app/lib/models/agent_policy.dart
```

- [ ] **Step 1: Inventory strings**

```powershell
Select-String -Path mobile_app\lib\features\tasks\agent_launch_plan.dart,mobile_app\lib\services\project_chat_agent_service.dart,mobile_app\lib\services\task_agent_automation_service.dart,mobile_app\lib\models\agent_policy.dart -Pattern '[А-Яа-яЁё]'
```

- [ ] **Step 2: Create classification notes in commit message or final report**

Classify each group:

```text
UI label
User-visible error
SnackBar/dialog text
Agent prompt body
Stored audit activity
Backend error matching keyword
Fallback after l10n
```

- [ ] **Step 3: Only localize UI/user-visible errors**

Examples to localize if shown directly:

```text
Нет прав на запуск агента
Сначала сохраните задачу
Не удалось запустить агента: {error}
Выберите воркспейс для агентского чата
```

Examples likely intentional and should not be translated in this pass:

```text
Актуальная карточка из мобильного приложения:
После работы обнови карточку...
Работай строго в рамках задачи...
```

- [ ] **Step 4: Add tests for whichever UI path is changed**

Use existing tests:

```text
mobile_app/test/project_chat_agent_service_test.dart
mobile_app/test/task_editor_sheet_test.dart
```

Do not change prompt semantics without service tests.

---

## Task 8: Final Localization Audit

Run after completing Tasks 1-7 or after a meaningful batch.

- [ ] **Step 1: Scan remaining Cyrillic**

```powershell
cd C:\Users\user\Desktop\weather
Select-String -Path mobile_app\lib\*.dart,mobile_app\lib\features\**\*.dart,mobile_app\lib\services\*.dart,mobile_app\lib\models\*.dart -Pattern '[А-Яа-яЁё]' |
  Select-Object Path,LineNumber,Line
```

- [ ] **Step 2: Confirm categories**

Every remaining Cyrillic line must be one of:

```text
RU fallback behind l10n
Agent prompt body
Stored audit/domain text
Backend keyword matching
Debug-only text
Intentional test data
```

- [ ] **Step 3: Add a note to final report**

Use this format:

```text
Remaining Cyrillic:
- app_ru.arb: expected locale data.
- l10n fallbacks: expected defensive fallbacks.
- agent prompt bodies: intentionally Russian product behavior.
- backend keyword matching: intentionally Russian error detection.
No obvious unlocalized user-facing UI strings found in inspected files.
```

Do not claim "all technical debt is gone" unless architecture/test debt was also audited and fixed.

---

## Task 9: Architecture Cleanup After Localization

Start this only after the visible localization backlog is mostly cleared.

Targets:

```text
task_editor_sheet.dart is too large.
Agent launch logic is mixed with UI.
Dialog/snackbar helpers repeat.
Workspace and agent selectors can be extracted.
```

Rules:

1. No behavior changes without tests.
2. Extract only one component/helper per commit.
3. Keep public API stable unless tests prove update.
4. Do not add dependencies.

Recommended extraction order:

```text
Task editor comments/checklists widgets
Task editor agent panel widgets
Task editor workspace settings widgets
Dialog/snackbar helper methods
Agent queue command grouping helpers
```

Each extraction commit:

```powershell
flutter test --no-pub test\task_editor_sheet_test.dart
run_flutter_checks.ps1 -SkipTests -Retries 1
git commit -m "refactor: extract task editor <component>"
git push
```

---

## Completion Checklist

Before saying the work is complete:

- [ ] `git status --short` is empty.
- [ ] Last commit is pushed.
- [ ] GitHub Actions for last commit are success.
- [ ] Targeted tests for changed files pass.
- [ ] Analyzer passes.
- [ ] Remaining Cyrillic strings are audited and categorized.
- [ ] Final report does not say "all tech debt is gone" unless architecture and test debt were actually audited.
- [ ] Report includes commit hashes and exact commands run.

