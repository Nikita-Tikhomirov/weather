# Weather Voice Assistant

Локальный голосовой ассистент на Python для Windows.

Проект умеет:
- слушать голосовые команды с микрофона;
- озвучивать ответы;
- показывать системные desktop-уведомления для ответов ассистента;
- показывать погоду, время, новости, шутки, Википедию и поиск в браузере;
- вести семейный ToDo (по дням, времени, с напоминаниями и историей действий);
- отправлять push-сообщения в Telegram при изменениях в семейном расписании/задачах;
- работать через Telegram-бота как второй интерфейс (сценарии на кнопках + текст только в шагах, где нужен ввод названия);
- запускать детскую угадайку (викторина из `quiz_data`).

## 1. Что в проекте главное

Точка входа:
- `voice_trigger.py` - основной цикл голосового ассистента.

Ключевые модули:
- `audio.py` - распознавание речи (faster-whisper, fallback на Google STT).
- `tts.py` - озвучка через gTTS + pydub.
- `notifier.py` - системные desktop-уведомления + Telegram push.
- `commands.py` + `config.py` - список и запуск голосовых команд.
- `family_todo.py` + `todo_*.py` - семейные задачи и напоминания.
- `telegram_bot.py` - Telegram-интерфейс с мастерами действий по кнопкам.
- `animals.py` + `quiz_data/*.json` - голосовая викторина.

Данные:
- `family_data/<person>/todos.json` - задачи.
- `family_data/<person>/history.json` - история действий для undo.
- `family_data/<person>/schedule.json` - расписание (есть у `arisha`).
- `family_data/family_tasks.json` - общие семейные дела с участниками и длительностью.
- `family_data/logs/events.log` и `family_data/logs/errors.jsonl` - логи.

## 2. Требования

- Windows (есть платформенно-зависимые места: `winsound`, `ctypes`, `schtasks`).
- Python 3.10+.
- Микрофон и интернет.
- FFmpeg в `PATH` (нужен для `pydub`).

## 3. Установка

