# Family ToDo Backend API (PHP + MySQL)

Backend синхронизации для мобильного приложения и Telegram-бота.

## Что реализовано

- `POST /sync/push` — прием батча изменений (идемпотентно по `event_id`)
- `GET /sync/pull?since=...` — выдача изменений задач/семейных задач
- `POST /telegram/events` — прием событий из Telegram-бота
- `POST /telegram/outbox/retry` — повторная отправка pending/failed событий в Telegram
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

