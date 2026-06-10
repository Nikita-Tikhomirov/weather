# ТЗ: стабилизация мобильного Flutter-приложения

Дата анализа: 2026-06-10.

## Цель

Снять свежий срез технического долга `mobile_app`, исправить найденные безопасные дефекты и оставить проверяемый путь для дальнейших refactor-задач без большого rewrite.

## Текущее состояние

- Приложение: Flutter `family_todo_mobile`, Android-first + Windows desktop.
- Фактический локальный SDK: `C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat`.
- `flutter analyze` на Flutter 3.41.7 / Dart 3.11.5 проходит без issues.
- `dart format --set-exit-if-changed lib test` ничего не меняет.
- Полный `flutter test --concurrency=1` нестабилен в текущем Windows-окружении: разные suite могут падать до загрузки с `Connection closed before test suite loaded`.
- Windows Event Log подтверждает native crash `flutter_tester.exe` с `0xc0000005`; в том же временном окне есть такие же access violations у `powershell.exe`, `git.exe`, `dart.exe`, `where.exe`.

## Найденные проблемы

### P1: устаревшая локальная команда Flutter

`README.md` и `mobile_app/README.md` указывали на `C:\Users\user\tools\flutter\bin\flutter.bat`. В текущем shell этот путь не запускается, а рабочий SDK находится в Puro.

Требования:
- документация должна вести к рабочему SDK;
- путь можно переопределить через `FLUTTER_BIN`;
- команды проверки не должны требовать изменения системного `PATH`.

### P1: нестабильный полный test runner на Windows

Полный локальный прогон может падать не из-за assertion, а из-за native crash `flutter_tester.exe` до загрузки suite. Отдельно упавшие suite проходят.

Требования:
- не запускать несколько Flutter-команд параллельно;
- оставить CI-equivalent команду `flutter test --concurrency=1`;
- добавить локальный fallback, который прогоняет suite последовательно и повторяет только инфраструктурные падения;
- не маскировать реальные compile/assertion failures.

### P2: крупные файлы и подавленные lints

Самые крупные файлы на 2026-06-10:
- `mobile_app/lib/features/tasks/task_editor_sheet.dart` — 5306 строк;
- `mobile_app/lib/features/home/home_page.dart` — 3418 строк;
- `mobile_app/lib/features/projects/projects_and_groups_screen.dart` — 1048 строк;
- `mobile_app/lib/services/task_agent_automation_service.dart` — 1027 строк;
- `mobile_app/lib/services/local_db.dart` — 977 строк.

Оставшиеся suppressions:
- `invalid_use_of_protected_member` в `home_chat_section.dart` и `projects_data.dart`;
- точечные `avoid_slow_async_io` в push/FCM handlers;
- `annotate_overrides` в `local_db.dart`.

Требования:
- не делать массовый split в этой фазе;
- следующие refactor-задачи начинать с тестов конкретного поведения;
- сначала выделять pure helpers и небольшие services из `task_editor_sheet.dart` и `home_page.dart`.

## Реализуемый объем этой фазы

1. Добавить локальный runner `mobile_app/tool/run_flutter_checks.ps1`.
2. Обновить `README.md` и `mobile_app/README.md` на актуальный SDK и runner.
3. Задокументировать root cause текущей нестабильности тестов.
4. Оставить следующий план refactor-задач без изменения production-поведения.

## Definition of Done

- `flutter analyze` проходит.
- Новый runner запускает analyzer.
- Документация больше не указывает основной путь на нерабочий `C:\Users\user\tools\flutter`.
- Полный test failure описан как инфраструктурный native crash с evidence, а не скрыт.
- Изменения закоммичены и запушены.
