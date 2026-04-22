# Laravel Phase 3 Parity Report

Date: 2026-04-23 (Europe/Moscow)  
Tool: `scripts/compare_backend_parity.py`  
JSON artifact: `docs/phase3_parity_report.json`

## Run Command
```powershell
python scripts/compare_backend_parity.py --out-json docs/phase3_parity_report.json
```

## Compared Targets
- Old backend: `https://familly.nikportfolio.ru/backend_api/public`
- New backend: `http://31.129.97.211`
- Actor profile: `nik`
- API key: `dev-local-key`

## Result Summary
- New backend contract checks: **PASS**
- Old-vs-new direct parity: **old_unavailable** (not comparable)

## Why Not Comparable
Old backend returned no successful API cases during suite run:
- `500` with error:
  - `SQLSTATE[HY000] [1045] Access denied for user 'stitc994_familly'@'s18.link-host.net'`
- `404` on `sync_changes.php` path

This indicates infrastructure/auth/database outage on the old backend environment, not contract mismatch in Laravel.

## New Backend Verification (Passed)
- `GET /health` -> `200`, keys: `ok,time`
- `GET /sync/pull` (or alias) -> `200`, snapshot contract keys present
- `POST /sync/push` -> `200`, `accepted/duplicates/telegram/push/server_time` present
- `GET /sync/changes` -> `200`, changes contract keys present and pushed task visible
- cleanup delete event accepted

## Next Action
Choose one:
1. Restore old backend DB access and rerun old-vs-new parity suite.
2. Accept current evidence (`contract tests + smoke + parity harness`) and move to Phase 4 cutover.
