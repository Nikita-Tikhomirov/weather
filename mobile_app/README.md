# Family ToDo Mobile (Android-first)

Flutter-клиент с offline-first синхронизацией.

## Что уже есть

- локальная БД (`sqflite`) для задач;
- очередь `pending_events` для офлайн-изменений;
- sync push/pull с backend API;
- FCM app-to-app push:
  - регистрация device token в backend (`/devices/register`);
  - обновление token через `onTokenRefresh`;
  - foreground banner + sync;
  - tap по push запускает sync;
- Kanban-экран по статусам (`todo`, `in_progress`, `in_review`, `done`);
- базовый приятный Material 3 дизайн.

## Запуск

```bash
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=https://your-domain.tld \
  --dart-define=API_KEY=YOUR_API_KEY
```

## Firebase setup (Android)

1. Скопируйте ваш `google-services.json` в `mobile_app/android/app/google-services.json`.
2. Проверьте `applicationId` в `mobile_app/android/app/build.gradle` и package в `google-services.json`.
3. Включите Firebase Cloud Messaging в проекте Firebase.
