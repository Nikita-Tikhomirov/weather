## ТЗ: Технический долг Family Todo Mobile — оставшиеся 7 пунктов

### Контекст
Проект: `C:\Users\user\Desktop\weather\mobile_app`
Предыдущие 12 пунктов выполнены и запушены в `master` (6 коммитов).
`flutter analyze` показывает 739 issues — в основном тесты с устаревшим API и trailing commas.

### 1. Разбить God-классы сервисов

**`lib/services/local_db.dart` (847 строк)**
Разбить по доменам:
- `local_db_tasks.dart` — таблицы tasks, task_tags, task_history
- `local_db_projects.dart` — таблицы projects, family_groups, project_files
- `local_db_chat.dart` — таблицы chat_messages, conversations, contacts, stickers
- В `local_db.dart` оставить `open()`, миграции, общие хелперы. Новые файлы импортировать как part или отдельные классы.

**`lib/services/fcm_service.dart` (852 строки)**
Выделить:
- `fcm_messaging.dart` — инициализация Firebase, регистрация токена, background handler
- `fcm_notifications.dart` — локальные уведомления, каналы, показ
- `fcm_diagnostics.dart` — диагностика токенов, метод channel
- В `fcm_service.dart` оставить класс `FcmService`, координацию, dispose.

**`lib/services/project_bridge_service.dart` (611 строк)**
Выделить:
- `bridge_connection.dart` — WebSocket connect/reconnect/ping
- `bridge_protocol.dart` — сериализация/десериализация сообщений BridgeMessage
- В `project_bridge_service.dart` оставить публичный API, координацию.

**`lib/services/api_client.dart` (615 строк)**
Уже фасад над Sync/Chat/Call клиентами. Можно оставить как есть или выделить реэкспорты в отдельный barrel-файл. На своё усмотрение.

**После разбивки:** обновить все импорты в `home_page.dart` и других файлах. Убедиться что `flutter analyze` ошибок стало меньше.

### 2. Разбить home_page.dart

Сейчас 3922 строки. Выделить в `lib/features/home/` отдельные part-файлы (уже используется `part` для `desktop_shell.dart`, `share_receiver.dart`, `projects_data.dart`):

- `home_navigation.dart` — нижняя навигация, `BottomNavigationBar`, переключение страниц, `_buildNavBar`
- `home_chat_section.dart` — всё что связано с чатом: список контактов, сообщения, ввод текста, стикеры. Методы `_initChat`, `_openConversation`, `_onChatInputChanged`, `_sendMessage`, и все связанные поля.
- `home_dashboard_section.dart` — дашборд: `_buildDashboard`, календарь, статистика
- `home_desktop_section.dart` — desktop-специфичные виджеты (уже есть `desktop_shell.dart` — может быть достаточно)
- В `home_page.dart` оставить: `_HomePageState`, координацию, общие поля, `initState`, `_init`, `build`.

### 3. Локализация (i18n)

**Создать структуру:**
```
lib/l10n/
  app_ru.arb
  app_en.arb
```

**`app_ru.arb`:**
```json
{
  "@@locale": "ru",
  "appTitle": "Задачи",
  "newTask": "Новая задача",
  "editTask": "Редактирование задачи",
  "taskTitle": "Название",
  "taskDescription": "Описание",
  "taskProject": "Проект",
  "taskGroup": "Группа",
  "taskPriority": "Приоритет",
  "taskStatus": "Статус",
  "taskAssignees": "Ответственные",
  "taskReminders": "Напоминания",
  "taskDuration": "Оценка времени (мин)",
  "taskSave": "Сохранить",
  "taskCancel": "Отмена",
  "taskDelete": "Удалить",
  "noContacts": "Нет контактов",
  "selectProject": "Выберите проект",
  // ... добавить все строки из AppLabels + хардкод-строки из UI
}
```

**`app_en.arb`** — английские аналоги.

**Настройка:**
- `pubspec.yaml`: добавить `flutter_localizations` в dependencies, `generate: true`
- Создать `lib/l10n/app_localizations.dart` (делегат, автогенерация через `flutter gen-l10n`)
- В `lib/app/family_todo_app.dart`: восстановить `localizationsDelegates`, `supportedLocales`, `locale`
- Заменить хардкод-строки во всех UI-файлах на `AppLocalizations.of(context)!.xxx`

### 4. Разбить chat_message_bubble.dart

Сейчас 831 строка. Выделить в `lib/features/chat/`:
- `chat_text_bubble.dart` — `_buildTextBubble`, текстовые сообщения
- `chat_image_bubble.dart` — `_buildImageBubble`, изображения/видео/просмотр
- `chat_sticker_bubble.dart` — `_buildStickerBubble`, стикеры
- `chat_attachment_bubble.dart` — `_buildAttachmentBubble`, файлы/документы
- `chat_voice_bubble.dart` — `_buildVoiceBubble`, голосовые/аудио
- В `chat_message_bubble.dart` оставить `ChatMessageBubble` виджет-диспетчер, выбор типа.

### 5. Widget-тесты

Создать в `test/`:
- `task_editor_sheet_test.dart` — открытие/закрытие sheet, валидация полей
- `tasks_board_test.dart` — Kanban-колонки, перетаскивание, фильтры
- `calendar_view_test.dart` — выбор даты, отображение задач
- `dashboard_view_test.dart` — счётчики, overdue, upcoming

Каждый тест: `flutter_test` + мок `TaskStore` через `ServiceLocator`.

### 6. Unit-тесты сервисов

Создать в `test/`:
- `task_store_test.dart` — CRUD, фильтрация по дате/статусу/проекту, undo/redo
- `sync_api_client_test.dart` — мок HTTP, проверка fallback-путей (несколько URL)
- `task_item_test.dart` — `fromJson`/`toJson` round-trip, `==`/`hashCode`, `copyWith`

### 7. Финальная проверка

```bash
cd C:\Users\user\Desktop\weather\mobile_app
C:\Users\user\tools\flutter\bin\flutter.bat analyze
C:\Users\user\tools\flutter\bin\flutter.bat test
```

Исправить все новые ошибки. Сделать commit + push.

### Важно
- YOLO mode. Авто-push после каждого логического блока.
- Не трогать файлы вне `mobile_app/`.
- Перед правками читать целевые файлы.
- Использовать sub-agents для параллельной работы где уместно.
- Формат коммитов: `refactor:`, `fix:`, `test:`.
