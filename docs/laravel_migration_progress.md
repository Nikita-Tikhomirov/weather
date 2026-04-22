# Laravel Migration Progress

Last update: 2026-04-23 (Europe/Moscow)

## Current Mode
- Deployment mode: IP-only (no domain)
- Backend target: `http://31.129.97.211`
- Strategy: phased migration, dual-run ready path
- Runtime DB: MySQL on VPS (`DB_CONNECTION=mysql`)

## Phase Status
- [x] Phase 0: contract freeze + migration checklist approved
- [x] Phase 1: VPS prepared, Laravel installed, nginx/php-fpm running on server
- [x] Phase 2: data layer parity in Laravel (tables + domain rules)
- [~] Phase 3: API compatibility layer (`/sync_*` + `/sync/*`) in progress
- [ ] Phase 4: dual-run verification + client cutover sequence

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

## Known Constraints
- IP mode currently uses HTTP (no TLS).
- If server IP changes, client configs must be updated.
- Domain + HTTPS can be added later without changing migration phases.

## Next Step (Resume From Here)
Implement Phase 3 (API compatibility layer) on server Laravel app:
1. Decide cutover policy with current blocker:
   - restore old backend DB access and run full old-vs-new parity,
   - or accept `contract-only + smoke` evidence and close Phase 3.
2. Keep outbox behavior `disabled` for MVP sync-only scope (as agreed), or explicitly enable behind feature flag in a dedicated sub-phase.
3. Start Phase 4 dual-run/cutover checklist after decision above.

## Quick Resume Prompt
If context resets, start with:
"Continue from `docs/laravel_migration_progress.md`, continue Phase 3 parity tests and outbox behavior."
