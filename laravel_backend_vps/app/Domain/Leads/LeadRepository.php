<?php

namespace App\Domain\Leads;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use InvalidArgumentException;

final class LeadRepository
{
    private const EDITABLE_STATUSES = ['new', 'edited', 'failed'];
    private const MONITOR_COMMANDS = ['start', 'stop', 'scan'];

    public function profileForPhone(string $phone): string
    {
        $normalized = preg_replace('/\D+/', '', $phone) ?: '';
        $profile = DB::table('messenger_users')
            ->where('phone_normalized', $normalized)
            ->value('profile_key');
        if (!is_string($profile) || trim($profile) === '') {
            throw new InvalidArgumentException('Owner phone is not registered in the mobile app');
        }
        return trim($profile);
    }

    public function ingest(array $input, string $ownerProfile): array
    {
        $externalKey = $this->required($input, 'external_key');
        $title = $this->required($input, 'title');
        $now = $this->nowIso();

        return DB::transaction(function () use ($input, $ownerProfile, $externalKey, $title, $now): array {
            $existing = DB::table('kwork_leads')->where('external_key', $externalKey)->first();
            $values = $this->ingestValues($input, $ownerProfile, $title, $now);
            if ($existing === null) {
                $id = DB::table('kwork_leads')->insertGetId([
                    'external_key' => $externalKey,
                    ...$values,
                    'status' => 'new',
                    'executor_id' => null,
                    'executor_claimed_at' => null,
                    'last_error' => '',
                    'version' => 1,
                    'created_at' => $now,
                    'updated_at' => $now,
                    'deleted_at' => null,
                ]);
                $this->audit($id, '', 'ingested', ['external_key' => $externalKey]);
                return $this->find($id);
            }

            $nextStatus = in_array((string)$existing->status, ['sent', 'sending'], true)
                ? (string)$existing->status
                : 'new';
            DB::table('kwork_leads')->where('id', $existing->id)->update([
                ...$values,
                'status' => $nextStatus,
                'version' => (int)$existing->version + 1,
                'updated_at' => $now,
            ]);
            $this->audit((int)$existing->id, '', 'refreshed', ['external_key' => $externalKey]);
            return $this->find((int)$existing->id);
        });
    }

    public function listForOwner(string $ownerProfile): array
    {
        return DB::table('kwork_leads')
            ->where('owner_profile_key', $ownerProfile)
            ->whereNull('deleted_at')
            ->orderByDesc('updated_at')
            ->orderByDesc('id')
            ->get()
            ->map(fn (object $row): array => $this->map($row))
            ->all();
    }

    public function createForOwner(string $ownerProfile, array $input): array
    {
        $title = $this->required($input, 'title');
        $now = $this->nowIso();
        $values = $this->ingestValues($input, $ownerProfile, $title, $now);
        $id = DB::table('kwork_leads')->insertGetId([
            'external_key' => 'manual:'.$ownerProfile.':'.Str::uuid(),
            ...$values,
            'status' => 'new',
            'executor_id' => null,
            'executor_claimed_at' => null,
            'last_error' => '',
            'version' => 1,
            'created_at' => $now,
            'updated_at' => $now,
            'deleted_at' => null,
        ]);
        $this->audit($id, $ownerProfile, 'created', ['source' => $values['source']]);
        return $this->find($id);
    }

    public function findForOwner(int $leadId, string $ownerProfile): array
    {
        return $this->map($this->findRowForOwner($leadId, $ownerProfile));
    }

    public function edit(int $leadId, string $actor, array $values): array
    {
        return DB::transaction(function () use ($leadId, $actor, $values): array {
            $lead = $this->findRowForOwner($leadId, $actor);
            if (!in_array((string)$lead->status, self::EDITABLE_STATUSES, true)) {
                throw new InvalidArgumentException('Lead cannot be edited in its current status');
            }
            $update = $this->editableValues($values);
            if ($update === []) {
                throw new InvalidArgumentException('No editable lead fields supplied');
            }
            $now = $this->nowIso();
            DB::table('kwork_leads')->where('id', $leadId)->update([
                ...$update,
                'status' => 'edited',
                'version' => (int)$lead->version + 1,
                'updated_at' => $now,
            ]);
            $this->audit($leadId, $actor, 'edited', array_keys($update));
            return $this->find($leadId);
        });
    }

