# Family ToDo Mobile (Android-first)

Flutter-клиент с offline-first синхронизацией.

## Что уже есть

- локальная БД (`sqflite`) для задач;
- очередь `pending_events` для офлайн-изменений;
- sync push/pull с backend API;
- Kanban-экран по статусам (`todo`, `in_progress`, `in_review`, `done`);
- базовый приятный Material 3 дизайн.

## Запуск

```bash
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=https://your-domain.tld \
  --dart-define=API_KEY=YOUR_API_KEY
```

