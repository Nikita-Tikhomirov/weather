# Laravel Migration Progress

Last update: 2026-04-23 (Europe/Moscow)

## Current Mode
- Deployment mode: IP-only (no domain)
- Backend target: `http://31.129.97.211`
- Strategy: phased migration, dual-run ready path

## Phase Status
- [x] Phase 0: contract freeze + migration checklist approved
- [x] Phase 1: VPS prepared, Laravel installed, nginx/php-fpm running on server
- [x] Phase 2: data layer parity in Laravel (tables + domain rules)
- [ ] Phase 3: API compatibility layer (`/sync_*` + `/sync/*`)
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

## Known Constraints
- IP mode currently uses HTTP (no TLS).
- If server IP changes, client configs must be updated.
- Domain + HTTPS can be added later without changing migration phases.

## Next Step (Resume From Here)
Implement Phase 3 (API compatibility layer) on server Laravel app:
1. Add `/sync/push`, `/sync/pull`, `/sync/changes`, `/telegram/events`, `/devices/register`, `/devices/unregister`, retry endpoints.
2. Add legacy-compatible routes (`/sync_push.php`, `/sync_pull.php`, `/sync_changes.php`, etc.) that map to same controllers.
3. Preserve v1 contract:
   `X-Api-Key`, `actor_profile`, idempotency by `event_id`, response fields `server_time/cursor/next_cursor/mode`.
4. Add contract tests for JSON shape parity against current `backend_api`.

## Quick Resume Prompt
If context resets, start with:
"Continue from `docs/laravel_migration_progress.md`, begin Phase 3 API compatibility implementation."
