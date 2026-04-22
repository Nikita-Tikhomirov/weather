# Laravel Migration Progress

Last update: 2026-04-23 (Europe/Moscow)

## Current Mode
- Deployment mode: IP-only (no domain)
- Backend target: `http://31.129.97.211`
- Strategy: phased migration, dual-run ready path

## Phase Status
- [x] Phase 0: contract freeze + migration checklist approved
- [x] Phase 1: VPS prepared, Laravel installed, nginx/php-fpm running on server
- [ ] Phase 2: data layer parity in Laravel (tables + domain rules)
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

## Known Constraints
- IP mode currently uses HTTP (no TLS).
- If server IP changes, client configs must be updated.
- Domain + HTTPS can be added later without changing migration phases.

## Next Step (Resume From Here)
Implement Phase 2 in repo:
1. Create Laravel migrations/models mirroring `tasks`, `family_tasks`, `sync_events`, `telegram_outbox`, `device_tokens`, `push_outbox`.
2. Port auth/routing constraints (`actor_profile`, roles, idempotency).
3. Add parity tests for dedup/cursor/permissions before exposing API endpoints.

## Quick Resume Prompt
If context resets, start with:
"Continue from `docs/laravel_migration_progress.md`, begin Phase 2 data-layer parity implementation."
