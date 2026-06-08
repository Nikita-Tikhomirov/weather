<?php

namespace App\Domain\Sync;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

final class SyncRepository
{
    private const ALLOWED_REMINDER_OFFSETS = [1440, 720, 180, 120, 60, 30, 15, 5];

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
        $participants = $task['participants'] ?? $task['assignees'] ?? [];

        return [
            'id' => (string)($task['id'] ?? ''),
            'owner_key' => (string)($task['owner_key'] ?? ''),
            'project_id' => (string)($task['project_id'] ?? ''),
            'group_id' => (string)($task['group_id'] ?? ''),
            'is_family' => (bool)($task['is_family'] ?? false),
            'title' => trim((string)($task['title'] ?? '')),
            'details' => trim((string)($task['details'] ?? '')),
            'due_date' => (string)($task['due_date'] ?? ''),
            'time' => (string)($task['time'] ?? ''),
            'workflow_status' => SyncRules::ensureWorkflow((string)($task['workflow_status'] ?? 'todo')),
            'priority' => (string)($task['priority'] ?? 'medium'),
            'tags' => is_array($tags) ? array_values($tags) : [],
            'participants' => is_array($participants) ? array_values($participants) : [],
            'collaboration' => $this->normalizeCollaboration($task['collaboration'] ?? $task['collaboration_json'] ?? []),
            'reminder_offsets_minutes' => $this->normalizeReminderOffsets($task['reminder_offsets_minutes'] ?? []),
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
            'project_id' => (string)($item['project_id'] ?? ''),
            'group_id' => (string)($item['group_id'] ?? ''),
            'owner_key' => 'family',
            'is_family' => true,
            'title' => trim((string)($item['title'] ?? '')),
            'details' => trim((string)($item['details'] ?? '')),
            'due_date' => (string)($item['due_date'] ?? ''),
            'time' => (string)($item['time'] ?? ''),
            'workflow_status' => SyncRules::ensureWorkflow((string)($item['workflow_status'] ?? 'todo')),
            'assignees' => $assignees,
            'participants' => $assignees,
            'collaboration' => $this->normalizeCollaboration($item['collaboration'] ?? $item['collaboration_json'] ?? []),
            'reminder_offsets_minutes' => $this->normalizeReminderOffsets($item['reminder_offsets_minutes'] ?? []),
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

    public function findTask(string $storedId): ?array
    {
        $row = DB::table('tasks')->where('id', $storedId)->first();
        if ($row === null) {
            return null;
        }
        return [
            'id' => (string) $row->id,
            'owner_key' => (string) $row->owner_key,
            'is_family' => (bool) $row->is_family,
            'title' => (string) $row->title,
            'workflow_status' => (string) $row->workflow_status,
        ];
    }

    public function findFamilyTask(string $taskId): ?array
    {
        $row = DB::table('family_tasks')->where('id', $taskId)->first();
        if ($row === null) {
            return null;
        }
        return [
            'id' => (string) $row->id,
            'title' => (string) $row->title,
            'workflow_status' => (string) $row->workflow_status,
        ];
    }

    /** @return array<string, mixed>|null */
    public function contextTask(string $taskId, string $actor = ''): ?array
    {
        $taskId = trim($taskId);
        $actor = trim($actor);
        if ($taskId === '') {
            return null;
        }

        $row = DB::table('tasks')->where('id', $taskId)->first();
        if ($row === null && $actor !== '') {
            $row = DB::table('tasks')
                ->where('id', $this->taskStorageId($actor, $taskId, false))
                ->first();
        }
        if ($row !== null) {
            return [
                'id' => $this->taskExternalId((string) $row->owner_key, (string) $row->id, (bool) $row->is_family),
                'stored_id' => (string) $row->id,
                'owner_key' => (string) $row->owner_key,
                'project_id' => (string)($row->project_id ?? ''),
                'group_id' => (string)($row->group_id ?? ''),
                'is_family' => (bool) $row->is_family,
                'title' => (string) $row->title,
                'details' => (string) $row->details,
                'due_date' => (string) $row->due_date,
                'time' => (string) $row->time_value,
                'workflow_status' => (string) $row->workflow_status,
                'priority' => (string)($row->priority ?? 'medium'),
                'participants' => $this->decodeJsonArray($row->participants_json),
                'collaboration' => $this->normalizeCollaboration($row->collaboration_json ?? []),
                'updated_at' => (string) $row->updated_at,
                'version' => (int) $row->version,
            ];
        }

        $family = DB::table('family_tasks')->where('id', $taskId)->first();
        if ($family === null) {
            return null;
        }

        $participants = $this->decodeJsonArray($family->participants_json);
        return [
            'id' => (string) $family->id,
            'stored_id' => (string) $family->id,
            'owner_key' => 'family',
            'project_id' => (string)($family->project_id ?? ''),
            'group_id' => (string)($family->group_id ?? ''),
            'is_family' => true,
            'title' => (string) $family->title,
            'details' => (string) $family->details,
            'due_date' => (string) $family->due_date,
            'time' => (string) $family->time_value,
            'workflow_status' => (string) $family->workflow_status,
            'priority' => 'medium',
            'participants' => $participants,
            'assignees' => $participants,
            'collaboration' => $this->normalizeCollaboration($family->collaboration_json ?? []),
            'updated_at' => (string) $family->updated_at,
            'version' => (int) $family->version,
        ];
    }

    /**
     * @param array<string, mixed> $context
     * @param array<string, mixed> $collaboration
     */
    public function updateTaskCollaboration(array $context, array $collaboration, string $workflowStatus = ''): void
    {
        $storedId = (string)($context['stored_id'] ?? $context['id'] ?? '');
        if ($storedId === '') {
            return;
        }

        $normalized = $this->normalizeCollaboration($collaboration);
        $now = $this->nowIso();
        $updates = [
            'collaboration_json' => json_encode($normalized, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
            'updated_at' => $now,
            'version' => max(1, (int)($context['version'] ?? 1) + 1),
        ];
        if ($workflowStatus !== '') {
            $updates['workflow_status'] = SyncRules::ensureWorkflow($workflowStatus);
        }

        if ((bool)($context['is_family'] ?? false)) {
            DB::table('family_tasks')->where('id', $storedId)->update($updates);
            return;
        }

        DB::table('tasks')->where('id', $storedId)->update($updates);
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
                'project_id' => $task['project_id'] ?? '',
                'group_id' => $task['group_id'] ?? '',
                'is_family' => $isFamily ? 1 : 0,
                'title' => $task['title'],
                'details' => $task['details'],
                'due_date' => $task['due_date'],
                'time_value' => $task['time'],
                'workflow_status' => $task['workflow_status'],
                'priority' => $task['priority'],
                'tags_json' => json_encode($task['tags'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                'participants_json' => json_encode($task['participants'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                'collaboration_json' => json_encode($this->normalizeCollaboration($task['collaboration'] ?? []), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                'reminder_offsets_json' => json_encode($task['reminder_offsets_minutes'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
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
                'project_id' => $item['project_id'] ?? '',
                'group_id' => $item['group_id'] ?? '',
                'title' => $item['title'],
                'details' => $item['details'],
                'due_date' => $item['due_date'],
                'time_value' => $item['time'],
                'workflow_status' => $item['workflow_status'],
                'participants_json' => json_encode($item['assignees'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                'collaboration_json' => json_encode($this->normalizeCollaboration($item['collaboration'] ?? []), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                'reminder_offsets_json' => json_encode($item['reminder_offsets_minutes'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
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
                'project_id' => (string)($row->project_id ?? ''),
                'group_id' => (string)($row->group_id ?? ''),
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
                'collaboration' => $this->normalizeCollaboration($row->collaboration_json ?? []),
                'reminder_offsets_minutes' => $this->normalizeReminderOffsets($this->decodeJsonArray($row->reminder_offsets_json)),
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
                'project_id' => (string)($row->project_id ?? ''),
                'group_id' => (string)($row->group_id ?? ''),
                'owner_key' => 'family',
                'is_family' => true,
                'title' => (string)$row->title,
                'details' => (string)$row->details,
                'due_date' => (string)$row->due_date,
                'time' => (string)$row->time_value,
                'workflow_status' => (string)$row->workflow_status,
                'participants' => $participants,
                'assignees' => $participants,
                'collaboration' => $this->normalizeCollaboration($row->collaboration_json ?? []),
                'reminder_offsets_minutes' => $this->normalizeReminderOffsets($this->decodeJsonArray($row->reminder_offsets_json)),
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

    public function deviceTokenStatus(string $token, string $actor): ?string
    {
        $status = DB::table('device_tokens')
            ->where('token', trim($token))
            ->where('profile_key', trim($actor))
            ->value('token_status');

        return is_string($status) ? $status : null;
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
        $activeTokenCount = 0;
        foreach ($tokens as $token) {
            if (($token['is_active'] ?? false) === true) {
                $activeTokenCount++;
            }
        }
        $effectiveTokenStatus = $activeTokenCount > 0
            ? 'active'
            : (string) ($tokens[0]['token_status'] ?? 'missing');

        if ($row === null) {
            return [
                'actor_profile' => $actor,
                'status' => null,
                'effective_token_status' => $effectiveTokenStatus,
                'active_token_count' => $activeTokenCount,
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
            'effective_token_status' => $effectiveTokenStatus,
            'active_token_count' => $activeTokenCount,
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

    private function normalizeCollaboration(mixed $value): array
    {
        if (is_string($value) && trim($value) !== '') {
            $decoded = json_decode($value, true);
            $value = is_array($decoded) ? $decoded : [];
        }
        if (!is_array($value)) {
            $value = [];
        }

        return [
            'comments' => array_values(is_array($value['comments'] ?? null) ? $value['comments'] : []),
            'attachments' => array_values(is_array($value['attachments'] ?? null) ? $value['attachments'] : []),
            'checklists' => array_values(is_array($value['checklists'] ?? null) ? $value['checklists'] : []),
            'questions' => array_values(is_array($value['questions'] ?? null) ? $value['questions'] : []),
            'activity' => array_values(is_array($value['activity'] ?? null) ? $value['activity'] : []),
            'agent_sessions' => array_values(is_array($value['agent_sessions'] ?? null) ? $value['agent_sessions'] : []),
        ];
    }

    /** @return array<string, mixed>|null */
    public function findProject(string $id): ?array
    {
        $row = DB::table('task_projects')->where('id', $id)->first();
        if ($row === null) {
            return null;
        }
        return [
            'id' => (string)$row->id,
            'name' => (string)$row->name,
            'description' => (string)$row->description,
            'owner_key' => (string)$row->owner_key,
            'created_at' => (string)$row->created_at,
            'updated_at' => (string)$row->updated_at,
        ];
    }

    /** @return array<string, mixed>|null */
    public function findGroup(string $id): ?array
    {
        $row = DB::table('family_groups')->where('id', $id)->first();
        if ($row === null) {
            return null;
        }
        return [
            'id' => (string)$row->id,
            'name' => (string)$row->name,
            'members' => $this->decodeJsonArray($row->members_json),
            'owner_key' => (string)$row->owner_key,
            'created_at' => (string)$row->created_at,
            'updated_at' => (string)$row->updated_at,
        ];
    }

    /** @return array<int, array<string, mixed>> */
    public function allProjects(): array
    {
        return DB::table('task_projects')
            ->orderBy('name')
            ->get()
            ->map(fn($row) => [
                'id' => (string)$row->id,
                'name' => (string)$row->name,
                'description' => (string)$row->description,
                'owner_key' => (string)$row->owner_key,
                'created_at' => (string)$row->created_at,
                'updated_at' => (string)$row->updated_at,
            ])
            ->values()
            ->all();
    }

    /**
     * Projects visible to the actor: owner OR member of an attached group.
     * @return array<int, array<string, mixed>>
     */
    public function visibleProjectsForActor(string $actor): array
    {
        if ($actor === '') {
            return [];
        }

        // 1) Projects owned by actor
        $ownedIds = DB::table('task_projects')
            ->where('owner_key', $actor)
            ->pluck('id')
            ->map(fn($v) => (string)$v)
            ->toArray();

        // 2) Groups where actor is a member OR owner
        $allGroups = DB::table('family_groups')->get();
        $actorGroupIds = [];
        foreach ($allGroups as $group) {
            $isOwner = (string)$group->owner_key === $actor;
            $members = $this->decodeJsonArray($group->members_json);
            if ($isOwner || in_array($actor, $members, true)) {
                $actorGroupIds[] = (string)$group->id;
            }
        }

        // 3) Projects linked to those groups
        $groupProjectIds = [];
        if (!empty($actorGroupIds)) {
            $groupProjectIds = DB::table('project_family_groups')
                ->whereIn('group_id', $actorGroupIds)
                ->pluck('project_id')
                ->map(fn($v) => (string)$v)
                ->toArray();
        }

        $visibleIds = array_unique(array_merge($ownedIds, $groupProjectIds));
        if (empty($visibleIds)) {
            return [];
        }

        return DB::table('task_projects')
            ->whereIn('id', $visibleIds)
            ->orderBy('name')
            ->get()
            ->map(fn($row) => [
                'id' => (string)$row->id,
                'name' => (string)$row->name,
                'description' => (string)$row->description,
                'owner_key' => (string)$row->owner_key,
                'created_at' => (string)$row->created_at,
                'updated_at' => (string)$row->updated_at,
            ])
            ->values()
            ->all();
    }

    /** @return array<int, array<string, mixed>> */
    public function allFamilyGroups(): array
    {
        return DB::table('family_groups')
            ->orderBy('name')
            ->get()
            ->map(fn($row) => [
                'id' => (string)$row->id,
                'name' => (string)$row->name,
                'members' => $this->decodeJsonArray($row->members_json),
                'owner_key' => (string)$row->owner_key,
                'created_at' => (string)$row->created_at,
                'updated_at' => (string)$row->updated_at,
            ])
            ->values()
            ->all();
    }

    /**
     * Groups visible to the actor: owner OR member.
     * @return array<int, array<string, mixed>>
     */
    public function visibleGroupsForActor(string $actor): array
    {
        if ($actor === '') {
            return [];
        }

        return DB::table('family_groups')
            ->orderBy('name')
            ->get()
            ->filter(function ($row) use ($actor): bool {
                // Owner always sees their group
                if ((string)$row->owner_key === $actor) {
                    return true;
                }
                // Member sees group they belong to
                $members = $this->decodeJsonArray($row->members_json);
                return in_array($actor, $members, true);
            })
            ->map(fn($row) => [
                'id' => (string)$row->id,
                'name' => (string)$row->name,
                'members' => $this->decodeJsonArray($row->members_json),
                'owner_key' => (string)$row->owner_key,
                'created_at' => (string)$row->created_at,
                'updated_at' => (string)$row->updated_at,
            ])
            ->values()
            ->all();
    }

    /**
     * Project-group map filtered to projects visible to actor.
     * @return array<string, list<string>> project_id => [group_id, ...]
     */
    public function visibleProjectGroupMap(string $actor): array
    {
        $visibleProjects = $this->visibleProjectsForActor($actor);
        $visibleProjectIds = array_map(fn($p) => $p['id'], $visibleProjects);
        if (empty($visibleProjectIds)) {
            return [];
        }

        $rows = DB::table('project_family_groups')
            ->whereIn('project_id', $visibleProjectIds)
            ->get();
        $map = [];
        foreach ($rows as $row) {
            $pid = (string)$row->project_id;
            $gid = (string)$row->group_id;
            if (!isset($map[$pid])) {
                $map[$pid] = [];
            }
            $map[$pid][] = $gid;
        }
        return $map;
    }

    /** @return array<string, list<string>> project_id => [group_id, ...] */
    public function projectGroupMap(): array
    {
        $rows = DB::table('project_family_groups')->get();
        $map = [];
        foreach ($rows as $row) {
            $pid = (string)$row->project_id;
            $gid = (string)$row->group_id;
            if (!isset($map[$pid])) {
                $map[$pid] = [];
            }
            $map[$pid][] = $gid;
        }
        return $map;
    }

    public function upsertProject(array $project): void
    {
        DB::table('task_projects')->updateOrInsert(
            ['id' => $project['id']],
            [
                'name' => $project['name'],
                'description' => $project['description'] ?? '',
                'owner_key' => $project['owner_key'],
                'created_at' => $project['created_at'] ?? $this->nowIso(),
                'updated_at' => $project['updated_at'] ?? $this->nowIso(),
            ],
        );
    }

    public function deleteProject(string $id): void
    {
        DB::table('task_projects')->where('id', $id)->delete();
        DB::table('project_family_groups')->where('project_id', $id)->delete();
        if (Schema::hasTable('project_chat_bindings')) {
            DB::table('project_chat_bindings')->where('project_id', $id)->delete();
        }
        if (Schema::hasTable('project_automation_configs')) {
            DB::table('project_automation_configs')->where('project_id', $id)->delete();
        }
    }

    public function upsertFamilyGroupRecord(array $group): void
    {
        DB::table('family_groups')->updateOrInsert(
            ['id' => $group['id']],
            [
                'name' => $group['name'],
                'members_json' => json_encode($group['members'] ?? [], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                'owner_key' => $group['owner_key'],
                'created_at' => $group['created_at'] ?? $this->nowIso(),
                'updated_at' => $group['updated_at'] ?? $this->nowIso(),
            ],
        );
    }

    public function deleteFamilyGroup(string $id): void
    {
        DB::table('family_groups')->where('id', $id)->delete();
        DB::table('project_family_groups')->where('group_id', $id)->delete();
        if (Schema::hasTable('project_chat_bindings')) {
            DB::table('project_chat_bindings')->where('group_id', $id)->delete();
        }
    }

    public function setProjectGroups(string $projectId, array $groupIds): void
    {
        DB::table('project_family_groups')->where('project_id', $projectId)->delete();
        $now = $this->nowIso();
        foreach ($groupIds as $gid) {
            DB::table('project_family_groups')->insert([
                'project_id' => $projectId,
                'group_id' => $gid,
            ]);
        }
    }

    /** @param list<string> $groupIds */
    public function syncProjectChatBindings(string $projectId, array $groupIds): void
    {
        if (!Schema::hasTable('project_chat_bindings')) {
            return;
        }

        $projectId = trim($projectId);
        if ($projectId === '') {
            return;
        }

        $normalizedGroupIds = array_values(array_unique(array_filter(
            array_map(static fn ($value): string => trim((string)$value), $groupIds),
            static fn (string $value): bool => $value !== '',
        )));
        $conversationKey = 'grp:project:'.$projectId;
        $expectedConversationKeys = $normalizedGroupIds === [] ? [] : [$conversationKey];

        DB::table('project_chat_bindings')
            ->where('project_id', $projectId)
            ->whereIn('source', ['family_group', 'project_group'])
            ->whereNotIn('conversation_key', $expectedConversationKeys === [] ? [''] : $expectedConversationKeys)
            ->delete();

        if ($normalizedGroupIds === []) {
            DB::table('project_chat_bindings')
                ->where('project_id', $projectId)
                ->whereIn('source', ['family_group', 'project_group'])
                ->delete();
            return;
        }

        $now = $this->nowIso();
        DB::table('project_chat_bindings')
            ->where('project_id', $projectId)
            ->update(['is_primary' => 0, 'updated_at' => $now]);
        DB::table('project_chat_bindings')->updateOrInsert(
            ['project_id' => $projectId, 'conversation_key' => $conversationKey],
            [
                'group_id' => $normalizedGroupIds[0],
                'source' => 'project_group',
                'is_primary' => 1,
                'created_at' => $now,
                'updated_at' => $now,
            ],
        );
    }

    /** @return list<array<string, mixed>> */
    public function projectChatBindings(string $projectId): array
    {
        if (!Schema::hasTable('project_chat_bindings')) {
            return [];
        }
        return DB::table('project_chat_bindings')
            ->where('project_id', trim($projectId))
            ->orderByDesc('is_primary')
            ->orderBy('created_at')
            ->get()
            ->map(static fn ($row): array => [
                'project_id' => (string)$row->project_id,
                'conversation_key' => (string)$row->conversation_key,
                'group_id' => (string)($row->group_id ?? ''),
                'source' => (string)($row->source ?? ''),
                'is_primary' => (bool)$row->is_primary,
                'created_at' => (string)$row->created_at,
                'updated_at' => (string)$row->updated_at,
            ])
            ->values()
            ->all();
    }

    /** @return array<string, mixed>|null */
    public function projectChatBinding(string $projectId, string $conversationKey): ?array
    {
        if (!Schema::hasTable('project_chat_bindings')) {
            return null;
        }
        $row = DB::table('project_chat_bindings')
            ->where('project_id', trim($projectId))
            ->where('conversation_key', trim($conversationKey))
            ->first();
        if ($row === null) {
            return null;
        }
        return [
            'project_id' => (string)$row->project_id,
            'conversation_key' => (string)$row->conversation_key,
            'group_id' => (string)($row->group_id ?? ''),
            'source' => (string)($row->source ?? ''),
            'is_primary' => (bool)$row->is_primary,
            'created_at' => (string)$row->created_at,
            'updated_at' => (string)$row->updated_at,
        ];
    }

    /** @return array<string, mixed> */
    public function projectAutomationConfig(string $projectId): array
    {
        $projectId = trim($projectId);
        $defaults = [
            'project_id' => $projectId,
            'primary_workspace_id' => '',
            'agent_enabled' => false,
            'default_agent_mode' => 'planner',
            'chat_analysis_message_limit' => 40,
            'created_at' => '',
            'updated_at' => '',
        ];
        if (!Schema::hasTable('project_automation_configs')) {
            return $defaults;
        }
        $row = DB::table('project_automation_configs')->where('project_id', $projectId)->first();
        if ($row === null) {
            return $defaults;
        }
        return [
            'project_id' => (string)$row->project_id,
            'primary_workspace_id' => (string)($row->primary_workspace_id ?? ''),
            'agent_enabled' => (bool)$row->agent_enabled,
            'default_agent_mode' => (string)($row->default_agent_mode ?? 'planner'),
            'chat_analysis_message_limit' => max(1, min(100, (int)($row->chat_analysis_message_limit ?? 40))),
            'created_at' => (string)$row->created_at,
            'updated_at' => (string)$row->updated_at,
        ];
    }

    /** @param array<string, mixed> $values */
    public function upsertProjectAutomationConfig(string $projectId, array $values): array
    {
        $projectId = trim($projectId);
        if ($projectId === '' || !Schema::hasTable('project_automation_configs')) {
            return $this->projectAutomationConfig($projectId);
        }

        $current = $this->projectAutomationConfig($projectId);
        $primaryWorkspaceId = array_key_exists('primary_workspace_id', $values)
            ? trim((string)$values['primary_workspace_id'])
            : (string)($current['primary_workspace_id'] ?? '');
        $agentEnabled = array_key_exists('agent_enabled', $values)
            ? (bool)$values['agent_enabled']
            : $primaryWorkspaceId !== '';
        $defaultAgentMode = trim((string)($values['default_agent_mode'] ?? $current['default_agent_mode'] ?? 'planner'));
        if ($defaultAgentMode === '') {
            $defaultAgentMode = 'planner';
        }
        $limit = array_key_exists('chat_analysis_message_limit', $values)
            ? (int)$values['chat_analysis_message_limit']
            : (int)($current['chat_analysis_message_limit'] ?? 40);
        $limit = max(1, min(100, $limit));
        $now = $this->nowIso();

        DB::table('project_automation_configs')->updateOrInsert(
            ['project_id' => $projectId],
            [
                'primary_workspace_id' => $primaryWorkspaceId,
                'agent_enabled' => $agentEnabled,
                'default_agent_mode' => $defaultAgentMode,
                'chat_analysis_message_limit' => $limit,
                'updated_at' => $now,
                'created_at' => (string)($current['created_at'] ?? '') === '' ? $now : $current['created_at'],
            ],
        );

        return $this->projectAutomationConfig($projectId);
    }

    private function normalizeReminderOffsets(mixed $raw): array
    {
        if (!is_array($raw)) {
            return [];
        }

        $normalized = [];
        foreach ($raw as $value) {
            $offset = (int) $value;
            if (!in_array($offset, self::ALLOWED_REMINDER_OFFSETS, true)) {
                continue;
            }
            if (!in_array($offset, $normalized, true)) {
                $normalized[] = $offset;
            }
        }

        rsort($normalized);
        return $normalized;
    }
}
