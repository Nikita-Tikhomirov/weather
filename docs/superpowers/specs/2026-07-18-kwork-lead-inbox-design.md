# Kwork Lead Inbox Design

## Goal

Replace email delivery in the local Kwork lead funnel with a mobile inbox where Nikita can inspect, edit, approve, reject, and track each lead.

## Architecture

Laravel on the existing VPS is the authoritative store. A `lead` record keeps the structured Kwork data and an audit trail; the existing mobile chat renders a system conversation named `Заказы` and opens a dedicated editable lead card. FCM signals lead changes immediately, while API polling and chat sync recover missed notifications.

The desktop funnel is the only Kwork executor because it owns the authenticated Chrome session. It upserts discovered leads to Laravel. A mobile approval creates a durable command; the desktop client consumes that command once, submits the prepared Kwork proposal, then reports either `sent` or `failed` to Laravel.

## Lead Contract

Each lead has a stable external key (`kwork:<local_lead_id>`), title, source URL, raw brief, AI summary, attachment report, draft reply, proposal title, price, duration, Kwork offer count, timestamps, version, and status.

Allowed statuses are `new`, `edited`, `approved`, `sending`, `sent`, `rejected`, and `failed`. The server validates transitions, stores every change in an audit table, and treats an already-approved or sent lead idempotently. `approved` is the explicit user approval for external submission.

## API

The Laravel API exposes a guarded lead namespace for ingestion, list/detail, edit, approval, rejection, command pull, and executor result reporting. The desktop funnel uses an integration API key from its local `.env`; the mobile app continues using its existing API key and profile identity. Responses include the current version so the UI can refresh after edits or actions.

## Mobile Experience

The chat list contains the system conversation `Заказы`. Every new or changed lead is visible as a compact, high-signal card: title, time, offer count, status, price/duration, source link, and summary. Opening it shows raw task data, attachment processing status, an editable proposal, and explicit `Одобрить` / `Отклонить` actions. Existing person and group conversations are unchanged.

## Failure Handling

If the desktop agent is offline, an approved lead stays approved and appears as waiting for the PC. A failed Kwork action returns a readable error and allows a deliberate re-approval after editing. The executor atomically claims only approved commands and never sends a lead that has already reached `sending` or `sent`.

## Scope Boundaries

No change to Flutter package/signing, calling, audio, or Telecom code. SMTP/IMAP configuration, email commands, mail GUI controls, and email approval routes are removed from the funnel. Secrets remain only in local environment files and VPS configuration.
