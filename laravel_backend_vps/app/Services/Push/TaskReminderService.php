<?php

namespace App\Services\Push;

use App\Domain\Sync\SyncRepository;
use App\Domain\Sync\SyncRules;
use DateTimeImmutable;
use DateTimeInterface;
use DateTimeZone;
use Illuminate\Support\Facades\DB;

class TaskReminderService
{
    private const DEFAULT_TIME = '19:00';

    public function __construct(
        private readonly SyncRepository $repo,
        private readonly PushOutboxService $pushOutbox,
    ) {
    }

    public function rescheduleForTask(array $task): void
    {
        $storageId = $this->repo->taskStorageId(
            (string) ($task['owner_key'] ?? ''),
            (string) ($task['id'] ?? ''),
            false,
        );
        $this->reschedule('task', $storageId, $task);
    }

    public function rescheduleForFamilyTask(array $task): void
    {
        $storageId = trim((string) ($task['id'] ?? ''));
        $this->reschedule('family_task', $storageId, $task);
    }

    public function clearForTask(string $entity, string $storageId): void
    {
        DB::table('task_reminders')
            ->where('entity', $entity)
            ->where('task_storage_id', $storageId)
            ->delete();
    }

    public function rescheduleAllForOwner(string $ownerKey): void
    {
        $rows = DB::table('tasks')
            ->where('owner_key', $ownerKey)
            ->where('is_family', 0)
            ->get();

        foreach ($rows as $row) {
            $payload = [
                'id' => $this->repo->taskExternalId((string) $row->owner_key, (string) $row->id, false),
                'owner_key' => (string) $row->owner_key,
                'is_family' => false,
                'title' => (string) $row->title,
                'details' => (string) $row->details,
                'due_date' => (string) $row->due_date,
                'time' => (string) $row->time_value,
                'participants' => $this->decodeJsonArray($row->participants_json),
                'reminder_offsets_minutes' => $this->decodeJsonArray($row->reminder_offsets_json),
            ];
            $this->reschedule('task', (string) $row->id, $payload);
        }
    }

    public function rescheduleAllFamily(): void
    {
        $rows = DB::table('family_tasks')->get();

        foreach ($rows as $row) {
            $participants = $this->decodeJsonArray($row->participants_json);
            $payload = [
                'id' => (string) $row->id,
                'owner_key' => 'family',
                'is_family' => true,
                'title' => (string) $row->title,
                'details' => (string) $row->details,
                'due_date' => (string) $row->due_date,
                'time' => (string) $row->time_value,
                'participants' => $participants,
                'assignees' => $participants,
                'reminder_offsets_minutes' => $this->decodeJsonArray($row->reminder_offsets_json),
            ];
            $this->reschedule('family_task', (string) $row->id, $payload);
        }
    }

    /**
     * @return array{queued:int,processed:int}
     */
    public function dispatchDue(int $limit = 200): array
    {
        $nowIso = $this->repo->nowIso();
        $rows = DB::table('task_reminders')
            ->where('status', 'pending')
            ->where('remind_at', '<=', $nowIso)
            ->orderBy('id')
            ->limit(max(1, $limit))
            ->get();

        $queued = 0;
        $processed = 0;

        foreach ($rows as $row) {
            $processed++;
            $payload = $this->decodeJsonArray($row->payload_json);
            $title = (string) ($payload['title'] ?? 'Напоминание о задаче');
            $taskTitle = trim((string) ($payload['task_title'] ?? ''));
            $offset = (int) ($payload['offset_minutes'] ?? 0);
            $body = $this->buildReminderBody($taskTitle, $offset);

            $eventId = sprintf('reminder-%s-%s', (string) $row->id, str_replace(':', '-', (string) $row->remind_at));
            $queued += $this->pushOutbox->enqueueRawToRecipients(
                $eventId,
                [(string) $row->recipient_key],
                $title,
                $body,
                [
                    'type' => 'task_reminder',
                    'entity' => (string) $row->entity,
                    'task_storage_id' => (string) $row->task_storage_id,
                    'offset_minutes' => (string) $offset,
                    'due_at' => (string) $row->due_at,
                ],
            );

            DB::table('task_reminders')
                ->where('id', $row->id)
                ->update([
                    'status' => 'sent',
                    'sent_event_id' => $eventId,
                    'updated_at' => $this->repo->nowIso(),
                ]);
        }

        return [
            'queued' => $queued,
            'processed' => $processed,
        ];
    }

