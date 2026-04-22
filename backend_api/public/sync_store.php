<?php

declare(strict_types=1);

require_once dirname(__DIR__) . '/src/bootstrap.php';
require_once dirname(__DIR__) . '/src/auth.php';

function sync_store_path(): string
{
    $dir = dirname(__DIR__) . '/storage';
    if (!is_dir($dir)) {
        @mkdir($dir, 0775, true);
    }
    return $dir . '/sync_store.json';
}

function sync_store_load(): array
{
    $path = sync_store_path();
    if (!is_file($path)) {
        return [
            'tasks' => [],
            'family_tasks' => [],
            'event_ids' => [],
        ];
    }
    $raw = file_get_contents($path);
    if (!is_string($raw) || trim($raw) === '') {
        return ['tasks' => [], 'family_tasks' => [], 'event_ids' => []];
    }
    $decoded = json_decode($raw, true);
    if (!is_array($decoded)) {
        return ['tasks' => [], 'family_tasks' => [], 'event_ids' => []];
    }
    $decoded['tasks'] = is_array($decoded['tasks'] ?? null) ? $decoded['tasks'] : [];
    $decoded['family_tasks'] = is_array($decoded['family_tasks'] ?? null) ? $decoded['family_tasks'] : [];
    $decoded['event_ids'] = is_array($decoded['event_ids'] ?? null) ? $decoded['event_ids'] : [];
    return $decoded;
}

function sync_store_save(array $store): void
{
    $path = sync_store_path();
    $tmp = $path . '.tmp';
    file_put_contents(
        $tmp,
        json_encode($store, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT),
        LOCK_EX
    );
    @rename($tmp, $path);
}

function sync_should_include(string $updatedAt, string $cursor, bool $changesMode): bool
{
    if ($updatedAt === '') {
        return false;
    }
    if ($changesMode) {
        return $updatedAt > $cursor;
    }
    return $updatedAt >= $cursor;
}

function sync_task_storage_id(string $ownerKey, string $taskId): string
{
    return $ownerKey . '::' . $taskId;
}

function sync_normalize_task(array $payload, string $actor): array
{
    $owner = trim((string)($payload['owner_key'] ?? $actor));
    if (!in_array($owner, ALLOWED_PROFILES, true)) {
        throw new InvalidArgumentException('Invalid owner_key');
    }
    $id = trim((string)($payload['id'] ?? ''));
    if ($id === '') {
        throw new InvalidArgumentException('Task id is required');
    }
    if ($owner !== $actor) {
        throw new InvalidArgumentException('Personal task can be changed only by owner');
    }
    $version = max(1, (int)($payload['version'] ?? 1));
    $updatedAt = trim((string)($payload['updated_at'] ?? ''));
    if ($updatedAt === '') {
        $updatedAt = iso_now();
    }
    $tags = $payload['tags'] ?? [];
    $participants = $payload['participants'] ?? [];
    return [
        'id' => $id,
        'owner_key' => $owner,
        'is_family' => false,
        'title' => trim((string)($payload['title'] ?? '')),
        'details' => trim((string)($payload['details'] ?? '')),
        'due_date' => trim((string)($payload['due_date'] ?? '')),
        'time' => trim((string)($payload['time'] ?? '')),
        'workflow_status' => ensure_workflow((string)($payload['workflow_status'] ?? 'todo')),
        'priority' => trim((string)($payload['priority'] ?? 'medium')),
        'tags' => is_array($tags) ? array_values($tags) : [],
        'participants' => is_array($participants) ? array_values($participants) : [],
        'duration_minutes' => max(0, (int)($payload['duration_minutes'] ?? 0)),
        'updated_at' => $updatedAt,
        'version' => $version,
    ];
}

