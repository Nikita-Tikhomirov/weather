# Technical Debt Cleanup Spec For DeepSeek

Этот файл является самодостаточным заданием для следующего агента/исполнителя.
Прочитать полностью перед началом работы.

## 1. Цель

Продолжить устранение технического долга в мобильном Flutter-приложении `mobile_app`.
Первый и текущий основной пласт долга: оставшиеся hardcoded Russian UI strings, которые должны быть вынесены в Flutter l10n.

Работать end-to-end:

1. Найти маленький покрываемый срез.
2. Добавить failing test.
3. Убедиться, что тест падает по ожидаемой причине.
4. Внести минимальную правку.
5. Прогнать targeted tests и analyzer.
6. Сделать commit.
7. Push в `master`.
8. Проверить GitHub Actions для нового commit.

Не останавливаться на анализе, если можно безопасно сделать следующий маленький срез.

## 2. Текущая точка входа

Репозиторий:

```text
C:\Users\user\Desktop\weather
```

Мобильное приложение:

```text
C:\Users\user\Desktop\weather\mobile_app
```

Основная ветка:

```text
master
```

Базовый commit перед этим handoff:

```text
d5689b53 fix: localize chat audio placeholder
```

На момент handoff этот commit был запушен, GitHub Actions были зелёные:

```text
Tests: success
Mobile APK Build: success
```

Перед началом новой работы проверить актуальное состояние самостоятельно:

```powershell
cd C:\Users\user\Desktop\weather
git status --short
git rev-parse --short HEAD
git log -20 --oneline
```

Если worktree не чистый, не удалять чужие изменения. Разобраться, относятся ли они к текущей задаче.

## 3. Обязательные правила работы

### 3.1. Не использовать локальную LLM/Ollama

Пользователь попросил не использовать локальную LLM-прослойку, чтобы не занимать VRAM.

Запрещено:

```text
ollama run ...
ollama serve ...
local-first-preflight.ps1
harness smoke/live/ab/gate, если он запускает локальные модели
```

Если процесс `ollama` сам поднялся внешней автозадачей, остановить его:

```powershell
Get-Process | Where-Object { $_.ProcessName -like '*ollama*' } |
  Select-Object Id,ProcessName,CPU,WorkingSet64

Get-Process | Where-Object { $_.ProcessName -like '*ollama*' } |
  Stop-Process -Force
```

Не писать, что "локалка не требовалась". Просто не использовать.

### 3.2. TDD обязательно для каждого bugfix/UI-change

Для каждого среза:

1. Написать тест.
2. Запустить его.
3. Увидеть RED.
4. Только после этого менять production code.
5. Увидеть GREEN.

Пример целевого цикла:

```powershell
cd C:\Users\user\Desktop\weather\mobile_app
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test --no-pub test\some_test.dart --plain-name "uses localized label"
```

Ожидаемый RED:

```text
Expected: exactly one matching candidate
Actual: Found 0 widgets with text "English label"
```

После правки:

```text
All tests passed!
```

### 3.3. Git обязателен после каждого логического среза

После каждого маленького законченного среза:

```powershell
cd C:\Users\user\Desktop\weather
git diff --check
git -c core.fsmonitor=false add -- <changed files>
git commit -m "fix: localize ..."
git push
```

Не использовать destructive git commands:

```text
git reset --hard
git checkout -- <file>
git clean -fd
force-push
```

Если commit не проходит из-за identity:

```powershell
git config user.name "Nikita"
git config user.email "stithc92@gmail.com"
```

### 3.4. Проверки перед commit

Минимум для каждого среза:

```powershell
cd C:\Users\user\Desktop\weather\mobile_app
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test --no-pub test\<target_test>.dart
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run_flutter_checks.ps1 -SkipTests -Retries 1
```

Для docs-only changes достаточно:

```powershell
git diff --check
```

### 3.5. Проверка GitHub Actions после push

После push проверить Actions для exact HEAD SHA.
Не просить пользователя смотреть логи.

Шаблон PowerShell:

