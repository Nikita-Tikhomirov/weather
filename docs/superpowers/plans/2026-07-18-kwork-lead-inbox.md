# Kwork Lead Inbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Put Kwork leads into an editable, approval-driven mobile inbox and replace the funnel's email workflow.

**Architecture:** Laravel owns structured lead records, audits, API actions, and FCM notifications. Flutter presents a dedicated system inbox and lead card. The local Python funnel syncs leads and executes only server-approved Kwork commands from the logged-in Chrome session.

**Tech Stack:** Laravel/PHP/MySQL, Flutter/Dart, Python 3.10, SQLite, pytest, PHPUnit.

## Global Constraints

- Keep FCM as a notification accelerator; API state is authoritative.
- Store all integration keys in local environment configuration only.
- Do not change package id, signing, call audio, or Telecom behavior.
- The Kwork browser is local; no external submission can be duplicated.

---

### Task 1: Laravel lead domain and HTTP contract

**Files:**
- Create: `laravel_backend_vps/database/migrations/*_create_kwork_leads_tables.php`
- Create: `laravel_backend_vps/app/Domain/Leads/LeadRepository.php`
- Create: `laravel_backend_vps/app/Http/Controllers/LeadController.php`
- Modify: `laravel_backend_vps/routes/api.php`
- Test: `laravel_backend_vps/tests/Feature/LeadApiTest.php`

- [ ] Write failing feature tests for idempotent ingestion, edit, approval, rejection, claiming, and result reporting.
- [ ] Run the Laravel test file and confirm routes are absent.
- [ ] Implement the migration, repository, controller, guarded routes, status validation, audit rows, and FCM enqueue.
- [ ] Re-run the feature tests and commit `feat: add Kwork lead API`.

### Task 2: Mobile lead data source and cards

**Files:**
- Create: `mobile_app/lib/models/lead_models.dart`
- Create: `mobile_app/lib/contracts/lead_api.dart`
- Create: `mobile_app/lib/services/lead_api_client.dart`
- Create: `mobile_app/lib/features/leads/lead_inbox_page.dart`
- Create: `mobile_app/lib/features/leads/lead_detail_sheet.dart`
- Modify: `mobile_app/lib/features/chat/messenger_page.dart`
- Modify: `mobile_app/lib/services/service_locator.dart`
- Test: `mobile_app/test/services/lead_api_client_test.dart`
- Test: `mobile_app/test/features/leads/lead_models_test.dart`

- [ ] Write failing Dart tests for model decoding and approval/edit payloads.
- [ ] Run the focused tests and confirm the API surface is absent.
- [ ] Implement client, inbox, detail editor, explicit actions, and route from the existing chat experience.
- [ ] Run focused tests, `flutter analyze`, and commit `feat: add mobile Kwork lead inbox`.

### Task 3: Funnel API synchronization and email removal

**Files:**
- Create: `src/app/lead_api_client.py`
- Modify: `src/app/config.py`
- Modify: `src/app/main.py`
- Modify: `src/app/gui.py`
- Modify: `src/app/storage.py`
- Delete: `src/app/email_client.py`
- Modify: `.env.example`, `README.md`, `tests/test_config.py`, `tests/test_main.py`, `tests/test_gui.py`
- Create: `tests/test_lead_api_client.py`

- [ ] Write failing pytest cases for lead payload sync, command polling, and missing integration configuration.
- [ ] Run focused pytest and confirm the client is unavailable.
- [ ] Implement authenticated API client, upsert after lead analysis, approved-command consumption, result reporting, and removal of all SMTP/IMAP paths.
- [ ] Run focused pytest and commit `feat: sync Kwork leads with mobile inbox`.

### Task 4: End-to-end verification and deployment

**Files:**
- Modify: `README.md`
- Modify: `weather/README.md` or deployment documentation as needed

- [ ] Run Python tests, compile checks, harness smoke, Laravel tests, Flutter tests, and Flutter analyze.
- [ ] Deploy the Laravel API through the project deployment path without committing secrets.
- [ ] Manually verify: new local lead -> VPS -> mobile card -> edit -> approve -> desktop command becomes visible -> result status updates.
- [ ] Commit documentation, push both repositories, inspect CI, and record the deployed API contract.