В PowerShell из корня проекта:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install speechrecognition gTTS pydub requests wikipedia-api pyttsx3 faster-whisper
python -m pip install customtkinter
```

Если хотите использовать только облачное распознавание Google STT, `faster-whisper` можно не ставить.

## 4. Быстрый запуск

Запустить ассистента:

```powershell
python .\voice_trigger.py
```

Или через батник:

```powershell
.\weather.bat
```

## 4.1 Desktop-приложение (GUI)

Сейчас поддерживаются два desktop-клиента:
- новый Flutter Desktop (`mobile_app/`) — основной путь миграции;
- legacy CTk (`desktop_app.py`) — fallback до полного завершения миграции.

Быстрый запуск:

```powershell
.\desktop.bat
```

`desktop.bat` сначала пытается запустить Flutter EXE:
- `mobile_app\build\windows\x64\runner\Release\family_todo_mobile.exe`

Если EXE еще не собран — автоматически запускается legacy CTk клиент:
- `python .\desktop_app.py`

Что уже умеет Flutter desktop GUI:
- dashboard, kanban, calendar, family-экран;
- offline-first CRUD + sync delta/full;
- поиск задач, фильтр по дате, массовое удаление выбранных задач;
- фильтры семейных задач (предстоящие/просроченные/выполненные/все);
- откат последнего действия (undo).

Что умеет legacy CTk GUI (fallback):
- редактирование задач вручную (добавить/изменить/удалить/сделано);
- Kanban-перетаскивание между колонками и reorder внутри колонки;
- отдельная вкладка `Семейные дела` (участники, длительность, редактирование);
- фильтр по человеку и дню;
- поиск по задачам;
- русские подписи в приоритете и повторе (без английских пунктов);
- удобный выбор времени (часы/минуты) и ручной ввод;
- текстовые команды в стиле голосовых фраз;
- откат последнего действия;
- включение/выключение голосового режима прямо из окна.
- включение/выключение встроенного Telegram-бота прямо из окна.
- адаптивный календарь с `+N еще` без налезаний и day-popup строго по выбранной дате.

Ограничение для личных задач:
- если человек участвует в семейном деле, нельзя создать личную задачу в интервале `[start_at - 60 минут, start_at + duration]`.

Важно по Telegram:
- push-уведомления отправляет тот процесс, где выполняется действие;
- поэтому `TELEGRAM_BOT_TOKEN` и `TELEGRAM_FAMILY_CHAT_IDS` должны быть заданы в окружении desktop-приложения (не только в отдельном окне с `telegram_bot.py`).

## 4.2 Упаковка в `.exe`

Скрипт сборки:

```powershell
.\desktop_build.ps1
```

Результат по умолчанию:
- `dist\WeatherAssistantDesktop\WeatherAssistantDesktop.exe`

Сборка в один файл:

```powershell
.\desktop_build.ps1 -OneFile
```

Результат:
- `dist\WeatherAssistantDesktop.exe`

Если используете `onefile`-сборку, отдельный `python .\\telegram_bot.py` запускать не нужно:
- desktop-приложение умеет поднимать встроенный Telegram-бот (переключатель в левом меню).

Сборка Flutter desktop EXE:

```powershell
.\desktop_flutter_build.ps1
```

Результат:
- `mobile_app\build\windows\x64\runner\Release\family_todo_mobile.exe`

Сборка Flutter Android APK:

```powershell
.\mobile_flutter_build.ps1
```

Результат:
- `mobile_app\build\app\outputs\flutter-apk\app-release.apk`

## 5. Как пользоваться (основной сценарий)

1. Запускаете `voice_trigger.py`.
2. Ассистент ждет голосовую команду.
3. Говорите одну из поддерживаемых команд.
4. Если это сценарий с диалогом (например `вики`, `туду`, `угадайка`) - ассистент задает уточнения голосом.

## 6. Поддерживаемые голосовые команды

Основные команды (из `config.py`):
- `погода` - текущая погода (Open-Meteo).
- `включи кино` - открывает Кинопоиск в браузере.
- `который час` - озвучивает текущее время.
- `интерфакс` - читает 3 свежие новости из RSS.
- `прикол` - случайная шутка.
- `вики` - поиск и озвучка краткой статьи Википедии.
- `яндекс` - голосовой поисковый запрос (если сказать `гугл`, откроет Google).
- `выключи компьютер` - вызывает задачу `ShutdownTask` через `schtasks`.
- `смени язык` - эмуляция `Alt+Shift`.
- `угадайка` - голосовая викторина.
- `тудушка` / `туду` / `задачи` - семейный ToDo режим.
- `телеграм бот` - запуск Telegram-бота.
- `выход` - завершение ассистента.

## 6.1 Telegram как второй интерфейс

Перед запуском задайте переменные окружения:

```powershell
$env:TELEGRAM_BOT_TOKEN='123456:ABCDEF...'
$env:TELEGRAM_FAMILY_CHAT_IDS='111111111,222222222'
```

Запуск:

```powershell
python .\telegram_bot.py
```

Что умеет бот:
- пошаговые кнопочные сценарии: `➕ Задача`, `🗑 Удалить`, `✅ Сделано`, `🔁 Перенести`, `🗓 Расписание`, `➕ Урок`, `🗑 Урок`;
- выбор роли через `🪪 Кто я` и выбор профиля через `👤 Профиль`;
- отправлять уведомления в Telegram и на desktop с учетом прав/приватности.

## 6.2 Роли и приватность

Роли:
- взрослые: `Ник`, `Настя`;
- дети: `Миша`, `Ариша`.

Права:
- взрослые могут менять только свой профиль и профили детей;
- дети могут менять только свой профиль;
- взрослые не меняют профиль друг друга.

Видимость уведомлений:
- изменения в профиле взрослого видит только этот взрослый;
- изменения в профиле ребенка видят оба взрослых и сам ребенок.

## 7. Семейный ToDo: как говорить команды

Сначала скажите имя человека (`ник`, `миша`, `настя`, `ариша`).

Примеры:
- Добавить задачу:
  - `добавь во вторник в 19 30 кормить крыс`
  - `добавь каждый день в 8 00 зарядка`
- Показать задачи:
  - `список на вторник`
  - `что на сегодня`
- Отметить выполненной:
  - `отметь вторник номер 1`
- Перенести:
  - `перенеси вторник кормить крыс на среду в 20 15`
- Удалить:
  - `удали все дела на вторник`
  - `удали вторник кормить крыс`
- Откат последнего действия:
  - `отмени`
- Недельный обзор:
  - `недельный обзор`

Встроены стоп-слова: `стоп`, `выход`, `хватит`, `заверши`.

## 8. Распознавание речи (важно)

`audio.py` работает так:
- сначала пытается использовать `faster-whisper` (локально);
- если не получилось, переходит на `recognize_google`.

Полезные переменные окружения:
- `FW_MODEL` (по умолчанию `large-v3`)
- `FW_DEVICE` (`cpu` или `cuda`)
- `FW_COMPUTE_TYPE` (например `int8_float16`)
- `STT_DEBUG=1` - печать распознанного текста

Пример:

```powershell
$env:FW_MODEL='small'
$env:FW_DEVICE='cpu'
python .\voice_trigger.py
```

## 9. Запуск тестов

В проекте есть unit-тесты для семейного ToDo:

```powershell
python -m unittest discover -s tests -v
```

Если запускать просто `python -m unittest -v`, тесты могут не находиться.

## 10. Полезные файлы

- `config.py` - глобальные настройки (таймауты, язык, координаты погоды, список команд).
- `family_todo.py` - основная логика задач и напоминаний.
- `generate_quiz_data.py` - пересобирает `quiz_data/*.json`.
- `todo_logger.py` - запись событий/ошибок в лог.

## 11. Частые проблемы и решения

1. Нет звука или ошибка TTS
- Проверьте интернет (gTTS облачный).
- Проверьте, что установлен FFmpeg и доступен в `PATH`.

2. Речь не распознается

## 12. Mobile + Backend sync (Android + Telegram 2-way)

В проект добавлен backend API для единого source of truth:

- `backend_api/public/index.php`
- `backend_api/sql/schema.sql`
- `backend_api/config.example.php`

После деплоя backend включите его для desktop/telegram процесса:

```powershell
$env:TODO_BACKEND_URL='https://your-domain.tld'
$env:TODO_BACKEND_API_KEY='YOUR_API_KEY'
```

Или задайте единый конфиг проекта (рекомендуется, без ручного `set env` на каждый запуск):

- `sync_runtime.json` - базовый runtime-конфиг (в репозитории);
- `sync_runtime.local.json` - локальные секреты/переопределения (игнорируется git).

Пример `sync_runtime.local.json`:

```json
{
  "backend_url": "https://familly.nikportfolio.ru/backend_api/public",
  "backend_api_key": "YOUR_API_KEY",
  "backend_source": "desktop"
}
```

Текущий режим миграции (без домена, по IP):

```json
{
  "backend_url": "http://31.129.97.211",
  "backend_api_key": "YOUR_API_KEY",
  "backend_source": "desktop"
}
```

Для Android в IP-режиме включен cleartext HTTP (`android:usesCleartextTraffic="true"` в `AndroidManifest.xml`).
Прогресс по фазам Laravel-миграции фиксируется в `docs/laravel_migration_progress.md`.

Для процесса Telegram-бота дополнительно:

```powershell
$env:TODO_BACKEND_SOURCE='telegram'
```

Примечание: встроенный бот из `desktop_app.py` теперь автоматически запускается с `TODO_BACKEND_SOURCE=telegram`.

Что это дает:

- desktop и Telegram-бот записывают изменения в backend;
- мобильное и desktop Flutter-приложения (`mobile_app/`) синхронизируются через `/sync/push`, `/sync/pull` и `/sync/changes`;
- быстрые обновления идут через delta-режим `changes since cursor`, а полный snapshot используется как fallback раз в 10 минут;
- outbox backend подавляет дубли одинаковых уведомлений (push/telegram) в коротком окне и при retry;
- desktop агрегирует пачку sync-событий в один toast и подавляет повтор одинаковых событий по cooldown;
- `telegram_bot.py` в режиме `--bot-only` работает как singleton (один активный процесс);
- при недоступности Telegram используется outbox-очередь в backend (`telegram_outbox`), которую можно повторно отправить через:

```bash
POST /telegram/outbox/retry
```

или локально из проекта:

```powershell
python .\scripts\retry_telegram_outbox.py
```

Для этого хостинга без rewrite используйте URL вида:

```powershell
$env:TODO_BACKEND_URL='https://familly.nikportfolio.ru/backend_api/public'
```

И endpoint-файлы:

- `sync_push.php`
- `sync_pull.php`
- `sync_changes.php`
- `devices_register.php`
- `devices_unregister.php`
- `telegram_outbox_retry.php`
- `push_outbox_retry.php`

В репозитории присутствуют плоские endpoint-обертки в `backend_api/public/*.php` для shared-hosting деплоя без rewrite.

### FCM app-to-app push

В backend появились endpoint'ы:

- `POST /devices/register`
- `POST /devices/unregister`
- `POST /push/outbox/retry`

В `backend_api/config.php` заполните секцию `fcm`:

- `project_id`
- `service_account_email`
- `private_key`

Для Android-клиента:

- добавьте `google-services.json` в `mobile_app/android/app/google-services.json`;
- укажите корректный `applicationId`;
- убедитесь, что FCM включен в Firebase-проекте.
- прогоните smoke backend-проверку:

```powershell
python .\scripts\smoke_backend_sync.py
```

Legacy-cleanup старых/битых записей у всех профилей (без удаления валидных задач):

```powershell
python .\scripts\cleanup_legacy_todos.py
```
- Проверьте микрофон в Windows.
- Увеличьте тишину в комнате (в коде есть авто-калибровка шума).
- Включите `STT_DEBUG=1`.

3. Команда `выключи компьютер` не работает
- В системе должна существовать задача планировщика `ShutdownTask`.

4. Кривые символы в консоли
- Это кодировка терминала Windows, а не обязательно проблема логики.
- Для отображения UTF-8 можно попробовать `chcp 65001` перед запуском.
- Файлы проекта должны быть сохранены в UTF-8 (без ANSI), чтобы не ломалась кириллица.

## 12. Что можно улучшить дальше

- Добавить `requirements.txt`/`pyproject.toml` для воспроизводимой установки.
- Добавить отдельный CLI-режим без микрофона (для отладки команд текстом).
- Расширить тесты на все команды, не только семейный ToDo.
- Вынести desktop-UI на Tauri/Electron, если нужна web-верстка, автообновления и richer UX.

