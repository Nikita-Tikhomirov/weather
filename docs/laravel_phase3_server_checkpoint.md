# Laravel Phase 3 Server Checkpoint (In Progress)

Date: 2026-04-23 (Europe/Moscow)  
Server: `31.129.97.211`  
Laravel root: `/var/www/adebechigef`

## Implemented Scope
- Added API routing pipeline in Laravel bootstrap with `apiPrefix: ''` (no `/api` prefix).
- Added API key middleware (`X-Api-Key`) with v1 compatibility behavior (`dev-local-key` bypass).
- Added sync compatibility controller + repository:
  - `health`
  - `sync pull/changes`
  - `sync push`
  - `telegram events`
  - `devices register/unregister`
  - retry endpoints (`telegram_outbox_retry`, `push_outbox_retry`) returning safe `disabled` contract.
- Added dual route styles:
  - clean routes (`/sync/pull`, `/sync/push`, `/sync/changes`, etc.)
  - legacy aliases (`/sync_pull.php`, `/sync_push.php`, `/sync_changes.php`, etc.).
- Updated nginx so legacy `*.php` aliases route into Laravel instead of filesystem PHP lookup.

## Server Files Created/Updated
- `bootstrap/app.php`
- `config/sync.php`
- `app/Http/Middleware/RequireApiKey.php`
- `app/Http/Controllers/SyncController.php`
- `app/Domain/Sync/SyncRepository.php`
- `routes/api.php`
- `/etc/nginx/sites-available/adebechigef`
- `tests/Feature/SyncApiContractTest.php`

## Integrity Hashes (sha256)
```text
f7a03456e32cb3a3d9ff3f1673631c72fb552550ce6d304d919637bcf44d7003  bootstrap/app.php
efe446e43c5ad41fc2245595c97dbc0dca6c0ac64742844e8c896df0155aa596  config/sync.php
d03f1d2011d7e2e7c50e6c2a0f1c14a6c54364fda5e4fe221f7f567bb866d5cf  app/Http/Middleware/RequireApiKey.php
761c1401e95d8cb6fd1c84b5d18a1e4fae11a625bd65ddb8dfe754ffe919adc7  app/Http/Controllers/SyncController.php
ec6aec36f67a97e7ae36db7c545d3c372c38fa03f87b5eb4a81afbef022d0302  app/Domain/Sync/SyncRepository.php
a910379cbafb53b99b8d7d86d5cf573ad994c719ef2407608334caed9ead7069  routes/api.php
40a8ae3d9a18bd23b8cfbf8463390e2a16cb58e9fd823e5bf74159af4be945ef  /etc/nginx/sites-available/adebechigef
b826a6787dae1d92a8c42a73ce8995eba9d85e6a878ca8a581fa280bca82c9b0  tests/Feature/SyncApiContractTest.php
```

## Runtime Verification
Executed:
```bash
cd /var/www/adebechigef
php artisan optimize:clear
php artisan route:list | grep -E 'health|sync|telegram|devices|outbox'
```

Route snapshot includes:
- `GET /health`
- `GET /sync/pull`, `GET /sync/changes`
- `GET /sync_pull.php`, `GET /sync_changes.php`
- `POST /sync/push`, `POST /sync_push.php`
- `POST /telegram/events`, `POST /telegram_events.php`
- `POST /devices/register`, `POST /devices/unregister`
- `POST /devices_register.php`, `POST /devices_unregister.php`
- `POST /telegram/outbox/retry`, `POST /push/outbox/retry`
- `POST /telegram_outbox_retry.php`, `POST /push_outbox_retry.php`

Smoke checks from client side:
- `GET http://31.129.97.211/health` -> `{"ok":true,...}`
- `GET /sync_pull.php` with key -> valid snapshot JSON
- `POST /sync_push.php` with event -> `accepted=1`
- `GET /sync/changes` and `GET /sync_changes.php` -> include pushed task and cursor contract
- cleanup event (delete) accepted.

Automated HTTP contract tests:
```bash
cd /var/www/adebechigef
php artisan test tests/Feature/SyncApiContractTest.php --debug
```
- Result: `PASS` (3 tests, 28 assertions).

## Remaining To Finish Phase 3
- Add automated contract tests (golden JSON shape and status-code parity).
- Decide and implement outbox behavior mode:
  - keep `disabled` (current MVP), or
  - enable full processing under feature flags.
- Produce parity report vs old `backend_api` on controlled dataset.

## Resume Marker
Continue from `docs/laravel_migration_progress.md` and execute **Phase 3 parity tests/outbox decision**.