    public function approve(int $leadId, string $actor): array
    {
        return DB::transaction(function () use ($leadId, $actor): array {
            $lead = $this->findRowForOwner($leadId, $actor);
            if ((string)$lead->status === 'approved') {
                return $this->map($lead);
            }
            if (!in_array((string)$lead->status, self::EDITABLE_STATUSES, true)) {
                throw new InvalidArgumentException('Lead cannot be approved in its current status');
            }
            DB::table('kwork_leads')->where('id', $leadId)->update([
                'status' => 'approved',
                'last_error' => '',
                'version' => (int)$lead->version + 1,
                'updated_at' => $this->nowIso(),
            ]);
            $this->audit($leadId, $actor, 'approved', []);
            return $this->find($leadId);
        });
    }

    public function reject(int $leadId, string $actor): array
    {
        return DB::transaction(function () use ($leadId, $actor): array {
            $lead = $this->findRowForOwner($leadId, $actor);
            if ((string)$lead->status === 'rejected') {
                return $this->map($lead);
            }
            if (in_array((string)$lead->status, ['sending', 'sent'], true)) {
                throw new InvalidArgumentException('Lead cannot be rejected in its current status');
            }
            DB::table('kwork_leads')->where('id', $leadId)->update([
                'status' => 'rejected',
                'version' => (int)$lead->version + 1,
                'updated_at' => $this->nowIso(),
            ]);
            $this->audit($leadId, $actor, 'rejected', []);
            return $this->find($leadId);
        });
    }

    public function delete(int $leadId, string $actor): array
    {
        return DB::transaction(function () use ($leadId, $actor): array {
            $lead = $this->findRowForOwner($leadId, $actor);
            if ((string)$lead->status === 'sending') {
                throw new InvalidArgumentException('Lead cannot be deleted while sending');
            }
            DB::table('kwork_leads')->where('id', $leadId)->update([
                'deleted_at' => $this->nowIso(),
                'version' => (int)$lead->version + 1,
                'updated_at' => $this->nowIso(),
            ]);
            $this->audit($leadId, $actor, 'deleted', []);
            $mapped = $this->map($lead);
            $mapped['status'] = 'deleted';
            return $mapped;
        });
    }

    public function approvedCommands(): array
    {
        return DB::table('kwork_leads')
            ->where('status', 'approved')
            ->whereNull('deleted_at')
            ->orderBy('updated_at')
            ->get()
            ->map(fn (object $row): array => $this->map($row))
            ->all();
    }

    public function monitorForOwner(string $ownerProfile): array
    {
        return DB::transaction(function () use ($ownerProfile): array {
            return $this->mapMonitor($this->findOrCreateMonitor($ownerProfile, true));
        });
    }

    public function monitorForPhone(string $phone): array
    {
        if ($phone === '') {
            throw new InvalidArgumentException('Owner phone is required');
        }
        return $this->monitorForOwner($this->profileForPhone($phone));
    }

    public function commandMonitor(string $ownerProfile, string $command): array
    {
        $command = trim(mb_strtolower($command));
        if (!in_array($command, self::MONITOR_COMMANDS, true)) {
            throw new InvalidArgumentException('Unsupported monitor command');
        }

        return DB::transaction(function () use ($ownerProfile, $command): array {
            $monitor = $this->findOrCreateMonitor($ownerProfile, true);
            $now = $this->nowIso();
            $update = match ($command) {
                'start' => ['desired_state' => 'running', 'scan_requested_at' => $now],
                'stop' => ['desired_state' => 'stopped', 'scan_requested_at' => null],
                'scan' => ['scan_requested_at' => $now],
            };
            DB::table('kwork_monitor_controls')->where('id', $monitor->id)->update([
                ...$update,
                'updated_at' => $now,
            ]);
            return $this->mapMonitor($this->findMonitor((int)$monitor->id));
        });
    }