```powershell
cd C:\Users\user\Desktop\weather
$ErrorActionPreference='Stop'
$sha=(git rev-parse HEAD).Trim()
$remote=(git config --get remote.origin.url).Trim()
$repo='Nikita-Tikhomirov/weather'
$token=$env:GH_TOKEN
if (-not $token -and $remote -match '^https://(?<token>[^@]+)@github\.com/') {
  $token=$Matches.token
}
$headers=@{
  'Accept'='application/vnd.github+json'
  'User-Agent'='codex-ci-check'
}
if ($token) { $headers['Authorization'] = "Bearer $token" }
$deadline=(Get-Date).AddMinutes(12)
while ((Get-Date) -lt $deadline) {
  $runs=Invoke-RestMethod -Headers $headers -Uri "https://api.github.com/repos/$repo/actions/runs?branch=master&per_page=20"
  $matching=@($runs.workflow_runs | Where-Object { $_.head_sha -eq $sha } | Sort-Object created_at)
  if ($matching.Count -eq 0) {
    Write-Output "waiting_for_runs sha=$($sha.Substring(0,8))"
    Start-Sleep -Seconds 10
    continue
  }
  $matching |
    ForEach-Object {
      [PSCustomObject]@{
        name=$_.name
        status=$_.status
        conclusion=$_.conclusion
        url=$_.html_url
      }
    } |
    Format-Table -AutoSize
  $incomplete=@($matching | Where-Object { $_.status -ne 'completed' })
  if ($incomplete.Count -eq 0) {
    $failed=@($matching | Where-Object { $_.conclusion -ne 'success' })
    if ($failed.Count -gt 0) { exit 2 }
    exit 0
  }
  Start-Sleep -Seconds 15
}
Write-Output "timed_out sha=$sha"
exit 3
```

Если Actions упали:

1. Получить failing run URL из вывода.
2. Забрать logs через GitHub API или `gh`.
3. Исправить причину.
4. Повторить tests/analyzer/commit/push.

## 4. Известные особенности окружения

Flutter SDK:

```text
C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat
```

Dart formatter:

```text
C:\Users\user\.puro\envs\stable\flutter\bin\dart.bat
```

Analyzer wrapper:

```text
C:\Users\user\Desktop\weather\mobile_app\tool\run_flutter_checks.ps1
```

Известные infrastructure flakes:

```text
git subprocess failed with exit code -1073741819
Puro crashed
empty exit code 1 без stdout/stderr
Connection closed before test suite loaded
```

Что делать:

1. Если команда упала пусто или с `-1073741819`, перезапустить один раз.
2. Если analyzer wrapper пишет "retrying flutter analyze after infrastructure failure" и затем `No issues found!`, это валидный pass.
3. Не запускать несколько Flutter test/analyze процессов параллельно.
4. Для git staging использовать:

```powershell
git -c core.fsmonitor=false add -- <files>
```

## 5. Безопасность

Не коммитить секреты.
Не печатать токены из remote URL.
Не вставлять пароли или access tokens в файлы проекта.

В предыдущем диалоге пользователь раскрывал VPS root-доступ. В код, docs, commits и логи его не вставлять. После завершения стоит рекомендовать пользователю ротировать пароль, но без повторения секрета.

## 6. Уже сделано

Последние green commits:

```text
d5689b53 fix: localize chat audio placeholder
571ebd2e fix: localize chat upload progress
dbbe2093 fix: localize chat message footer
c0f1e7fd fix: localize chat image placeholder
a721d9d6 fix: localize messenger empty contacts
7ef30e38 fix: localize messenger typing labels
000fbce8 fix: localize messenger call tooltips
8f37cddf fix: localize messenger contacts toolbar
95a12d66 fix: localize messenger conversation sections
eda1b120 fix: localize messenger composer input
8f3e79fb fix: localize messenger composer labels
fb74a388 fix: localize messenger project actions
270d396b fix: localize share receiver dialog
2ff7f4b5 fix: localize initial profile prompt
244a6bb6 fix: localize desktop shell toolbar
8753d54d fix: localize project group menus
d40078f4 fix: localize project workspace controls
8c9a1aaf fix: localize admin access labels
732e9814 fix: localize project section empty states
6e5f54b3 fix: localize project file browser
```

Covered areas:

```text
mobile_app/lib/features/chat/messenger_page.dart
mobile_app/lib/features/chat/chat_message_bubble.dart
mobile_app/lib/features/chat/chat_audio_bubble.dart
mobile_app/lib/features/home/home_share_receiver.dart
mobile_app/lib/features/share/share_receiver.dart
mobile_app/lib/features/home/home_profile_initializer.dart
mobile_app/lib/features/home/desktop_shell_labels.dart
mobile_app/lib/features/projects/project/group UI slices
mobile_app/lib/features/admin/admin_access_page.dart
```

