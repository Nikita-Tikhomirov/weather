<?php

namespace App\Http\Controllers;

use App\Domain\Sync\Cursor;
use App\Domain\Sync\ProfileRequestGuard;
use App\Domain\Sync\Profiles;
use App\Domain\Sync\SyncRepository;
use App\Domain\Sync\SyncRules;
use App\Services\Push\PushOutboxService;
use App\Services\Push\TaskReminderService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;
use Throwable;

class SyncController extends Controller
{
    public function __construct(
        private readonly SyncRepository $repo,
        private readonly PushOutboxService $pushOutbox,
        private readonly TaskReminderService $taskReminders,
    ) {}

    public function health(): JsonResponse
    {
        return $this->json(200, [
            'ok' => true,
            'time' => $this->repo->nowIso(),
        ]);
    }

    public function pull(Request $request): JsonResponse
    {
        try {
            $sinceInput = trim((string)$request->query('since', ''));
            $cursorInput = trim((string)$request->query('cursor', ''));
            $modeInput = trim((string)$request->query('mode', ''));
            $path = '/'.$request->path();

            $isChangesMode = str_contains($path, '/sync/changes')
                || str_contains($path, '/sync_changes.php')
                || $modeInput === 'changes'
                || $cursorInput !== '';

            $since = $isChangesMode
                ? ($cursorInput !== '' ? $cursorInput : ($sinceInput !== '' ? $sinceInput : '1970-01-01T00:00:00'))
                : ($sinceInput !== '' ? $sinceInput : '1970-01-01T00:00:00');

            $actorRaw = trim((string)$request->query('actor_profile', ''));
            $actor = $actorRaw !== '' ? ProfileRequestGuard::ensureAllowed($request, $actorRaw) : null;

            $tasks = $this->repo->changedTasks($since, $actor, $isChangesMode);
            $familyTasks = $this->repo->changedFamilyTasks($since, $isChangesMode);
            $serverTime = $this->repo->nowIso();
            $cursorFallback = $isChangesMode ? $since : $serverTime;
            $nextCursor = Cursor::nextSyncCursor($tasks, $familyTasks, $cursorFallback);

            return $this->json(200, [
                'ok' => true,
                'tasks' => $tasks,
                'family_tasks' => $familyTasks,
                'server_time' => $serverTime,
                'cursor' => $since,
                'next_cursor' => $nextCursor,
                'mode' => $isChangesMode ? 'changes' : 'snapshot',
                'routing_contract' => [
                    'family_task_recipients' => Profiles::ALLOWED,
                    'personal_task_visibility' => 'role_based',
                ],
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function push(Request $request): JsonResponse
    {
        try {
            $actor = ProfileRequestGuard::ensureAllowed($request, (string)$request->input('actor_profile', ''));
            $source = trim((string)$request->input('source', 'mobile')) ?: 'mobile';
            $events = $request->input('events', []);
            if (!is_array($events)) {
                throw new InvalidArgumentException('events must be array');
            }

            $accepted = 0;
            $duplicates = 0;
            $queued = 0;

            foreach ($events as $event) {
                if (!is_array($event)) {
                    continue;
                }
                $result = $this->applyEvent($event, $actor, $source);
                if ($result['status'] === 'accepted') {
                    $accepted++;
                    $queued += (int)($result['push_queued'] ?? 0);
                } elseif ($result['status'] === 'duplicate') {
                    $duplicates++;
                }
            }

            $pushStats = $this->pushOutbox->retryDue();
            $pushStats['queued'] = $queued;

            return $this->json(200, [
                'ok' => true,
                'accepted' => $accepted,
                'duplicates' => $duplicates,
                'telegram' => ['disabled' => true],
                'push' => $pushStats,
                'server_time' => $this->repo->nowIso(),
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function telegramEvents(Request $request): JsonResponse
    {
        try {
            $actor = ProfileRequestGuard::ensureAllowed($request, (string)$request->input('actor_profile', ''));
            $events = $request->input('events', []);
            if (!is_array($events)) {
                throw new InvalidArgumentException('events must be array');
            }

            $accepted = 0;
            $duplicates = 0;
            $queued = 0;

            foreach ($events as $event) {
                if (!is_array($event)) {
                    continue;
                }
                $result = $this->applyEvent($event, $actor, 'telegram');
                if ($result['status'] === 'accepted') {
                    $accepted++;
                    $queued += (int)($result['push_queued'] ?? 0);
                } elseif ($result['status'] === 'duplicate') {
                    $duplicates++;
                }
            }

            $pushStats = $this->pushOutbox->retryDue();
            $pushStats['queued'] = $queued;

            return $this->json(200, [
                'ok' => true,
                'accepted' => $accepted,
                'duplicates' => $duplicates,
                'telegram' => ['disabled' => true],
                'push' => $pushStats,
                'server_time' => $this->repo->nowIso(),
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function registerDevice(Request $request): JsonResponse
    {
        try {
            $actor = ProfileRequestGuard::ensureAllowed($request, (string)$request->input('actor_profile', ''));
            $token = trim((string)$request->input('token', ''));
            if ($token === '') {
                throw new InvalidArgumentException('token is required');
            }

            $platform = trim((string)$request->input('platform', 'android')) ?: 'android';
            $appVersion = trim((string)$request->input('app_version', ''));
            $deviceId = trim((string)$request->input('device_id', ''));
            $playServices = trim((string)$request->input('play_services', 'unknown')) ?: 'unknown';
            $tokenStatus = trim((string)$request->input('token_status', 'active')) ?: 'active';
            $lastError = trim((string)$request->input('last_error', ''));

            $this->repo->upsertDeviceToken(
                $token,
                $actor,
                $platform,
                $appVersion,
                $deviceId !== '' ? $deviceId : null,
                $playServices,
                $tokenStatus,
                $lastError,
            );

            $this->repo->upsertDeviceStatus(
                $actor,
                $platform,
                $tokenStatus,
                $playServices,
                $appVersion,
                $deviceId,
                $lastError,
                $token,
            );

            return $this->json(200, [
                'ok' => true,
                'token_status' => $tokenStatus,
                'play_services' => $playServices,
                'registered_at' => $this->repo->nowIso(),
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function unregisterDevice(Request $request): JsonResponse
    {
        try {
            $actor = ProfileRequestGuard::ensureAllowed($request, (string)$request->input('actor_profile', ''));
            $token = trim((string)$request->input('token', ''));
            if ($token === '') {
                throw new InvalidArgumentException('token is required');
            }

            $this->repo->deactivateDeviceToken($token, $actor);
            return $this->json(200, ['ok' => true]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function reportDeviceStatus(Request $request): JsonResponse
    {
        try {
            $actor = ProfileRequestGuard::ensureAllowed($request, (string)$request->input('actor_profile', ''));
            $platform = trim((string)$request->input('platform', 'android')) ?: 'android';
            $tokenStatus = trim((string)$request->input('token_status', 'unknown')) ?: 'unknown';
            $playServices = trim((string)$request->input('play_services', 'unknown')) ?: 'unknown';
            $appVersion = trim((string)$request->input('app_version', ''));
            $deviceId = trim((string)$request->input('device_id', ''));
            $lastError = trim((string)$request->input('last_error', ''));
            $token = trim((string)$request->input('token', ''));

            $this->repo->upsertDeviceStatus(
                $actor,
                $platform,
                $tokenStatus,
                $playServices,
                $appVersion,
                $deviceId,
                $lastError,
                $token,
            );

            return $this->json(200, ['ok' => true]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function getDeviceStatus(Request $request): JsonResponse
    {
        try {
            $actor = ProfileRequestGuard::ensureAllowed($request, (string)$request->query('actor_profile', ''));
            return $this->json(200, [
                'ok' => true,
                'result' => $this->repo->latestDeviceStatusForActor($actor),
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function pushDiagnostics(Request $request): JsonResponse
    {
        try {
            $actorRaw = trim((string)$request->query('actor_profile', ''));
            $actor = $actorRaw !== '' ? ProfileRequestGuard::ensureAllowed($request, $actorRaw) : null;

            $tokenQuery = DB::table('device_tokens')
                ->select('profile_key', 'token', 'token_status', 'play_services', 'last_error', 'last_seen_at', 'registered_at', 'is_active')
                ->orderByDesc('updated_at');
            if ($actor !== null) {
                $tokenQuery->where('profile_key', $actor);
            }

            $tokens = $tokenQuery
                ->limit(10)
                ->get()
                ->map(function ($row): array {
                    return [
                        'profile_key' => (string) $row->profile_key,
                        'token' => (string) $row->token,
                        'token_status' => (string) ($row->token_status ?? ''),
                        'play_services' => (string) ($row->play_services ?? ''),
                        'last_error' => (string) ($row->last_error ?? ''),
                        'last_seen_at' => (string) ($row->last_seen_at ?? ''),
                        'registered_at' => (string) ($row->registered_at ?? ''),
                        'is_active' => (bool) ($row->is_active ?? false),
                    ];
                })
                ->values()
                ->all();

            $failedOutbox = DB::table('push_outbox')
                ->select('id', 'event_id', 'profile_key', 'status', 'retry_count', 'last_error', 'updated_at')
                ->where('status', 'failed')
                ->orderByDesc('id')
                ->limit(10)
                ->get()
                ->map(function ($row): array {
                    return [
                        'id' => (int) $row->id,
                        'event_id' => (string) $row->event_id,
                        'profile_key' => (string) $row->profile_key,
                        'status' => (string) $row->status,
                        'retry_count' => (int) $row->retry_count,
                        'last_error' => (string) $row->last_error,
                        'updated_at' => (string) $row->updated_at,
                    ];
                })
                ->values()
                ->all();

            return $this->json(200, [
                'ok' => true,
                'push' => [
                    'enabled' => $this->pushOutbox->isEnabled(),
                    'configured' => $this->pushOutbox->isConfigured(),
                    'pending_count' => (int) DB::table('push_outbox')->where('status', 'pending')->count(),
                    'failed_count' => (int) DB::table('push_outbox')->where('status', 'failed')->count(),
                    'sent_count' => (int) DB::table('push_outbox')->where('status', 'sent')->count(),
                ],
                'actor_profile' => $actor,
                'device_status' => $actor !== null ? $this->repo->latestDeviceStatusForActor($actor) : null,
                'tokens' => $tokens,
                'failed_outbox' => $failedOutbox,
                'time' => $this->repo->nowIso(),
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function pushTest(Request $request): JsonResponse
    {
        try {
            $actor = ProfileRequestGuard::ensureAllowed($request, (string)$request->input('actor_profile', ''));
            $title = trim((string)$request->input('title', 'Тест push')) ?: 'Тест push';
            $body = trim((string)$request->input('body', 'Проверка доставки push-уведомления')) ?: 'Проверка доставки push-уведомления';
            $data = $request->input('data', []);
            if (!is_array($data)) {
                $data = [];
            }
            $data['type'] = 'diagnostic_test';
            $data['actor_profile'] = $actor;

            $eventId = sprintf('diag-test-%s-%s', $actor, str_replace('.', '', uniqid('', true)));
            $queued = $this->pushOutbox->enqueueRawToRecipients($eventId, [$actor], $title, $body, $data);
            $result = $this->pushOutbox->retryDue(50);

            return $this->json(200, [
                'ok' => true,
                'event_id' => $eventId,
                'queued' => $queued,
                'push' => $result,
                'device_status' => $this->repo->latestDeviceStatusForActor($actor),
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function telegramOutboxRetry(): JsonResponse
    {
        return $this->json(200, ['ok' => true, 'result' => ['disabled' => true]]);
    }

    public function pushOutboxRetry(): JsonResponse
    {
        return $this->json(200, [
            'ok' => true,
            'result' => $this->pushOutbox->retryDue(),
        ]);
    }

    /**
     * @return array{status:string,push_queued:int}
     */
    private function applyEvent(array $event, string $actor, string $source): array
    {
        $eventId = trim((string)($event['event_id'] ?? ''));
        if ($eventId === '') {
            return ['status' => 'skip', 'push_queued' => 0];
        }

        if ($this->repo->isDuplicateEvent($eventId)) {
            return ['status' => 'duplicate', 'push_queued' => 0];
        }

        $entity = (string)($event['entity'] ?? 'task');
        $action = (string)($event['action'] ?? 'upsert');
        $payload = is_array($event['payload'] ?? null) ? $event['payload'] : [];

            if ($entity === 'task') {
                if ($action === 'delete') {
                    $taskId = trim((string)($payload['id'] ?? ''));
                    $owner = trim((string)($payload['owner_key'] ?? $actor));
                    if ($taskId !== '') {
                        $this->repo->deleteTask($taskId, $owner);
                        $storedId = $this->repo->taskStorageId($owner, $taskId, false);
                        $this->taskReminders->clearForTask('task', $storedId);
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
                    $this->repo->replacePersonTasks($owner, $items);
                    $this->taskReminders->rescheduleAllForOwner($owner);
                } else {
                    $task = $this->repo->normalizeTask($payload);
                    SyncRules::ensureTaskPermissions($actor, $task);
                    $this->repo->upsertTask($task);
                    $this->taskReminders->rescheduleForTask($task);
                }
            } elseif ($entity === 'family_task') {
                SyncRules::ensureFamilyPermissions($actor);
                if ($action === 'delete') {
                    $id = trim((string)($payload['id'] ?? ''));
                    if ($id !== '') {
                        $this->repo->deleteFamilyTask($id);
                        $this->taskReminders->clearForTask('family_task', $id);
                    }
                } elseif ($action === 'replace_family_tasks') {
                    $items = $payload['items'] ?? [];
                    if (!is_array($items)) {
                        throw new InvalidArgumentException('items must be array');
                    }
                    $this->repo->replaceFamilyTasks($items);
                    $this->taskReminders->rescheduleAllFamily();
                } else {
                    $item = $this->repo->normalizeFamilyTask($payload);
                    $this->repo->upsertFamilyTask($item);
                    $this->taskReminders->rescheduleForFamilyTask($item);
                }
        } else {
            throw new InvalidArgumentException('Unsupported entity');
        }

        $this->repo->registerEvent($eventId, $source);
        $queued = $this->pushOutbox->enqueueFromEvent($eventId, $actor, $entity, $action, $payload);

        return ['status' => 'accepted', 'push_queued' => $queued];
    }

    private function json(int $status, array $payload): JsonResponse
    {
        return response()->json($payload, $status, [], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }
}
