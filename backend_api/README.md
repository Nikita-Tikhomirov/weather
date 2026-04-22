# Family ToDo Backend API (PHP + MySQL)

Backend синхронизации для мобильного приложения и Telegram-бота.

В этом хостинг-профиле используются плоские endpoint-файлы (`*.php`), чтобы не зависеть от nginx rewrite.

## Что реализовано

- `POST /sync_push.php` — прием батча изменений (идемпотентно по `event_id`)
- `GET /sync_pull.php?since=...` — выдача изменений задач/семейных задач
- `POST /telegram_events.php` — прием событий из Telegram-бота
- `POST /telegram_outbox_retry.php` — повторная отправка pending/failed событий в Telegram
- `POST /devices_register.php` — регистрация FCM token устройства
- `POST /devices_unregister.php` — деактивация FCM token устройства
- `POST /push_outbox_retry.php` — повторная отправка pending/failed app push в FCM
- права:
  - личные задачи редактирует только владелец;
  - семейные задачи редактируют только `nik` и `nastya`.
- outbox-очередь в БД для гарантий доставки в Telegram

## Быстрый деплой на shared hosting

1. Создайте БД MySQL и импортируйте `sql/schema.sql`.
2. Скопируйте папку `backend_api` на хостинг.
3. Скопируйте `config.example.php` в `config.php` и заполните.
4. Убедитесь, что web root указывает на `backend_api/public`.

## Формат API-ключа

Все POST-запросы должны содержать заголовок:

`X-Api-Key: <YOUR_API_KEY>`

## FCM config

В `config.php` заполните:

- `fcm.project_id`
- `fcm.service_account_email`
- `fcm.private_key` (как строка PEM, `\n` допустимы)

## Пример push

```json
{
  "actor_profile": "nik",
  "source": "mobile",
  "events": [
    {
      "event_id": "d4b95db0-92b7-43d2-8f3f-ec3a1c0f8fd6",
      "entity": "task",
      "action": "upsert",
      "payload": {
        "id": "t-1001",
        "owner_key": "nik",
        "is_family": false,
        "title": "Купить корм",
        "details": "",
        "due_date": "2026-04-21",
        "time": "19:00",
        "workflow_status": "todo",
        "priority": "medium",
        "tags": ["дом"],
        "participants": [],
        "duration_minutes": 0,
        "updated_at": "2026-04-20T20:00:00",
        "version": 1
      },
      "happened_at": "2026-04-20T20:00:00"
    }
  ]
}
```

## Delivery contract (current)

- Telegram delivery is the only active notification channel for task changes.
- Personal task events are visible only to the selected owner profile.
- Family task events are visible to all four profiles: `nik`, `nastya`, `misha`, `arisha`.
- `POST /sync_push.php` processes Telegram outbox immediately after accepting events.
- Full sync fallback stays at 10 minutes; delta sync is used for fast updates between full pulls.