Relevant tests added or expanded:

```text
mobile_app/test/messenger_project_actions_test.dart
mobile_app/test/chat_messages_list_test.dart
mobile_app/test/home_share_receiver_test.dart
mobile_app/test/profile_init_service_test.dart
mobile_app/test/desktop_shell_widget_test.dart
```

## 7. Current remaining scope

Run this to get the current list:

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

Expected high-priority files:

```text
mobile_app\lib\features\tasks\task_editor_sheet.dart
mobile_app\lib\features\home\home_page.dart
mobile_app\lib\features\projects\projects_and_groups_screen.dart
mobile_app\lib\services\project_chat_agent_service.dart
mobile_app\lib\features\tasks\agent_launch_plan.dart
mobile_app\lib\features\chat\sticker_catalog.dart
mobile_app\lib\features\workspaces\session_management_view.dart
mobile_app\lib\features\home\home_chat_section.dart
mobile_app\lib\features\home\projects_data.dart
mobile_app\lib\features\admin\admin_access_page.dart
mobile_app\lib\features\tasks\task_editor_collaboration_widgets.dart
mobile_app\lib\features\tasks\task_editor_text.dart
mobile_app\lib\services\task_agent_automation_service.dart
mobile_app\lib\models\agent_policy.dart
mobile_app\lib\features\projects\chat_task_draft_editor_sheet.dart
mobile_app\lib\features\workspaces\codewhale_workspaces_page.dart
mobile_app\lib\features\projects\project_chat_view.dart
mobile_app\lib\models\project_control_models.dart
mobile_app\lib\features\workspaces\workspace_detail_view.dart
mobile_app\lib\features\projects\family_group_edit_sheet.dart
mobile_app\lib\features\chat\call_screen.dart
```

Important: this list includes intentional Russian content too.
Do not blindly move every Cyrillic string into l10n.

## 8. How to classify Cyrillic strings

Move to l10n:

```text
Text(...)
Tooltip(...)
SnackBar text
Dialog title/message/action labels
InputDecoration labelText/hintText/helperText
PopupMenuItem child labels
Button labels
Empty states
Section titles
Status labels visible in UI
Validation errors shown to users
```

Usually keep as constants or domain text, not l10n:

```text
Agent prompt bodies intended to be Russian instructions for an AI agent
Audit/activity text stored as Russian business history, if product intentionally stores it in Russian
Search keywords used to detect Russian backend errors, e.g. lower.contains('ошибка')
Test data in tests
Fallback strings after l10n is already wired, e.g. l10n?.cancel ?? 'Отмена'
Debug logs that are never shown to users
```

If a string is both shown to user and stored as business history, decide per call site:

1. UI presentation label goes to l10n.
2. Stored audit event can remain Russian if existing product history expects Russian.
3. If changing stored text affects backend expectations, do not change without a focused test.

## 9. l10n implementation pattern

Files:

```text
mobile_app/lib/l10n/app_en.arb
mobile_app/lib/l10n/app_ru.arb
mobile_app/lib/l10n/app_localizations.dart
mobile_app/lib/l10n/app_localizations_en.dart
mobile_app/lib/l10n/app_localizations_ru.dart
```

Do not edit generated `app_localizations*.dart` manually except via `flutter gen-l10n`.

Add key in both ARB files.

Simple key example:

```json
"taskComments": "Comments"
```

Russian:

```json
"taskComments": "Комментарии"
```

Parameterized key example:

```json
"taskSaveFailed": "Could not save task: {error}",
"@taskSaveFailed": {
  "placeholders": {
    "error": {}
  }
}
```

Russian:

```json
"taskSaveFailed": "Не удалось сохранить задачу: {error}",
"@taskSaveFailed": {
  "placeholders": {
    "error": {}
  }
}
```

Run:

```powershell
cd C:\Users\user\Desktop\weather\mobile_app
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' gen-l10n
```

Use in widget:

```dart
import '../../l10n/app_localizations.dart';

final l10n = AppLocalizations.of(context);

Text(l10n?.taskComments ?? 'Комментарии')
```

Use parameterized:

```dart
Text(l10n?.taskSaveFailed(error.toString()) ?? 'Не удалось сохранить задачу: $error')
```

## 10. Testing pattern

Every localization fix should have an English-locale test.

Template:

