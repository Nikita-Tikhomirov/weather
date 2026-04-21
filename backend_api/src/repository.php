<?php

declare(strict_types=1);

function normalize_task(array $task): array
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
        'workflow_status' => ensure_workflow((string)($task['workflow_status'] ?? 'todo')),
        'priority' => (string)($task['priority'] ?? 'medium'),
        'tags' => is_array($tags) ? array_values($tags) : [],
        'participants' => is_array($participants) ? array_values($participants) : [],
        'duration_minutes' => (int)($task['duration_minutes'] ?? 0),
        'updated_at' => (string)($task['updated_at'] ?? iso_now()),
        'version' => (int)($task['version'] ?? 1),
    ];
}

function task_storage_id(string $ownerKey, string $taskId, bool $isFamily): string
{
    $trimmed = trim($taskId);
    if ($isFamily || $trimmed === '') {
        return $trimmed;
    }
    if (str_starts_with($trimmed, $ownerKey . '::')) {
        return $trimmed;
    }
    return $ownerKey . '::' . $trimmed;
}

function task_external_id(string $ownerKey, string $storedId, bool $isFamily): string
{
    if ($isFamily) {
        return $storedId;
    }
    $prefix = $ownerKey . '::';
    if (str_starts_with($storedId, $prefix)) {
        return substr($storedId, strlen($prefix));
    }
    return $storedId;
}

function normalize_family_task(array $item): array
{
    $assignees = normalize_assignees($item);
    if (count($assignees) === 0) {
        throw new InvalidArgumentException('assignees must contain at least one allowed profile');
    }
    return [
        'id' => (string)($item['id'] ?? ''),
        'title' => trim((string)($item['title'] ?? '')),
        'details' => trim((string)($item['details'] ?? '')),
        'due_date' => (string)($item['due_date'] ?? ''),
        'time' => (string)($item['time'] ?? ''),
        'workflow_status' => ensure_workflow((string)($item['workflow_status'] ?? 'todo')),
        'assignees' => $assignees,
        // Legacy read/write compatibility for old clients.
        'participants' => $assignees,
        'duration_minutes' => (int)($item['duration_minutes'] ?? 0),
        'updated_at' => (string)($item['updated_at'] ?? iso_now()),
        'version' => (int)($item['version'] ?? 1),
    ];
}

function is_duplicate_event(PDO $db, string $eventId): bool
{
    $stmt = $db->prepare('SELECT 1 FROM sync_events WHERE event_id = :event_id LIMIT 1');
    $stmt->execute(['event_id' => $eventId]);
    return (bool)$stmt->fetchColumn();
}

function register_event(PDO $db, string $eventId, string $source): void
{
    $stmt = $db->prepare(
        'INSERT INTO sync_events (event_id, source, created_at) VALUES (:event_id, :source, :created_at)'
    );
    $stmt->execute([
        'event_id' => $eventId,
        'source' => $source,
        'created_at' => iso_now(),
    ]);
}

function upsert_task(PDO $db, array $task): void
{
    $ownerKey = (string)$task['owner_key'];
    $isFamily = (bool)$task['is_family'];
    $storedId = task_storage_id($ownerKey, (string)$task['id'], $isFamily);
    $sql = <<<SQL
INSERT INTO tasks (
    id, owner_key, is_family, title, details, due_date, time_value, workflow_status, priority,
    tags_json, participants_json, duration_minutes, updated_at, version
) VALUES (
    :id, :owner_key, :is_family, :title, :details, :due_date, :time_value, :workflow_status, :priority,
    :tags_json, :participants_json, :duration_minutes, :updated_at, :version
)
ON DUPLICATE KEY UPDATE
    owner_key = VALUES(owner_key),
    is_family = VALUES(is_family),
    title = VALUES(title),
    details = VALUES(details),
    due_date = VALUES(due_date),
    time_value = VALUES(time_value),
    workflow_status = VALUES(workflow_status),
    priority = VALUES(priority),
    tags_json = VALUES(tags_json),
    participants_json = VALUES(participants_json),
    duration_minutes = VALUES(duration_minutes),
    updated_at = VALUES(updated_at),
    version = GREATEST(version, VALUES(version))
SQL;
    $stmt = $db->prepare($sql);
    $stmt->execute([
        'id' => $storedId,
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
        'duration_minutes' => $task['duration_minutes'],
        'updated_at' => $task['updated_at'],
        'version' => $task['version'],
    ]);
}

