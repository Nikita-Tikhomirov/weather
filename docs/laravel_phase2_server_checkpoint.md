# Laravel Phase 2 Server Checkpoint

Date: 2026-04-23 (Europe/Moscow)  
Server: `31.129.97.211`  
Laravel root: `/var/www/adebechigef`

## Implemented Scope
- Data-layer parity migration for sync domain tables:
  - `tasks`
  - `family_tasks`
  - `sync_events`
  - `telegram_outbox`
  - `device_tokens`
  - `push_outbox`
- Domain rules/helpers port:
  - allowed profiles/adults/workflow
  - task/family permission guards
  - recipients routing logic
  - cursor next-value helper
  - payload signature helper with volatile fields ignored
- Eloquent models added for all six sync tables.
- Unit tests for rules/cursor/signature added and passed.

## Server Files Created/Updated
- `database/migrations/2026_04_23_000100_create_sync_domain_tables.php`
- `app/Domain/Sync/Cursor.php`
- `app/Domain/Sync/PayloadSignature.php`
- `app/Domain/Sync/Profiles.php`
- `app/Domain/Sync/SyncRules.php`
- `app/Models/Task.php`
- `app/Models/FamilyTask.php`
- `app/Models/SyncEvent.php`
- `app/Models/TelegramOutbox.php`
- `app/Models/DeviceToken.php`
- `app/Models/PushOutbox.php`
- `tests/Unit/SyncRulesTest.php`
- `tests/Unit/CursorAndSignatureTest.php`

## Integrity Hashes (sha256)
```text
a859e9ab0c08f54885d29f894d3d8fa04257bbc7399749d263138e470313668d  database/migrations/2026_04_23_000100_create_sync_domain_tables.php
35355b1545dff2f9514fb1a5169d6c36b45ea682e99ef8fba7e8c21748c139e6  app/Domain/Sync/Cursor.php
5750d40c61f571249160ca82f6f110c9511fcb1b2fd77e7b55610264d71097a3  app/Domain/Sync/PayloadSignature.php
a51bc135118becc2086c1c36bad897b7196e9635cb3e29261cc431ad9e253f03  app/Domain/Sync/Profiles.php
798bfa4c380bcaa688303c4fd487a55fbc4f50e0f969e8335d84c0e65b043bc9  app/Domain/Sync/SyncRules.php
0e81ea749538273a819436bc34447505f47ed7cc0813196910c7ddcdec7deec6  app/Models/Task.php
66ff8a51da06601f3efe35283fc93885a2046805b05921c794312c30cf243174  app/Models/FamilyTask.php
b8f1d9ef28e695a7f179b01ef11a714664180d920b748bfc18d61f2fe83a2402  app/Models/SyncEvent.php
437fb89feee61aa469747966aded59d0f77932d59ded1745babbc8c069416d5a  app/Models/TelegramOutbox.php
4f4608f60ef06d318f40a7406639fce76bb22031a25a890b78b0dfa59a2837e8  app/Models/DeviceToken.php
9e44cfa36353ad65e33f005689e705b6b53ec15400f2389abaa3b779b82e4df2  app/Models/PushOutbox.php
f8cf8098416a0ca06afcde2bec2308ab53e47607a09af5df919ee21643bf1906  tests/Unit/SyncRulesTest.php
8d990ec08bfc3de15d5701fc1e0d9f08df63a3fb269b0c47c2c0551c767db3c5  tests/Unit/CursorAndSignatureTest.php
```

## Verification Commands
```bash
cd /var/www/adebechigef
php artisan migrate --force
php artisan test tests/Unit/SyncRulesTest.php tests/Unit/CursorAndSignatureTest.php
php artisan migrate:status
```

## Verification Result
- Migration applied:
  - `2026_04_23_000100_create_sync_domain_tables` -> `Ran` (Batch 2)
- Tests:
  - `PASS` 9 tests, 12 assertions

## Resume Marker
Next implementation target is **Phase 3 API compatibility layer** (routes/controllers/contracts).