    private function reschedule(string $entity, string $storageId, array $payload): void
    {
        $storageId = trim($storageId);
        if ($storageId === '') {
            return;
        }

        $this->clearForTask($entity, $storageId);

        $recipients = SyncRules::recipientsForReminder($entity, $payload);
        $offsets = $this->normalizeOffsets($payload['reminder_offsets_minutes'] ?? []);
        $dueAt = $this->dueAt($payload);

        if ($dueAt === null || $recipients === [] || $offsets === []) {
            return;
        }

        $taskTitle = trim((string) ($payload['title'] ?? ''));
        $title = $entity === 'family_task' ? 'Семейная задача' : 'Личная задача';
        $createdAt = $this->repo->nowIso();

        foreach ($recipients as $recipient) {
            foreach ($offsets as $offset) {
                $remindAt = $dueAt->modify('-'.$offset.' minutes');
                if (!$remindAt instanceof DateTimeInterface) {
                    continue;
                }

                DB::table('task_reminders')->insert([
                    'entity' => $entity,
                    'task_storage_id' => $storageId,
                    'recipient_key' => $recipient,
                    'offset_minutes' => $offset,
                    'due_at' => $dueAt->format('Y-m-d\TH:i:s'),
                    'remind_at' => $remindAt->format('Y-m-d\TH:i:s'),
                    'payload_json' => json_encode([
                        'title' => $title,
                        'task_title' => $taskTitle,
                        'offset_minutes' => $offset,
                        'entity' => $entity,
                        'owner_key' => (string) ($payload['owner_key'] ?? ''),
                    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                    'status' => 'pending',
                    'sent_event_id' => null,
                    'created_at' => $createdAt,
                    'updated_at' => $createdAt,
                ]);
            }
        }
    }

    private function normalizeOffsets(mixed $raw): array
    {
        if (!is_array($raw)) {
            return [];
        }

        $allowed = [1440, 180, 120, 60, 30];
        $normalized = [];
        foreach ($raw as $value) {
            $offset = (int) $value;
            if (!in_array($offset, $allowed, true)) {
                continue;
            }
            if (!in_array($offset, $normalized, true)) {
                $normalized[] = $offset;
            }
        }
        rsort($normalized);
        return $normalized;
    }

    private function dueAt(array $payload): ?DateTimeImmutable
    {
        $dueDate = trim((string) ($payload['due_date'] ?? ''));
        if ($dueDate === '') {
            return null;
        }

        $timeValue = trim((string) ($payload['time'] ?? ''));
        if ($timeValue === '') {
            $timeValue = self::DEFAULT_TIME;
        }

        if (!preg_match('/^\d{2}:\d{2}$/', $timeValue)) {
            return null;
        }

        $tzName = (string) config('app.timezone', 'UTC');
        $tz = new DateTimeZone($tzName !== '' ? $tzName : 'UTC');

        $value = sprintf('%s %s:00', $dueDate, $timeValue);
        $dueAt = DateTimeImmutable::createFromFormat('Y-m-d H:i:s', $value, $tz);

        return $dueAt ?: null;
    }

    private function buildReminderBody(string $taskTitle, int $offsetMinutes): string
    {
        $offsetLabel = match ($offsetMinutes) {
            1440 => 'через 24 часа',
            180 => 'через 3 часа',
            120 => 'через 2 часа',
            60 => 'через 1 час',
            30 => 'через 30 минут',
            default => 'скоро',
        };

        if ($taskTitle === '') {
            return 'Напоминание: задача '.$offsetLabel.'.';
        }

        return sprintf('Напоминание %s: "%s".', $offsetLabel, $taskTitle);
    }

    private function decodeJsonArray(mixed $value): array
    {
        if (is_array($value)) {
            return $value;
        }
        if (!is_string($value) || trim($value) === '') {
            return [];
        }
        $decoded = json_decode($value, true);
        return is_array($decoded) ? $decoded : [];
    }
}
