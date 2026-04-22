<?php

declare(strict_types=1);

require_once dirname(__DIR__) . '/src/bootstrap.php';
require_once dirname(__DIR__) . '/src/db.php';
require_once dirname(__DIR__) . '/src/auth.php';
require_once dirname(__DIR__) . '/src/repository.php';
require_once dirname(__DIR__) . '/src/telegram_outbox.php';
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
    if ($source !== 'telegram') {
        enqueue_telegram_event($db, $eventId, [
            'event_id' => $eventId,
            'entity' => $entity,
            'action' => $action,
            'payload' => $payload,
            'actor_profile' => $actor,
        ], $recipients);
    }
    enqueue_push_notifications($db, $eventId, $actor, $entity, $action, $payload, $recipients);
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

        $pushResult = process_push_outbox($db, $config, 200);
        json_response(200, [
            'ok' => true,
            'accepted' => $accepted,
            'duplicates' => $duplicates,
            'push' => $pushResult,
            'server_time' => iso_now(),
        ]);
        exit;
    }

    if ($method === 'POST' && $path === '/telegram/events') {
        require_api_key($config);
        $body = read_json_body();
        $actor = ensure_actor((string)($body['actor_profile'] ?? ''));
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
                $result = apply_event($db, $event, $actor, 'telegram');
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
        $pushResult = process_push_outbox($db, $config, 200);
        json_response(200, ['ok' => true, 'accepted' => $accepted, 'duplicates' => $duplicates, 'push' => $pushResult]);
        exit;
    }

    if ($method === 'POST' && $path === '/telegram/outbox/retry') {
        require_api_key($config);
        $result = process_outbox($db, $config);
        json_response(200, ['ok' => true, 'result' => $result]);
        exit;
    }

    if ($method === 'POST' && $path === '/push/outbox/retry') {
        require_api_key($config);
        $result = process_push_outbox($db, $config);
        json_response(200, ['ok' => true, 'result' => $result]);
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
