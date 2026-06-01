# ТЗ: устранение технического долга и багов Family Todo Mobile

Дата анализа: 2026-06-01.

## Цель

Стабилизировать Flutter-приложение `mobile_app`, снизить риск регрессий в мессенджере, звонках, синхронизации и проектных чатах, а также убрать найденные секреты из deploy-контура.

## Текущее состояние

- Приложение: Flutter `family_todo_mobile`, Android-first + Windows desktop.
- Backend по умолчанию: `http://31.129.97.211`.
- VPS: Ubuntu 24.04.4 LTS; активны `nginx`, `php8.3-fpm`, `mariadb`, `coturn`, `project-tunnel`.
- Health-check `http://127.0.0.1/health` на VPS отвечает `200`.
- `flutter test --concurrency=1` проходит: 231 тест.
- Обычный `flutter test` без ограничения параллельности дал один нестабильный сбой загрузки suite; отдельный suite проходит.
- `flutter analyze` сейчас возвращает 359 info/lint issues.

## Найденные проблемы

### P0: секреты в deploy-скриптах

В `deploy_vps.ps1` и `deploy_backend_api.ps1` был захардкожен пароль root-доступа к VPS. Это прямой риск повторной утечки и блокер для безопасной поддержки.

Требования:
- пароль не хранится в git;
- deploy читает пароль из `WEATHER_VPS_PASSWORD` или параметра `-HostPassword`;
- Python/paramiko получает пароль через переменную окружения, а не через сгенерированный текст скрипта;
- README описывает безопасный запуск.

### P1: реальные async UI-риски

`flutter analyze` показывает 4 случая `use_build_context_synchronously`:
- `mobile_app/lib/features/home/home_page.dart`;
- `mobile_app/lib/features/home/home_profile_init.dart`;
- `mobile_app/lib/features/home/home_share_receiver.dart`.

Требования:
- после каждого `await` перед использованием `context`, `ScaffoldMessenger`, `Navigator`, `setState` проверять `mounted`;
- добавить или обновить widget/unit tests на затронутые сценарии.

### P1: небезопасные production-defaults

Найдены dev/default значения:
- `API_KEY=dev-local-key` в Flutter/Android/CI;
- default TURN credential;
- Firebase API key в workflow fallback и `google-services.json`;
- `android:usesCleartextTraffic="true"` и HTTP backend.

Требования:
- production APK должен собираться только с секретами из GitHub Secrets или локальных env;
- HTTP оставить только как временный dev/fallback режим;
- подготовить переход на HTTPS backend.

### P2: нестабильный локальный полный тестовый запуск

CI уже использует `flutter test --concurrency=1`, а локальный полный запуск без этого флага может падать при параллельной загрузке из-за глобального `sqflite` factory.

Требования:
- документация и локальные команды используют `--concurrency=1`;
- отдельной задачей изолировать sqflite-тесты, чтобы вернуть безопасную параллельность.

### P2: lint debt

`flutter analyze --format=machine`:
- 359 issues всего;
- 282 `REQUIRE_TRAILING_COMMAS`;
- 33 `PREFER_CONST_LITERALS_TO_CREATE_IMMUTABLES`;
- 19 `PREFER_CONST_CONSTRUCTORS_IN_IMMUTABLES`;
- 14 `UNNECESSARY_LAMBDAS`;
- 4 `USE_BUILD_CONTEXT_SYNCHRONOUSLY`;
- единичные `UNNECESSARY_IMPORT`, `CURLY_BRACES_IN_FLOW_CONTROL_STRUCTURES`, `DANGLING_LIBRARY_DOC_COMMENTS`, `USE_SUPER_PARAMETERS`.

Требования:
- сначала исправлять поведенческие и lifecycle issues;
- форматные lints закрывать механически через `dart format`, без ручных refactor-рисков;
- каждый блок проверять `flutter analyze` и targeted tests.

### P2: крупные файлы и границы ответственности

Самые крупные файлы:
- `mobile_app/lib/features/home/home_page.dart` — 3824 строки;
- `mobile_app/lib/services/local_db.dart` — 906 строк;
- `mobile_app/lib/features/workspaces/codewhale_workspaces_page.dart` — 727 строк;
- `mobile_app/lib/state/task_store.dart` — 669 строк;
- `mobile_app/lib/features/chat/call_screen.dart` — 659 строк;
- `mobile_app/lib/features/workspaces/session_management_view.dart` — 627 строк;
- `mobile_app/lib/features/chat/messenger_page.dart` — 597 строк.

Требования:
- не делать большой rewrite;
- продолжить существующий подход с `part`/фасадами;
- каждый split закрывать тестами до и после.

## Приоритеты работ

1. Убрать пароль VPS из deploy-скриптов и документации.
2. Зафиксировать ТЗ и implementation plan в `docs/superpowers`.
3. Исправить `use_build_context_synchronously`.
4. Зафиксировать локальную команду тестов `flutter test --concurrency=1`.
5. Закрыть 359 analyzer issues пакетами по доменам.
6. Перенести production defaults в env/secrets и подготовить HTTPS.
7. Разбить `home_page.dart`, `local_db.dart`, затем workspaces/chat файлы.
8. Добавить smoke-проверку VPS/API в CI или отдельный скрипт.

## Definition of Done

- P0 исправлен и пароль отсутствует в tracked-файлах.
- `flutter test --concurrency=1` проходит.
- `flutter analyze` не содержит новых ошибок; количество issues монотонно снижается.
- Серверные health-checks документированы.
- Изменения закоммичены и запушены.