function sync_normalize_family_task(array $payload): array
{
    $id = trim((string)($payload['id'] ?? ''));
    if ($id === '') {
        throw new InvalidArgumentException('Family task id is required');
    }
    $version = max(1, (int)($payload['version'] ?? 1));
    $updatedAt = trim((string)($payload['updated_at'] ?? ''));
    if ($updatedAt === '') {
        $updatedAt = iso_now();
    }
    $assignees = normalize_assignees($payload);
    if (!$assignees) {
        throw new InvalidArgumentException('assignees must contain at least one profile');
    }
    return [
        'id' => $id,
        'owner_key' => 'family',
        'is_family' => true,
        'title' => trim((string)($payload['title'] ?? '')),
        'details' => trim((string)($payload['details'] ?? '')),
        'due_date' => trim((string)($payload['due_date'] ?? '')),
        'time' => trim((string)($payload['time'] ?? '')),
        'workflow_status' => ensure_workflow((string)($payload['workflow_status'] ?? 'todo')),
        'assignees' => $assignees,
        'participants' => $assignees,
        'duration_minutes' => max(0, (int)($payload['duration_minutes'] ?? 0)),
        'updated_at' => $updatedAt,
        'version' => $version,
    ];
}

function sync_upsert_if_newer(array &$bucket, string $key, array $item): void
{
    $current = $bucket[$key] ?? null;
    if (!is_array($current)) {
        $bucket[$key] = $item;
        return;
    }
    $currentVersion = (int)($current['version'] ?? 1);
    $incomingVersion = (int)($item['version'] ?? 1);
    $currentUpdated = (string)($current['updated_at'] ?? '');
    $incomingUpdated = (string)($item['updated_at'] ?? '');
    $isNewer = $incomingVersion > $currentVersion || ($incomingVersion === $currentVersion && $incomingUpdated >= $currentUpdated);
    if ($isNewer) {
        $bucket[$key] = $item;
    }
}

function sync_handle_push(array $config): void
{
    require_api_key($config);
    $body = read_json_body();
    $actor = ensure_actor((string)($body['actor_profile'] ?? ''));
    $events = $body['events'] ?? [];
    if (!is_array($events)) {
        throw new InvalidArgumentException('events must be array');
    }

    $store = sync_store_load();
    $accepted = 0;
    $duplicates = 0;
    foreach ($events as $event) {
        if (!is_array($event)) {
            continue;
        }
        $eventId = trim((string)($event['event_id'] ?? ''));
        if ($eventId === '') {
            continue;
        }
        if (isset($store['event_ids'][$eventId])) {
            $duplicates++;
            continue;
        }
        $entity = (string)($event['entity'] ?? 'task');
        $action = (string)($event['action'] ?? 'upsert');
        $payload = is_array($event['payload'] ?? null) ? $event['payload'] : [];

        if ($entity === 'task') {
            if ($action === 'delete') {
                $owner = trim((string)($payload['owner_key'] ?? $actor));
                if ($owner !== $actor) {
                    throw new InvalidArgumentException('delete owner mismatch');
                }
                $taskId = trim((string)($payload['id'] ?? ''));
                if ($taskId !== '') {
                    unset($store['tasks'][sync_task_storage_id($owner, $taskId)]);
                }
            } elseif ($action === 'replace_person_tasks') {
                $owner = trim((string)($payload['owner_key'] ?? $actor));
                if ($owner !== $actor) {
                    throw new InvalidArgumentException('replace_person_tasks owner mismatch');
                }
                foreach (array_keys($store['tasks']) as $key) {
                    if (str_starts_with((string)$key, $owner . '::')) {
                        unset($store['tasks'][$key]);
                    }
                }
                $tasks = $payload['tasks'] ?? [];
                if (!is_array($tasks)) {
                    throw new InvalidArgumentException('tasks must be array');
                }
                foreach ($tasks as $rawTask) {
                    $task = sync_normalize_task(is_array($rawTask) ? $rawTask : [], $actor);
                    $storageId = sync_task_storage_id((string)$task['owner_key'], (string)$task['id']);
                    sync_upsert_if_newer($store['tasks'], $storageId, $task);
                }
            } else {
                $task = sync_normalize_task($payload, $actor);
                $storageId = sync_task_storage_id((string)$task['owner_key'], (string)$task['id']);
                sync_upsert_if_newer($store['tasks'], $storageId, $task);
            }
        } elseif ($entity === 'family_task') {
            ensure_family_permissions($actor);
            if ($action === 'delete') {
                $id = trim((string)($payload['id'] ?? ''));
                if ($id !== '') {
                    unset($store['family_tasks'][$id]);
                }
            } elseif ($action === 'replace_family_tasks') {
                $store['family_tasks'] = [];
                $items = $payload['items'] ?? [];
                if (!is_array($items)) {
                    throw new InvalidArgumentException('items must be array');
                }
                foreach ($items as $rawItem) {
                    $item = sync_normalize_family_task(is_array($rawItem) ? $rawItem : []);
                    sync_upsert_if_newer($store['family_tasks'], (string)$item['id'], $item);
                }
            } else {
                $item = sync_normalize_family_task($payload);
                sync_upsert_if_newer($store['family_tasks'], (string)$item['id'], $item);
            }
        } else {
            throw new InvalidArgumentException('Unsupported entity');
        }

        $accepted++;
        $store['event_ids'][$eventId] = iso_now();
    }

    if (count($store['event_ids']) > 20000) {
        $store['event_ids'] = array_slice($store['event_ids'], -15000, null, true);
    }
    sync_store_save($store);

    json_response(200, [
        'ok' => true,
        'accepted' => $accepted,
        'duplicates' => $duplicates,
        'telegram' => ['disabled' => true, 'message' => 'server delivery disabled'],
        'push' => ['disabled' => true],
        'server_time' => iso_now(),
    ]);
}

