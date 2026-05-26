<?php

declare(strict_types=1);

require_once dirname(__DIR__) . '/src/bootstrap.php';
require_once dirname(__DIR__) . '/src/db.php';
require_once dirname(__DIR__) . '/src/auth.php';
require_once dirname(__DIR__) . '/src/repository.php';
require_once dirname(__DIR__) . '/src/push_outbox.php';

function apply_event(PDO $db, array $event, string $actor, string $source): array
{
    $eventId = trim((string)($event['event_id'] ?? ''));
    if ($eventId === '') {
        return ['status' => 'skip'];
    }
    if (is_duplicate_event($db, $eventId)) {
        return ['status' => 'duplicate'];
    }

    $entity = (string)($event['entity'] ?? 'task');
    $action = (string)($event['action'] ?? 'upsert');
    $payload = is_array($event['payload'] ?? null) ? $event['payload'] : [];
    $recipients = recipients_for_push($actor, $entity, $action, $payload);

    if ($entity === 'task') {
        if ($action === 'delete') {
            $taskId = trim((string)($payload['id'] ?? ''));
            $owner = trim((string)($payload['owner_key'] ?? $actor));
            if ($taskId !== '') {
                delete_task($db, $taskId, $owner);
            }
        } elseif ($action === 'replace_person_tasks') {
            $owner = trim((string)($payload['owner_key'] ?? $actor));
            if ($owner !== $actor) {
                throw new InvalidArgumentException('replace_person_tasks owner mismatch');
            }
            $items = $payload['tasks'] ?? [];
            if (!is_array($items)) {
                throw new InvalidArgumentException('tasks must be array');
            }
            replace_person_tasks($db, $owner, $items);
        } else {
            $task = normalize_task($payload);
            ensure_task_permissions($actor, $task);
            upsert_task($db, $task);
        }
    } elseif ($entity === 'family_task') {
        ensure_family_permissions($actor);
        if ($action === 'delete') {
            $id = trim((string)($payload['id'] ?? ''));
            if ($id !== '') {
                delete_family_task($db, $id);
            }
        } elseif ($action === 'replace_family_tasks') {
            $items = $payload['items'] ?? [];
            if (!is_array($items)) {
                throw new InvalidArgumentException('items must be array');
            }
            replace_family_tasks($db, $items);
        } else {
            $item = normalize_family_task($payload);
            upsert_family_task($db, $item);
        }
    } else {
        throw new InvalidArgumentException('Unsupported entity');
    }

    register_event($db, $eventId, $source);
    return ['status' => 'accepted'];
}

function next_sync_cursor(array $tasks, array $familyTasks, string $fallback): string
{
    $cursor = $fallback;
    foreach ([$tasks, $familyTasks] as $bucket) {
        foreach ($bucket as $row) {
            if (!is_array($row)) {
                continue;
            }
            $updatedAt = trim((string)($row['updated_at'] ?? ''));
            if ($updatedAt !== '' && $updatedAt > $cursor) {
                $cursor = $updatedAt;
            }
        }
    }
    return $cursor;
}