function delete_task(PDO $db, string $taskId, ?string $ownerKey = null): void
{
    if ($ownerKey !== null && trim($ownerKey) !== '') {
        $stmt = $db->prepare('DELETE FROM tasks WHERE id = :id OR id = :scoped_id');
        $stmt->execute([
            'id' => $taskId,
            'scoped_id' => task_storage_id($ownerKey, $taskId, false),
        ]);
        return;
    }
    $stmt = $db->prepare('DELETE FROM tasks WHERE id = :id');
    $stmt->execute(['id' => $taskId]);
}

function replace_person_tasks(PDO $db, string $ownerKey, array $tasks): void
{
    $db->prepare('DELETE FROM tasks WHERE owner_key = :owner_key AND is_family = 0')->execute(['owner_key' => $ownerKey]);
    foreach ($tasks as $task) {
        $task = normalize_task(is_array($task) ? $task : []);
        $task['owner_key'] = $ownerKey;
        $task['is_family'] = false;
        upsert_task($db, $task);
    }
}

function upsert_family_task(PDO $db, array $item): void
{
    $sql = <<<SQL
INSERT INTO family_tasks (
    id, title, details, due_date, time_value, workflow_status, participants_json, duration_minutes, updated_at, version
) VALUES (
    :id, :title, :details, :due_date, :time_value, :workflow_status, :participants_json, :duration_minutes, :updated_at, :version
)
ON DUPLICATE KEY UPDATE
    title = VALUES(title),
    details = VALUES(details),
    due_date = VALUES(due_date),
    time_value = VALUES(time_value),
    workflow_status = VALUES(workflow_status),
    participants_json = VALUES(participants_json),
    duration_minutes = VALUES(duration_minutes),
    updated_at = VALUES(updated_at),
    version = GREATEST(version, VALUES(version))
SQL;
    $stmt = $db->prepare($sql);
    $stmt->execute([
        'id' => $item['id'],
        'title' => $item['title'],
        'details' => $item['details'],
        'due_date' => $item['due_date'],
        'time_value' => $item['time'],
        'workflow_status' => $item['workflow_status'],
        'participants_json' => json_encode($item['assignees'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
        'duration_minutes' => $item['duration_minutes'],
        'updated_at' => $item['updated_at'],
        'version' => $item['version'],
    ]);
}

function delete_family_task(PDO $db, string $id): void
{
    $stmt = $db->prepare('DELETE FROM family_tasks WHERE id = :id');
    $stmt->execute(['id' => $id]);
}

function replace_family_tasks(PDO $db, array $items): void
{
    $db->exec('DELETE FROM family_tasks');
    foreach ($items as $item) {
        $normalized = normalize_family_task(is_array($item) ? $item : []);
        upsert_family_task($db, $normalized);
    }
}

function changed_tasks_since(PDO $db, string $since): array
{
    $stmt = $db->prepare('SELECT * FROM tasks WHERE updated_at >= :since ORDER BY updated_at, id');
    $stmt->execute(['since' => $since]);
    $rows = $stmt->fetchAll();
    $out = [];
    foreach ($rows as $row) {
        $owner = (string)$row['owner_key'];
        $isFamily = (bool)$row['is_family'];
        $storedId = (string)$row['id'];
        $out[] = [
            'id' => task_external_id($owner, $storedId, $isFamily),
            'owner_key' => $owner,
            'is_family' => $isFamily,
            'title' => (string)$row['title'],
            'details' => (string)$row['details'],
            'due_date' => (string)$row['due_date'],
            'time' => (string)$row['time_value'],
            'workflow_status' => (string)$row['workflow_status'],
            'priority' => (string)$row['priority'],
            'tags' => json_decode((string)$row['tags_json'], true) ?: [],
            'participants' => json_decode((string)$row['participants_json'], true) ?: [],
            'duration_minutes' => (int)$row['duration_minutes'],
            'updated_at' => (string)$row['updated_at'],
            'version' => (int)$row['version'],
        ];
    }
    return $out;
}

function changed_tasks_since_for_actor(PDO $db, string $since, string $actor): array
{
    $stmt = $db->prepare(
        'SELECT * FROM tasks WHERE updated_at >= :since AND is_family = 0 AND owner_key = :owner_key ORDER BY updated_at, id'
    );
    $stmt->execute([
        'since' => $since,
        'owner_key' => $actor,
    ]);
    $rows = $stmt->fetchAll();
    $out = [];
    foreach ($rows as $row) {
        $owner = (string)$row['owner_key'];
        $isFamily = (bool)$row['is_family'];
        $storedId = (string)$row['id'];
        $out[] = [
            'id' => task_external_id($owner, $storedId, $isFamily),
            'owner_key' => $owner,
            'is_family' => $isFamily,
            'title' => (string)$row['title'],
            'details' => (string)$row['details'],
            'due_date' => (string)$row['due_date'],
            'time' => (string)$row['time_value'],
            'workflow_status' => (string)$row['workflow_status'],
            'priority' => (string)$row['priority'],
            'tags' => json_decode((string)$row['tags_json'], true) ?: [],
            'participants' => json_decode((string)$row['participants_json'], true) ?: [],
            'duration_minutes' => (int)$row['duration_minutes'],
            'updated_at' => (string)$row['updated_at'],
            'version' => (int)$row['version'],
        ];
    }
    return $out;
}

function changed_family_tasks_since(PDO $db, string $since): array
{
    $stmt = $db->prepare('SELECT * FROM family_tasks WHERE updated_at >= :since ORDER BY updated_at, id');
    $stmt->execute(['since' => $since]);
    $rows = $stmt->fetchAll();
    $out = [];
    foreach ($rows as $row) {
        $assignees = json_decode((string)$row['participants_json'], true) ?: [];
        $out[] = [
            'id' => (string)$row['id'],
            'title' => (string)$row['title'],
            'details' => (string)$row['details'],
            'due_date' => (string)$row['due_date'],
            'time' => (string)$row['time_value'],
            'workflow_status' => (string)$row['workflow_status'],
            'assignees' => $assignees,
            'participants' => $assignees,
            'duration_minutes' => (int)$row['duration_minutes'],
            'updated_at' => (string)$row['updated_at'],
            'version' => (int)$row['version'],
        ];
    }
    return $out;
}

function upsert_device_token(
    PDO $db,
    string $token,
    string $profileKey,
    string $platform,
    string $appVersion,
    ?string $deviceId
): void {
    $sql = <<<SQL
INSERT INTO device_tokens (
  token, profile_key, platform, app_version, device_id, is_active, last_seen_at, created_at, updated_at
) VALUES (
  :token, :profile_key, :platform, :app_version, :device_id, 1, :last_seen_at, :created_at, :updated_at
)
ON DUPLICATE KEY UPDATE
  profile_key = VALUES(profile_key),
  platform = VALUES(platform),
  app_version = VALUES(app_version),
  device_id = VALUES(device_id),
  is_active = 1,
  last_seen_at = VALUES(last_seen_at),
  updated_at = VALUES(updated_at)
SQL;
    $now = iso_now();
    $stmt = $db->prepare($sql);
    $stmt->execute([
        'token' => $token,
        'profile_key' => $profileKey,
        'platform' => $platform,
        'app_version' => $appVersion,
        'device_id' => $deviceId,
        'last_seen_at' => $now,
        'created_at' => $now,
        'updated_at' => $now,
    ]);
}

function deactivate_device_token(PDO $db, string $token, ?string $profileKey = null): void
{
    if ($profileKey === null) {
        $stmt = $db->prepare(
            "UPDATE device_tokens SET is_active = 0, updated_at = :updated_at WHERE token = :token"
        );
        $stmt->execute(['updated_at' => iso_now(), 'token' => $token]);
        return;
    }
    $stmt = $db->prepare(
        "UPDATE device_tokens
         SET is_active = 0, updated_at = :updated_at
         WHERE token = :token AND profile_key = :profile_key"
    );
    $stmt->execute([
        'updated_at' => iso_now(),
        'token' => $token,
        'profile_key' => $profileKey,
    ]);
}

function active_device_tokens_for_profiles(PDO $db, array $profiles): array
{
    if (!$profiles) {
        return [];
    }
    $profiles = array_values(array_unique(array_map(static fn($x): string => (string)$x, $profiles)));
    $placeholders = implode(',', array_fill(0, count($profiles), '?'));
    $sql = "SELECT token, profile_key FROM device_tokens WHERE is_active = 1 AND profile_key IN ($placeholders)";
    $stmt = $db->prepare($sql);
    $stmt->execute($profiles);
    return $stmt->fetchAll();
}