    public function heartbeatMonitor(string $phone, string $executorId, string $scanEvent, string $error): array
    {
        if ($phone === '' || $executorId === '') {
            throw new InvalidArgumentException('Owner phone and executor id are required');
        }
        if (!in_array($scanEvent, ['', 'started', 'finished'], true)) {
            throw new InvalidArgumentException('Unsupported monitor scan event');
        }

        return DB::transaction(function () use ($phone, $executorId, $scanEvent, $error): array {
            $ownerProfile = $this->profileForPhone($phone);
            $monitor = $this->findOrCreateMonitor($ownerProfile, true);
            $now = $this->nowIso();
            $update = [
                'executor_id' => $executorId,
                'last_seen_at' => $now,
                'last_error' => mb_substr(trim($error), 0, 2000),
                'updated_at' => $now,
            ];
            if ($scanEvent === 'started') {
                $update['last_scan_started_at'] = $now;
            }
            if ($scanEvent === 'finished') {
                $update['last_scan_finished_at'] = $now;
                $update['scan_requested_at'] = null;
            }
            DB::table('kwork_monitor_controls')->where('id', $monitor->id)->update($update);
            return $this->mapMonitor($this->findMonitor((int)$monitor->id));
        });
    }

    public function claim(int $leadId, string $executorId): ?array
    {
        if ($leadId < 1 || $executorId === '') {
            throw new InvalidArgumentException('Lead id and executor id are required');
        }
        return DB::transaction(function () use ($leadId, $executorId): ?array {
            $lead = DB::table('kwork_leads')->where('id', $leadId)->whereNull('deleted_at')->lockForUpdate()->first();
            if ($lead === null || (string)$lead->status !== 'approved') {
                return null;
            }
            $now = $this->nowIso();
            DB::table('kwork_leads')->where('id', $leadId)->update([
                'status' => 'sending',
                'executor_id' => $executorId,
                'executor_claimed_at' => $now,
                'version' => (int)$lead->version + 1,
                'updated_at' => $now,
            ]);
            $this->audit($leadId, $executorId, 'claimed', []);
            return $this->find($leadId);
        });
    }

    public function reportResult(int $leadId, string $executorId, bool $sent, string $error): array
    {
        if ($leadId < 1 || $executorId === '') {
            throw new InvalidArgumentException('Lead id and executor id are required');
        }
        return DB::transaction(function () use ($leadId, $executorId, $sent, $error): array {
            $lead = DB::table('kwork_leads')->where('id', $leadId)->lockForUpdate()->first();
            if ($lead === null || (string)$lead->executor_id !== $executorId || (string)$lead->status !== 'sending') {
                throw new InvalidArgumentException('Lead is not claimed by this executor');
            }
            $status = $sent ? 'sent' : 'failed';
            DB::table('kwork_leads')->where('id', $leadId)->update([
                'status' => $status,
                'last_error' => $sent ? '' : trim($error),
                'version' => (int)$lead->version + 1,
                'updated_at' => $this->nowIso(),
            ]);
            $this->audit($leadId, $executorId, $status, $sent ? [] : ['error' => trim($error)]);
            return $this->find($leadId);
        });
    }

