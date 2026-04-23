<?php

namespace App\Domain\Sync;

use Illuminate\Support\Facades\DB;

final class SyncRepository
{
    public function nowIso(): string
    {
        return now()->format('Y-m-d\TH:i:s');
    }

    public function isDuplicateEvent(string $eventId): bool
    {
        return DB::table('sync_events')->where('event_id', $eventId)->exists();
    }

    public function registerEvent(string $eventId, string $source): void
    {
        DB::table('sync_events')->updateOrInsert(
            ['event_id' => $eventId],
            ['source' => $source, 'created_at' => $this->nowIso()]
        );
    }

    public function normalizeTask(array $task): array
    {
        $tags = $task['tags'] ?? [];
        $participants = $task['participants'] ?? [];

        return [
            'id' => (string)($task['id'] ?? ''),
            'owner_key' => (string)($task['owner_key'] ?? ''),
            'is_family' => (bool)($task['is_family'] ?? false),
            'title' => trim((string)($task['title'] ?? '')),
            'details' => trim((string)($task['details'] ?? '')),
            'due_date' => (string)($task['due_date'] ?? ''),
            'time' => (string)($task['time'] ?? ''),
            'workflow_status' => SyncRules::ensureWorkflow((string)($task['workflow_status'] ?? 'todo')),
            'priority' => (string)($task['priority'] ?? 'medium'),
            'tags' => is_array($tags) ? array_values($tags) : [],
            'participants' => is_array($participants) ? array_values($participants) : [],
            'duration_minutes' => (int)($task['duration_minutes'] ?? 0),
            'updated_at' => (string)($task['updated_at'] ?? $this->nowIso()),
            'version' => max(1, (int)($task['version'] ?? 1)),
        ];
    }

    public function normalizeFamilyTask(array $item): array
    {
        $assignees = SyncRules::normalizeAssignees($item);

        return [
            'id' => (string)($item['id'] ?? ''),
            'owner_key' => 'family',
            'is_family' => true,
            'title' => trim((string)($item['title'] ?? '')),
            'details' => trim((string)($item['details'] ?? '')),
            'due_date' => (string)($item['due_date'] ?? ''),
            'time' => (string)($item['time'] ?? ''),
            'workflow_status' => SyncRules::ensureWorkflow((string)($item['workflow_status'] ?? 'todo')),
            'assignees' => $assignees,
            'participants' => $assignees,
            'duration_minutes' => (int)($item['duration_minutes'] ?? 0),
            'updated_at' => (string)($item['updated_at'] ?? $this->nowIso()),
            'version' => max(1, (int)($item['version'] ?? 1)),
        ];
    }

    public function taskStorageId(string $ownerKey, string $taskId, bool $isFamily): string
    {
        $trimmed = trim($taskId);
        if ($isFamily || $trimmed === '') {
            return $trimmed;
        }
        if (str_starts_with($trimmed, $ownerKey.'::')) {
            return $trimmed;
        }
        return $ownerKey.'::'.$trimmed;
    }

    public function taskExternalId(string $ownerKey, string $storedId, bool $isFamily): string
    {
        if ($isFamily) {
            return $storedId;
        }
        $prefix = $ownerKey.'::';
        if (str_starts_with($storedId, $prefix)) {
            return substr($storedId, strlen($prefix));
        }
        return $storedId;
    }