```dart
await tester.pumpWidget(
  MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: WidgetUnderTest(...),
    ),
  ),
);

expect(find.text('English label'), findsOneWidget);
expect(find.text('Русская строка'), findsNothing);
```

For tooltips:

```dart
expect(find.byTooltip('English tooltip'), findsOneWidget);
expect(find.byTooltip('Русский tooltip'), findsNothing);
```

For snackbars/dialogs:

```dart
await tester.tap(find.text('Trigger'));
await tester.pumpAndSettle();
expect(find.text('English message'), findsOneWidget);
expect(find.text('Русское сообщение'), findsNothing);
```

## 11. Recommended next files and what to do

### 11.1. `task_editor_sheet.dart`

This is the largest remaining file. Do not refactor it as one giant task.

Start with visible UI labels near the bottom where sections are built:

```text
Комментарии
Комментариев нет
Чеклисты
Новый чеклист
Добавить чеклист
Чеклистов нет
Активность
Пока пусто
Агент
Вопросы агента
Подключить чат
Новый чат
Чаты задачи
Агентские чаты не подключены
Воркспейс
Не выбран
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

Use existing tests:

```text
mobile_app/test/task_editor_sheet_test.dart
```

Run targeted tests first:

```powershell
cd C:\Users\user\Desktop\weather\mobile_app
& 'C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat' test --no-pub test\task_editor_sheet_test.dart --plain-name "<new test name>"
```

If the full file is too slow, still run at least the target test plus analyzer before commit.

### 11.2. `home_page.dart` and `home_chat_section.dart`

Focus:

```text
Dashboard labels
Section titles
Buttons
Empty states
Snackbars
Chat section labels
```

Likely tests:

```powershell
Get-ChildItem C:\Users\user\Desktop\weather\mobile_app\test -Filter '*home*test.dart'
```

Add English locale tests near existing home tests.

### 11.3. `projects_and_groups_screen.dart`

Focus:

```text
Project/group section labels
Create/edit/delete dialogs
Empty project/group states
Validation errors
Popup menu labels
Snackbars
```

Likely tests:

```text
mobile_app/test/project_control_center_test.dart
mobile_app/test/*project*test.dart
```

Use existing app l10n keys where available:

```text
projectsSection
groups
createProjectAction
createGroupAction
editProject
editGroup
delete
cancel
save
```

### 11.4. `workspaces/*`

Focus:

```text
Workspace list/loading/empty/error labels
Session management labels
Buttons/tooltips
Status texts
```

Likely files:

```text
mobile_app/lib/features/workspaces/session_management_view.dart
mobile_app/lib/features/workspaces/codewhale_workspaces_page.dart
mobile_app/lib/features/workspaces/workspace_detail_view.dart
mobile_app/lib/features/workspaces/session_chat_view.dart
```

### 11.5. Agent-related files

Files:

```text
mobile_app/lib/features/tasks/agent_launch_plan.dart
mobile_app/lib/services/project_chat_agent_service.dart
mobile_app/lib/services/task_agent_automation_service.dart
mobile_app/lib/models/agent_policy.dart
```

Be careful:

1. UI labels and user-visible errors should be l10n.
2. Agent prompts can intentionally remain Russian.
3. Stored activity text may intentionally remain Russian.
4. Do not break prompt semantics while doing UI localization.

If in doubt, choose a small UI-only sрез first.

## 12. Definition of Done for the whole remaining project

The task is not done until all of this is true:

1. No obvious user-visible hardcoded Russian UI remains outside `app_ru.arb`.
2. Remaining Cyrillic strings are classified as one of:
   - RU locale resources.
   - Intentional agent prompts.
   - Intentional stored activity/domain text.
   - Tests/test data.
   - Fallbacks after l10n.
3. Every changed behavior has a RED/GREEN test.
4. `flutter analyze` via wrapper passes.
5. Relevant widget/unit tests pass.
6. Every logical sрез is committed and pushed.
7. GitHub Actions are green for final HEAD.
8. Worktree is clean.
9. Final report lists:
   - Commits.
   - Tests run.
   - Remaining intentional Cyrillic categories.
   - Any risks.

## 13. Suggested progress estimate

At handoff:

```text
Messenger/chat localization: about 90% done.
Whole mobile UI localization: about 40% done.
Overall mobile technical debt cleanup: about 30% done.
```

After completing `task_editor_sheet.dart`, progress should jump significantly because it is the largest visible remaining file.