    public function reportAutoSent(int $leadId, string $executorId): array
    {
        if ($leadId < 1 || $executorId === '') {
            throw new InvalidArgumentException('Lead id and executor id are required');
        }

        return DB::transaction(function () use ($leadId, $executorId): array {
            $lead = DB::table('kwork_leads')
                ->where('id', $leadId)
                ->whereNull('deleted_at')
                ->lockForUpdate()
                ->first();
            if ($lead === null) {
                throw new InvalidArgumentException('Lead not found');
            }

            $status = (string)$lead->status;
            if ($status === 'sent') {
                return ['changed' => false, 'lead' => $this->map($lead)];
            }
            if ($status === 'rejected') {
                throw new InvalidArgumentException('Rejected lead cannot be marked as auto-sent');
            }
            if ($status === 'sending' && (string)$lead->executor_id !== $executorId) {
                throw new InvalidArgumentException('Lead is claimed by another executor');
            }
            if (!in_array($status, ['new', 'edited', 'approved', 'failed', 'sending'], true)) {
                throw new InvalidArgumentException('Lead cannot be marked as auto-sent in its current status');
            }

            DB::table('kwork_leads')->where('id', $leadId)->update([
                'status' => 'sent',
                'executor_id' => $executorId,
                'last_error' => '',
                'version' => (int)$lead->version + 1,
                'updated_at' => $this->nowIso(),
            ]);
            $this->audit($leadId, $executorId, 'auto_sent', ['previous_status' => $status]);

            return ['changed' => true, 'lead' => $this->find($leadId)];
        });
    }

    public function find(int $leadId): array
    {
        $lead = DB::table('kwork_leads')->where('id', $leadId)->first();
        if ($lead === null) {
            throw new InvalidArgumentException('Lead not found');
        }
        return $this->map($lead);
    }

    private function findRowForOwner(int $leadId, string $ownerProfile): object
    {
        $lead = DB::table('kwork_leads')
            ->where('id', $leadId)
            ->where('owner_profile_key', $ownerProfile)
            ->whereNull('deleted_at')
            ->lockForUpdate()
            ->first();
        if ($lead === null) {
            throw new InvalidArgumentException('Lead not found');
        }
        return $lead;
    }

