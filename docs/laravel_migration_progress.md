# Laravel Migration Progress

Last update: 2026-05-15 (Europe/Moscow)

## Current Mode
- Deployment mode: IP-only (no domain)
- Backend target: `http://31.129.97.211`
- Strategy: phased migration, dual-run ready path
- Runtime DB: MySQL on VPS (`DB_CONNECTION=mysql`)

## Phase Status
- [x] Phase 0: contract freeze + migration checklist approved
- [x] Phase 1: VPS prepared, Laravel installed, nginx/php-fpm running on server
- [x] Phase 2: data layer parity in Laravel (tables + domain rules)
- [x] Phase 3: API compatibility layer (`/sync_*` + `/sync/*`) + push outbox wiring complete
- [~] Phase 4: dual-run verification + client cutover sequence

## Completed In This Checkpoint
1. Switched desktop/backend runtime default to VPS IP:
   - `sync_runtime.py` default `backend_url` -> `http://31.129.97.211`
2. Switched Flutter API default to VPS IP:
   - `mobile_app/lib/main.dart` `API_BASE_URL` default -> `http://31.129.97.211`
3. Enabled Android cleartext traffic for HTTP IP mode:
   - `mobile_app/android/app/src/main/AndroidManifest.xml`
4. Added this progress file to preserve resume point between chats.
5. Implemented Phase 2 on server Laravel app (`/var/www/adebechigef`):
   - created migration `2026_04_23_000100_create_sync_domain_tables.php` for:
     `tasks`, `family_tasks`, `sync_events`, `telegram_outbox`, `device_tokens`, `push_outbox`
   - added domain rules/helpers:
     `App\Domain\Sync\{Profiles,SyncRules,Cursor,PayloadSignature}`
   - added Eloquent models:
     `Task`, `FamilyTask`, `SyncEvent`, `TelegramOutbox`, `DeviceToken`, `PushOutbox`
   - added unit tests:
     `tests/Unit/SyncRulesTest.php`, `tests/Unit/CursorAndSignatureTest.php`
   - validation passed:
     `php artisan migrate --force` and `php artisan test ...` (9 tests passed)
   - file hashes and exact server snapshot:
     `docs/laravel_phase2_server_checkpoint.md`
6. Implemented Phase 3 core API compatibility on server Laravel app:
   - added API middleware alias `sync.apikey` (`X-Api-Key` validation with `dev-local-key` compatibility)
   - added routes for both route styles:
     `/sync/*`, `/telegram/*`, `/devices/*`, `/push/outbox/retry`
     and legacy aliases:
     `/sync_pull.php`, `/sync_push.php`, `/sync_changes.php`,
     `/telegram_events.php`, `/telegram_outbox_retry.php`,
     `/devices_register.php`, `/devices_unregister.php`, `/push_outbox_retry.php`
   - added controller and repository for contract-compatible sync logic:
     idempotency by `event_id`, actor permissions, pull modes (`snapshot/changes`), cursor/next_cursor
   - nginx updated to rewrite legacy `*.php` aliases into Laravel router
   - smoke validation passed:
     - `GET /health`
     - `GET /sync_pull.php` with key
     - `POST /sync_push.php` upsert/delete
     - `GET /sync/changes` and `GET /sync_changes.php`
   - added automated Laravel feature contract tests:
     - `tests/Feature/SyncApiContractTest.php` (`PASS`, 3 tests / 28 assertions)
   - full file and command snapshot:
     `docs/laravel_phase3_server_checkpoint.md`
7. Added automated parity harness in repo:
   - `scripts/compare_backend_parity.py`
   - output report:
     - `docs/phase3_parity_report.json`
     - `docs/laravel_phase3_parity_report.md`
   - result:
     - new Laravel backend contract: `PASS`
     - old backend comparison: `old_unavailable` (DB access denied on old host)