try {
    $config = load_config();
    $db = db_connect($config);
    $method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
    $path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';

    if ($path === '/health') {
        json_response(200, ['ok' => true, 'time' => iso_now()]);
        exit;
    }

    if ($method === 'GET' && ($path === '/sync/pull' || $path === '/sync/changes')) {
        require_api_key($config);
        $sinceInput = trim((string)($_GET['since'] ?? ''));
        $cursorInput = trim((string)($_GET['cursor'] ?? ''));
        $modeInput = trim((string)($_GET['mode'] ?? ''));
        $isChangesMode = $path === '/sync/changes' || $modeInput === 'changes' || $cursorInput !== '';
        $since = $isChangesMode ? ($cursorInput !== '' ? $cursorInput : ($sinceInput !== '' ? $sinceInput : '1970-01-01T00:00:00')) : ($sinceInput !== '' ? $sinceInput : '1970-01-01T00:00:00');
        $actorRaw = trim((string)($_GET['actor_profile'] ?? ''));
        $tasks = $isChangesMode ? changed_tasks_after_cursor($db, $since) : changed_tasks_since($db, $since);
        if ($actorRaw !== '') {
            $actor = ensure_actor($actorRaw);
            $tasks = $isChangesMode
                ? changed_tasks_after_cursor_for_actor($db, $since, $actor)
                : changed_tasks_since_for_actor($db, $since, $actor);
        }
        $familyTasks = $isChangesMode
            ? changed_family_tasks_after_cursor($db, $since)
            : changed_family_tasks_since($db, $since);
        $serverTime = iso_now();
        $cursorFallback = $isChangesMode ? $since : $serverTime;
        $nextCursor = next_sync_cursor($tasks, $familyTasks, $cursorFallback);
        json_response(200, [
            'ok' => true,
            'tasks' => $tasks,
            'family_tasks' => $familyTasks,
            'projects' => all_projects($db),
            'family_groups' => all_family_groups($db),
            'project_groups' => project_group_map($db),
            'server_time' => $serverTime,
            'cursor' => $since,
            'next_cursor' => $nextCursor,
            'mode' => $isChangesMode ? 'changes' : 'snapshot',
            'routing_contract' => [
                'family_task_recipients' => FAMILY_NOTIFICATION_PROFILES,
                'personal_task_visibility' => 'role_based',
            ],
        ]);
        exit;
    }

    if ($method === 'POST' && $path === '/devices/register') {
        require_api_key($config);
        $body = read_json_body();
        $actor = ensure_actor((string)($body['actor_profile'] ?? ''));
        $token = trim((string)($body['token'] ?? ''));
        if ($token === '') {
            throw new InvalidArgumentException('token is required');
        }
        $platform = trim((string)($body['platform'] ?? 'android')) ?: 'android';
        $appVersion = trim((string)($body['app_version'] ?? ''));
        $deviceId = isset($body['device_id']) ? trim((string)$body['device_id']) : null;
        upsert_device_token($db, $token, $actor, $platform, $appVersion, $deviceId ?: null);
        json_response(200, ['ok' => true]);
        exit;
    }

    if ($method === 'POST' && $path === '/devices/unregister') {
        require_api_key($config);
        $body = read_json_body();
        $actor = ensure_actor((string)($body['actor_profile'] ?? ''));
        $token = trim((string)($body['token'] ?? ''));
        if ($token === '') {
            throw new InvalidArgumentException('token is required');
        }
        deactivate_device_token($db, $token, $actor);
        json_response(200, ['ok' => true]);
        exit;
    }

    if ($method === 'POST' && $path === '/sync/push') {
        require_api_key($config);
        $body = read_json_body();
        $actor = ensure_actor((string)($body['actor_profile'] ?? ''));
        $source = trim((string)($body['source'] ?? 'mobile')) ?: 'mobile';
        $events = $body['events'] ?? [];
        if (!is_array($events)) {
            throw new InvalidArgumentException('events must be array');
        }

        $accepted = 0;
        $duplicates = 0;
        $db->beginTransaction();
        try {
            foreach ($events as $event) {
                if (!is_array($event)) {
                    continue;
                }
                $result = apply_event($db, $event, $actor, $source);
                if ($result['status'] === 'accepted') {
                    $accepted++;
                } elseif ($result['status'] === 'duplicate') {
                    $duplicates++;
                }
            }
            $db->commit();
        } catch (Throwable $inner) {
            $db->rollBack();
            throw $inner;
        }

        json_response(200, [
            'ok' => true,
            'accepted' => $accepted,
            'duplicates' => $duplicates,
            'push' => ['disabled' => true],
            'server_time' => iso_now(),
        ]);
        exit;
    }

    if ($method === 'POST' && $path === '/push/outbox/retry') {
        require_api_key($config);
        json_response(200, ['ok' => true, 'result' => ['disabled' => true]]);
        exit;
    }

    // ── Task Projects ─────────────────────────────────────────

    if ($method === 'GET' && $path === '/projects') {
        require_api_key($config);
        $projects = all_projects($db);
        $pgMap = project_group_map($db);
        json_response(200, ['ok' => true, 'projects' => $projects, 'project_groups' => $pgMap]);
        exit;
    }

    if ($method === 'POST' && $path === '/projects/create') {
        require_api_key($config);
        $body = read_json_body();
        $actor = ensure_actor((string)($body['actor_profile'] ?? ''));
        $name = trim((string)($body['name'] ?? ''));
        if ($name === '') {
            throw new InvalidArgumentException('name is required');
        }
        $id = 'prj-' . str_replace('.', '', uniqid('', true));
        $description = trim((string)($body['description'] ?? ''));
        $now = iso_now();
        upsert_project($db, [
            'id' => $id,
            'name' => $name,
            'description' => $description,
            'owner_key' => $actor,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        json_response(200, [
            'ok' => true,
            'project' => ['id' => $id, 'name' => $name, 'description' => $description, 'owner_key' => $actor, 'created_at' => $now, 'updated_at' => $now],
        ]);
        exit;
    }

    if ($method === 'POST' && $path === '/projects/update') {
        require_api_key($config);
        $body = read_json_body();
        $actor = ensure_actor((string)($body['actor_profile'] ?? ''));
        $id = trim((string)($body['id'] ?? ''));
        if ($id === '') {
            throw new InvalidArgumentException('id is required');
        }
        $name = trim((string)($body['name'] ?? ''));
        $description = trim((string)($body['description'] ?? ''));
        $now = iso_now();
        upsert_project($db, ['id' => $id, 'name' => $name, 'description' => $description, 'owner_key' => $actor, 'updated_at' => $now]);
        if (isset($body['group_ids']) && is_array($body['group_ids'])) {
            set_project_groups($db, $id, array_map('strval', $body['group_ids']));
        }
        json_response(200, ['ok' => true]);
        exit;
    }

    if ($method === 'POST' && $path === '/projects/delete') {
        require_api_key($config);
        $body = read_json_body();
        $id = trim((string)($body['id'] ?? ''));
        if ($id === '') {
            throw new InvalidArgumentException('id is required');
        }
        delete_project($db, $id);
        json_response(200, ['ok' => true]);
        exit;
    }

    if ($method === 'POST' && $path === '/projects/set-groups') {
        require_api_key($config);
        $body = read_json_body();
        $projectId = trim((string)($body['project_id'] ?? ''));
        if ($projectId === '') {
            throw new InvalidArgumentException('project_id is required');
        }
        $groupIds = $body['group_ids'] ?? [];
        if (!is_array($groupIds)) {
            throw new InvalidArgumentException('group_ids must be array');
        }
        set_project_groups($db, $projectId, array_map('strval', $groupIds));
        json_response(200, ['ok' => true]);
        exit;
    }

    // ── Family Groups ─────────────────────────────────────────

    if ($method === 'GET' && $path === '/family-groups') {
        require_api_key($config);
        $groups = all_family_groups($db);
        $pgMap = project_group_map($db);
        json_response(200, ['ok' => true, 'groups' => $groups, 'project_groups' => $pgMap]);
        exit;
    }

    if ($method === 'POST' && $path === '/family-groups/create') {
        require_api_key($config);
        $body = read_json_body();
        $actor = ensure_actor((string)($body['actor_profile'] ?? ''));
        $name = trim((string)($body['name'] ?? ''));
        if ($name === '') {
            throw new InvalidArgumentException('name is required');
        }
        $members = $body['members'] ?? [];
        if (!is_array($members)) {
            throw new InvalidArgumentException('members must be array');
        }
        $id = 'grp-' . str_replace('.', '', uniqid('', true));
        $now = iso_now();
        upsert_family_group($db, ['id' => $id, 'name' => $name, 'members' => $members, 'owner_key' => $actor, 'created_at' => $now, 'updated_at' => $now]);
        json_response(200, ['ok' => true, 'group' => ['id' => $id, 'name' => $name, 'members' => $members, 'owner_key' => $actor, 'created_at' => $now, 'updated_at' => $now]]);
        exit;
    }

    if ($method === 'POST' && $path === '/family-groups/update') {
        require_api_key($config);
        $body = read_json_body();
        $actor = ensure_actor((string)($body['actor_profile'] ?? ''));
        $id = trim((string)($body['id'] ?? ''));
        if ($id === '') {
            throw new InvalidArgumentException('id is required');
        }
        $name = trim((string)($body['name'] ?? ''));
        $now = iso_now();
        $record = ['id' => $id, 'name' => $name, 'owner_key' => $actor, 'updated_at' => $now];
        if (isset($body['members']) && is_array($body['members'])) {
            $record['members'] = $body['members'];
        }
        upsert_family_group($db, $record);
        json_response(200, ['ok' => true]);
        exit;
    }

    if ($method === 'POST' && $path === '/family-groups/delete') {
        require_api_key($config);
        $body = read_json_body();
        $id = trim((string)($body['id'] ?? ''));
        if ($id === '') {
            throw new InvalidArgumentException('id is required');
        }
        delete_family_group($db, $id);
        json_response(200, ['ok' => true]);
        exit;
    }

    json_response(404, ['ok' => false, 'error' => 'Not found']);
} catch (UnexpectedValueException $exc) {
    json_response(401, ['ok' => false, 'error' => $exc->getMessage()]);
} catch (InvalidArgumentException $exc) {
    json_response(400, ['ok' => false, 'error' => $exc->getMessage()]);
} catch (Throwable $exc) {
    json_response(500, ['ok' => false, 'error' => $exc->getMessage()]);
}