    private function findOrCreateMonitor(string $ownerProfile, bool $lock): object
    {
        $query = DB::table('kwork_monitor_controls')->where('owner_profile_key', $ownerProfile);
        if ($lock) {
            $query->lockForUpdate();
        }
        $monitor = $query->first();
        if ($monitor !== null) {
            return $monitor;
        }

        $now = $this->nowIso();
        $id = DB::table('kwork_monitor_controls')->insertGetId([
            'owner_profile_key' => $ownerProfile,
            'desired_state' => 'stopped',
            'scan_requested_at' => null,
            'executor_id' => null,
            'last_seen_at' => null,
            'last_scan_started_at' => null,
            'last_scan_finished_at' => null,
            'last_error' => '',
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        return $this->findMonitor($id);
    }

    private function findMonitor(int $monitorId): object
    {
        $monitor = DB::table('kwork_monitor_controls')->where('id', $monitorId)->first();
        if ($monitor === null) {
            throw new InvalidArgumentException('Kwork monitor was not found');
        }
        return $monitor;
    }

    private function ingestValues(array $input, string $ownerProfile, string $title, string $now): array
    {
        return [
            'owner_profile_key' => $ownerProfile,
            'source' => trim((string)($input['source'] ?? 'kwork')) ?: 'kwork',
            'source_url' => trim((string)($input['source_url'] ?? '')),
            'title' => mb_substr($title, 0, 255),
            'raw_brief' => (string)($input['raw_brief'] ?? ''),
            'summary' => (string)($input['summary'] ?? ''),
            'attachment_report' => (string)($input['attachment_report'] ?? ''),
            'draft_reply' => (string)($input['draft_reply'] ?? ''),
            'proposal_title' => mb_substr(trim((string)($input['proposal_title'] ?? '')), 0, 70),
            'proposal_price_rub' => $this->positiveInt($input['proposal_price_rub'] ?? null),
            'proposal_days' => $this->positiveInt($input['proposal_days'] ?? null),
            'buyer_desired_budget_rub' => $this->positiveInt($input['buyer_desired_budget_rub'] ?? null),
            'kwork_max_price_rub' => $this->positiveInt($input['kwork_max_price_rub'] ?? null),
            'offer_count' => $this->nonNegativeInt($input['offer_count'] ?? null),
        ];
    }

    private function editableValues(array $input): array
    {
        $out = [];
        foreach ([
            'title',
            'source_url',
            'raw_brief',
            'summary',
            'draft_reply',
            'proposal_title',
            'proposal_price_rub',
            'proposal_days',
        ] as $field) {
            if (!array_key_exists($field, $input)) {
                continue;
            }
            $out[$field] = match ($field) {
                'title' => mb_substr(trim((string)$input[$field]), 0, 255),
                'source_url' => trim((string)$input[$field]),
                'proposal_title' => mb_substr(trim((string)$input[$field]), 0, 70),
                'proposal_price_rub', 'proposal_days' => $this->positiveInt($input[$field]),
                default => (string)$input[$field],
            };
        }
        return $out;
    }

    private function map(object $row): array
    {
        return [
            'id' => (int)$row->id,
            'external_key' => (string)$row->external_key,
            'owner_profile' => (string)$row->owner_profile_key,
            'source' => (string)$row->source,
            'source_url' => (string)$row->source_url,
            'title' => (string)$row->title,
            'raw_brief' => (string)$row->raw_brief,
            'summary' => (string)$row->summary,
            'attachment_report' => (string)$row->attachment_report,
            'draft_reply' => (string)$row->draft_reply,
            'proposal_title' => (string)$row->proposal_title,
            'proposal_price_rub' => $row->proposal_price_rub === null ? null : (int)$row->proposal_price_rub,
            'proposal_days' => $row->proposal_days === null ? null : (int)$row->proposal_days,
            'buyer_desired_budget_rub' => $row->buyer_desired_budget_rub === null ? null : (int)$row->buyer_desired_budget_rub,
            'kwork_max_price_rub' => $row->kwork_max_price_rub === null ? null : (int)$row->kwork_max_price_rub,
            'offer_count' => $row->offer_count === null ? null : (int)$row->offer_count,
            'status' => (string)$row->status,
            'last_error' => (string)$row->last_error,
            'version' => (int)$row->version,
            'created_at' => (string)$row->created_at,
            'updated_at' => (string)$row->updated_at,
        ];
    }

    private function mapMonitor(object $row): array
    {
        return [
            'desired_state' => (string)$row->desired_state,
            'scan_requested' => (string)($row->scan_requested_at ?? '') !== '',
            'scan_requested_at' => $row->scan_requested_at,
            'executor_id' => $row->executor_id,
            'last_seen_at' => $row->last_seen_at,
            'last_scan_started_at' => $row->last_scan_started_at,
            'last_scan_finished_at' => $row->last_scan_finished_at,
            'last_error' => (string)$row->last_error,
            'updated_at' => (string)$row->updated_at,
        ];
    }

    private function audit(int $leadId, string $actor, string $action, array $payload): void
    {
        DB::table('kwork_lead_audits')->insert([
            'lead_id' => $leadId,
            'actor_profile' => $actor,
            'action' => $action,
            'payload_json' => json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
            'created_at' => $this->nowIso(),
        ]);
    }

    private function required(array $input, string $field): string
    {
        $value = trim((string)($input[$field] ?? ''));
        if ($value === '') {
            throw new InvalidArgumentException($field.' is required');
        }
        return $value;
    }

    private function positiveInt(mixed $value): ?int
    {
        if ($value === null || $value === '') {
            return null;
        }
        $number = filter_var($value, FILTER_VALIDATE_INT);
        if ($number === false || $number < 1) {
            throw new InvalidArgumentException('Expected a positive integer');
        }
        return (int)$number;
    }

    private function nonNegativeInt(mixed $value): ?int
    {
        if ($value === null || $value === '') {
            return null;
        }
        $number = filter_var($value, FILTER_VALIDATE_INT);
        if ($number === false || $number < 0) {
            throw new InvalidArgumentException('Expected a non-negative integer');
        }
        return (int)$number;
    }

    private function nowIso(): string
    {
        return now()->format('Y-m-d\\TH:i:s');
    }
}