function sync_handle_pull(array $config, bool $forceChangesMode = false): void
{
    require_api_key($config);
    $cursorInput = trim((string)($_GET['cursor'] ?? ''));
    $sinceInput = trim((string)($_GET['since'] ?? ''));
    $modeInput = trim((string)($_GET['mode'] ?? ''));
    $changesMode = $forceChangesMode || $modeInput === 'changes' || $cursorInput !== '';
    $cursor = $changesMode
        ? ($cursorInput !== '' ? $cursorInput : ($sinceInput !== '' ? $sinceInput : '1970-01-01T00:00:00'))
        : ($sinceInput !== '' ? $sinceInput : '1970-01-01T00:00:00');
    $actorRaw = trim((string)($_GET['actor_profile'] ?? ''));
    $actor = $actorRaw !== '' ? ensure_actor($actorRaw) : '';

    $store = sync_store_load();
    $tasks = [];
    foreach ($store['tasks'] as $task) {
        if (!is_array($task)) {
            continue;
        }
        if ($actor !== '' && (string)($task['owner_key'] ?? '') !== $actor) {
            continue;
        }
        $updatedAt = (string)($task['updated_at'] ?? '');
        if (!sync_should_include($updatedAt, $cursor, $changesMode)) {
            continue;
        }
        $tasks[] = $task;
    }
    usort($tasks, static fn(array $a, array $b): int => strcmp(
        (string)($a['updated_at'] ?? '') . ':' . (string)($a['id'] ?? ''),
        (string)($b['updated_at'] ?? '') . ':' . (string)($b['id'] ?? '')
    ));

    $familyTasks = [];
    foreach ($store['family_tasks'] as $task) {
        if (!is_array($task)) {
            continue;
        }
        $updatedAt = (string)($task['updated_at'] ?? '');
        if (!sync_should_include($updatedAt, $cursor, $changesMode)) {
            continue;
        }
        $familyTasks[] = $task;
    }
    usort($familyTasks, static fn(array $a, array $b): int => strcmp(
        (string)($a['updated_at'] ?? '') . ':' . (string)($a['id'] ?? ''),
        (string)($b['updated_at'] ?? '') . ':' . (string)($b['id'] ?? '')
    ));

    $serverTime = iso_now();
    $nextCursor = $changesMode ? $cursor : $serverTime;
    foreach ([$tasks, $familyTasks] as $bucket) {
        foreach ($bucket as $row) {
            if (!is_array($row)) {
                continue;
            }
            $updatedAt = trim((string)($row['updated_at'] ?? ''));
            if ($updatedAt !== '' && $updatedAt > $nextCursor) {
                $nextCursor = $updatedAt;
            }
        }
    }

    json_response(200, [
        'ok' => true,
        'tasks' => $tasks,
        'family_tasks' => $familyTasks,
        'server_time' => $serverTime,
        'cursor' => $cursor,
        'next_cursor' => $nextCursor,
        'mode' => $changesMode ? 'changes' : 'snapshot',
        'routing_contract' => [
            'family_task_recipients' => FAMILY_NOTIFICATION_PROFILES,
            'personal_task_visibility' => 'role_based',
        ],
    ]);
}