8. Switched Laravel runtime DB from SQLite to MySQL on VPS:
   - installed `mariadb-server` + `php8.3-mysql`
   - created MySQL database/user for app runtime
   - updated Laravel `.env` on server to `DB_CONNECTION=mysql`
   - ran `php artisan migrate --force` on MySQL (all migrations `Ran`)
   - smoke verified after switch (`/health`, `/sync_push.php`, `/sync_changes.php`)
9. Implemented server-side mobile push pipeline in Laravel (FCM-ready):
   - added push config: `laravel_backend_vps/config/push.php`
   - added push gateway contract + FCM HTTP v1 implementation:
     - `App\Contracts\PushGateway`
     - `App\Services\Push\FcmPushGateway`
   - added message factory + outbox processor:
     - `App\Services\Push\PushMessageFactory`
     - `App\Services\Push\PushOutboxService`
   - wired DI binding in `AppServiceProvider`
   - updated `SyncController`:
     - enqueue push records per accepted event
     - process due push outbox items in `/sync_push.php`, `/telegram_events.php`
     - enabled `/push_outbox_retry.php` handler with real processing response
   - added tests:
     - `tests/Unit/PushOutboxServiceTest.php`
   - server verification:
     - `php artisan test --testsuite=Unit,Feature` -> `PASS` (16 tests, 50 assertions)
     - live smoke `/sync_push.php` and `/push_outbox_retry.php` -> push contract active, currently `disabled=true` until FCM credentials are set in `.env`
10. FCM credentials configured and push pipeline verified (2026-05-15):
   - FCM credentials in `.env`: `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, `FCM_PRIVATE_KEY`
   - `php artisan optimize:clear` executed, all caches rebuilt
   - push outbox stats: 639 sent, 31 failed (invalid device tokens, properly marked `unregistered`)
   - device_tokens: 33 registered devices, inactive tokens correctly marked
   - push_outbox retry endpoint: active, returns `{"ok":true,"result":{"disabled":false,...}}`
   - FCM key format: stored with escaped `\n` in `.env`, converted to real newlines by `FcmPushGateway::privateKey()` via `str_replace('\n', "\n", ...)`
11. Full smoke verification (2026-05-15):
   - `GET /health` -> `{"ok":true}` PASS
   - `GET /sync/pull` (snapshot) -> PASS, returns tasks with `owner_key` field
   - `GET /sync/pull.php` (legacy) -> PASS
   - `GET /sync/changes?cursor=...` -> PASS
   - `GET /sync_changes.php` (legacy) -> PASS
   - `POST /devices/register` with `actor_profile=nik` -> PASS (`{"ok":true,...}`)
   - `POST /push_outbox_retry.php` -> PASS
   - API auth: `RequireApiKey` middleware active, `dev-local-key` bypass works, family-mode (empty `sync.api_key`) passes through
   - `php artisan test --testsuite=Unit,Feature` -> 40 passed, 187 assertions (all PASS)
   - DB schema verified: `tasks` uses `owner_key`, `device_tokens` uses `profile_key`, `family_tasks` uses `participants_json`
   - 404 on `/health.php` is expected (nginx rewrite covers only legacy sync endpoints, not health)

## Known Constraints
- IP mode currently uses HTTP (no TLS).
- If server IP changes, client configs must be updated.
- Domain + HTTPS can be added later without changing migration phases.

## Next Step (Resume From Here)
1. Phase 4 dual-run verification:
   - Verify desktop Flutter client (`family_todo_mobile.exe`) syncs correctly against VPS Laravel backend
   - Verify Android APK syncs correctly against VPS
   - Verify Telegram bot outbox works through Laravel backend
   - Verify push delivery end-to-end (APK receives FCM notification on task change)
2. Client cutover:
   - Once dual-run verification passes, switch all clients to use only Laravel backend
   - Archive or remove old `backend_api/` PHP flat-file endpoints
3. Domain + HTTPS (optional, independent of phases):
   - Configure domain for VPS IP
   - Enable Let's Encrypt TLS
   - Remove `android:usesCleartextTraffic="true"` from AndroidManifest

## Quick Resume Prompt
If context resets, start with:
"Continue from `docs/laravel_migration_progress.md`, begin Phase 4 dual-run verification."