    public function upsertTask(array $task): void
    {
        $ownerKey = (string)$task['owner_key'];
        $isFamily = (bool)$task['is_family'];
        $storedId = $this->taskStorageId($ownerKey, (string)$task['id'], $isFamily);

        $currentVersion = (int)(DB::table('tasks')->where('id', $storedId)->value('version') ?? 1);
        $nextVersion = max($currentVersion, (int)$task['version']);

        DB::table('tasks')->updateOrInsert(
            ['id' => $storedId],
            [
                'owner_key' => $ownerKey,
                'is_family' => $isFamily ? 1 : 0,
                'title' => $task['title'],
                'details' => $task['details'],
                'due_date' => $task['due_date'],
                'time_value' => $task['time'],
                'workflow_status' => $task['workflow_status'],
                'priority' => $task['priority'],
                'tags_json' => json_encode($task['tags'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                'participants_json' => json_encode($task['participants'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                'duration_minutes' => (int)$task['duration_minutes'],
                'updated_at' => $task['updated_at'],
                'version' => $nextVersion,
            ]
        );
    }

    public function deleteTask(string $taskId, ?string $ownerKey = null): void
    {
        if ($ownerKey !== null && trim($ownerKey) !== '') {
            DB::table('tasks')
                ->where('id', $taskId)
                ->orWhere('id', $this->taskStorageId($ownerKey, $taskId, false))
                ->delete();
            return;
        }
        DB::table('tasks')->where('id', $taskId)->delete();
    }

    public function replacePersonTasks(string $ownerKey, array $tasks): void
    {
        DB::table('tasks')->where('owner_key', $ownerKey)->where('is_family', 0)->delete();
        foreach ($tasks as $task) {
            $task = $this->normalizeTask(is_array($task) ? $task : []);
            $task['owner_key'] = $ownerKey;
            $task['is_family'] = false;
            $this->upsertTask($task);
        }
    }

    public function upsertFamilyTask(array $item): void
    {
        $currentVersion = (int)(DB::table('family_tasks')->where('id', $item['id'])->value('version') ?? 1);
        $nextVersion = max($currentVersion, (int)$item['version']);

        DB::table('family_tasks')->updateOrInsert(
            ['id' => $item['id']],
            [
                'title' => $item['title'],
                'details' => $item['details'],
                'due_date' => $item['due_date'],
                'time_value' => $item['time'],
                'workflow_status' => $item['workflow_status'],
                'participants_json' => json_encode($item['assignees'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                'duration_minutes' => (int)$item['duration_minutes'],
                'updated_at' => $item['updated_at'],
                'version' => $nextVersion,
            ]
        );
    }

    public function deleteFamilyTask(string $id): void
    {
        DB::table('family_tasks')->where('id', $id)->delete();
    }

    public function replaceFamilyTasks(array $items): void
    {
        DB::table('family_tasks')->delete();
        foreach ($items as $item) {
            $normalized = $this->normalizeFamilyTask(is_array($item) ? $item : []);
            $this->upsertFamilyTask($normalized);
        }
    }

    public function changedTasks(string $since, ?string $actor = null, bool $afterCursor = false): array
    {
        $query = DB::table('tasks');
        $query->where('updated_at', $afterCursor ? '>' : '>=', $since);

        if ($actor !== null && $actor !== '') {
            $query->where('owner_key', $actor)->where('is_family', 0);
        }

        $rows = $query->orderBy('updated_at')->orderBy('id')->get();

        $out = [];
        foreach ($rows as $row) {
            $owner = (string)$row->owner_key;
            $isFamily = (bool)$row->is_family;
            $storedId = (string)$row->id;
            $out[] = [
                'id' => $this->taskExternalId($owner, $storedId, $isFamily),
                'owner_key' => $owner,
                'is_family' => $isFamily,
                'title' => (string)$row->title,
                'details' => (string)$row->details,
                'due_date' => (string)$row->due_date,
                'time' => (string)$row->time_value,
                'workflow_status' => (string)$row->workflow_status,
                'priority' => (string)$row->priority,
                'tags' => $this->decodeJsonArray($row->tags_json),
                'participants' => $this->decodeJsonArray($row->participants_json),
                'duration_minutes' => (int)$row->duration_minutes,
                'updated_at' => (string)$row->updated_at,
                'version' => (int)$row->version,
            ];
        }

        return $out;
    }

    public function changedFamilyTasks(string $since, bool $afterCursor = false): array
    {
        $rows = DB::table('family_tasks')
            ->where('updated_at', $afterCursor ? '>' : '>=', $since)
            ->orderBy('updated_at')
            ->orderBy('id')
            ->get();

        $out = [];
        foreach ($rows as $row) {
            $participants = $this->decodeJsonArray($row->participants_json);
            $out[] = [
                'id' => (string)$row->id,
                'owner_key' => 'family',
                'is_family' => true,
                'title' => (string)$row->title,
                'details' => (string)$row->details,
                'due_date' => (string)$row->due_date,
                'time' => (string)$row->time_value,
                'workflow_status' => (string)$row->workflow_status,
                'participants' => $participants,
                'assignees' => $participants,
                'duration_minutes' => (int)$row->duration_minutes,
                'updated_at' => (string)$row->updated_at,
                'version' => (int)$row->version,
            ];
        }

        return $out;
    }

    public function upsertDeviceToken(
        string $token,
        string $actor,
        string $platform,
        string $appVersion,
        ?string $deviceId,
        string $playServices = 'unknown',
        string $tokenStatus = 'active',
        string $lastError = '',
    ): void
    {
        $now = $this->nowIso();
        $normalizedTokenStatus = trim($tokenStatus) !== '' ? trim($tokenStatus) : 'active';
        $normalizedPlayServices = trim($playServices) !== '' ? trim($playServices) : 'unknown';
        $normalizedLastError = trim($lastError);
        DB::table('device_tokens')->updateOrInsert(
            ['token' => $token],
            [
                'profile_key' => $actor,
                'platform' => $platform,
                'app_version' => $appVersion,
                'device_id' => $deviceId,
                'is_active' => 1,
                'token_status' => $normalizedTokenStatus,
                'play_services' => $normalizedPlayServices,
                'last_error' => $normalizedLastError,
                'registered_at' => $now,
                'last_seen_at' => $now,
                'created_at' => $now,
                'updated_at' => $now,
            ]
        );
    }

    public function deactivateDeviceToken(string $token, string $actor): void
    {
        DB::table('device_tokens')
            ->where('token', $token)
            ->where('profile_key', $actor)
            ->update([
                'is_active' => 0,
                'token_status' => 'inactive',
                'updated_at' => $this->nowIso(),
            ]);
    }

    public function markDeviceTokenFailure(string $token, string $error, bool $permanent): void
    {
        $status = $permanent ? 'unregistered' : 'retry';
        $trimmedError = substr(trim($error), 0, 500);
        DB::table('device_tokens')
            ->where('token', $token)
            ->update([
                'is_active' => $permanent ? 0 : 1,
                'token_status' => $status,
                'last_error' => $trimmedError,
                'updated_at' => $this->nowIso(),
            ]);
    }

    public function upsertDeviceStatus(
        string $actor,
        string $platform,
        string $tokenStatus,
        string $playServices,
        string $appVersion,
        string $deviceId,
        string $lastError,
        string $token = '',
    ): void {
        $now = $this->nowIso();
        $record = [
            'profile_key' => trim($actor),
            'platform' => trim($platform) !== '' ? trim($platform) : 'android',
            'token_status' => trim($tokenStatus) !== '' ? trim($tokenStatus) : 'unknown',
            'play_services' => trim($playServices) !== '' ? trim($playServices) : 'unknown',
            'last_error' => substr(trim($lastError), 0, 500),
            'app_version' => trim($appVersion),
            'device_id' => trim($deviceId),
            'token' => trim($token),
            'updated_at' => $now,
            'created_at' => $now,
        ];

        DB::table('device_status')->insert($record);
    }

    public function latestDeviceStatusForActor(string $actor): array
    {
        $row = DB::table('device_status')
            ->where('profile_key', $actor)
            ->orderByDesc('id')
            ->first();

        $tokens = DB::table('device_tokens')
            ->where('profile_key', $actor)
            ->orderByDesc('updated_at')
            ->limit(3)
            ->get(['token', 'token_status', 'play_services', 'last_error', 'last_seen_at', 'is_active'])
            ->map(function ($item): array {
                return [
                    'token' => (string) $item->token,
                    'token_status' => (string) ($item->token_status ?? ''),
                    'play_services' => (string) ($item->play_services ?? ''),
                    'last_error' => (string) ($item->last_error ?? ''),
                    'last_seen_at' => (string) ($item->last_seen_at ?? ''),
                    'is_active' => (bool) ($item->is_active ?? false),
                ];
            })
            ->values()
            ->all();

        if ($row === null) {
            return [
                'actor_profile' => $actor,
                'status' => null,
                'tokens' => $tokens,
            ];
        }

        return [
            'actor_profile' => $actor,
            'status' => [
                'platform' => (string) $row->platform,
                'token_status' => (string) $row->token_status,
                'play_services' => (string) $row->play_services,
                'last_error' => (string) $row->last_error,
                'app_version' => (string) $row->app_version,
                'device_id' => (string) $row->device_id,
                'token' => (string) $row->token,
                'updated_at' => (string) $row->updated_at,
            ],
            'tokens' => $tokens,
        ];
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
