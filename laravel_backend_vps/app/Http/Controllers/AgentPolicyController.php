<?php

namespace App\Http\Controllers;

use App\Domain\Access\AccessPolicyService;
use App\Domain\Agent\AgentTaskService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use InvalidArgumentException;
use Throwable;

class AgentPolicyController extends Controller
{
    public function __construct(
        private readonly AccessPolicyService $access,
        private readonly AgentTaskService $agentTasks,
    ) {
    }

    public function access(Request $request): JsonResponse
    {
        try {
            $actor = trim((string) $request->query('actor_profile', (string) $request->input('actor_profile', '')));
            $phone = trim((string) $request->query('phone', (string) $request->input('phone', '')));
            $payload = $actor !== ''
                ? $this->access->accessForActor($actor, $phone)
                : $this->access->accessForPhone($phone);

            return $this->json(200, ['ok' => true, 'access' => $payload]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function policy(Request $request): JsonResponse
    {
        try {
            $policy = $this->buildPolicy($request);
            return $this->json($policy['allowed'] ? 200 : 403, [
                'ok' => (bool) $policy['allowed'],
                'policy' => $policy,
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function ticket(Request $request): JsonResponse
    {
        try {
            $policy = $this->buildPolicy($request);
            if (!((bool) ($policy['allowed'] ?? false))) {
                return $this->json(403, [
                    'ok' => false,
                    'policy' => $policy,
                    'error' => (string) ($policy['reason'] ?? 'Нет прав на запуск агента.'),
                ]);
            }

            $ticket = $this->access->signPolicyTicket(
                $policy,
                (string) config('sync.agent_policy_ticket_secret', ''),
            );

            return $this->json(200, [
                'ok' => true,
                'policy' => $policy,
                'policy_ticket' => $ticket,
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function context(Request $request): JsonResponse
    {
        try {
            $policy = $this->buildPolicy($request);
            if (!((bool)($policy['allowed'] ?? false))) {
                return $this->json(403, [
                    'ok' => false,
                    'policy' => $policy,
                    'error' => (string)($policy['reason'] ?? 'Нет прав на контекст агента.'),
                ]);
            }

            return $this->json(200, [
                'ok' => true,
                'policy' => $policy,
                'context' => $this->agentTasks->buildContextPack(
                    (string)$request->input('actor_profile', ''),
                    (string)$request->input('task_id', ''),
                    (string)$request->input('workspace_id', ''),
                ),
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function event(Request $request): JsonResponse
    {
        try {
            $policy = $this->buildPolicy($request);
            if (!((bool)($policy['allowed'] ?? false))) {
                return $this->json(403, [
                    'ok' => false,
                    'policy' => $policy,
                    'error' => (string)($policy['reason'] ?? 'Нет прав на запись события агента.'),
                ]);
            }

            $payload = $request->input('payload', []);
            if (!is_array($payload)) {
                $payload = [];
            }
            $event = $this->agentTasks->recordEvent(
                (string)$request->input('actor_profile', ''),
                (string)$request->input('task_id', ''),
                (string)$request->input('workspace_id', ''),
                (string)$request->input('agent_session_id', ''),
                (string)$request->input('event_type', 'agent_event'),
                $payload,
            );

            return $this->json(200, ['ok' => true, 'event' => $event]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function session(Request $request): JsonResponse
    {
        try {
            $policy = $this->buildPolicy($request);
            if (!((bool)($policy['allowed'] ?? false))) {
                return $this->json(403, [
                    'ok' => false,
                    'policy' => $policy,
                    'error' => (string)($policy['reason'] ?? 'Нет прав на агентский чат.'),
                ]);
            }

            $session = $this->agentTasks->recordSession(
                (string)$request->input('actor_profile', ''),
                (string)$request->input('task_id', ''),
                (string)$request->input('workspace_id', ''),
                (string)$request->input('agent_session_id', ''),
                (string)$request->input('session_id', ''),
                (string)($policy['mode'] ?? $request->input('requested_mode', 'chat')),
                (string)$request->input('status', 'pending'),
                (string)$request->input('title', ''),
                $policy,
            );

            return $this->json(200, ['ok' => true, 'session' => $session]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function taskCardRead(Request $request): JsonResponse
    {
        return $this->taskCardOperation($request, 'read');
    }

    public function taskCardComment(Request $request): JsonResponse
    {
        return $this->taskCardOperation($request, 'comment');
    }

    public function taskCardQuestion(Request $request): JsonResponse
    {
        return $this->taskCardOperation($request, 'question');
    }

    public function taskCardChecklist(Request $request): JsonResponse
    {
        return $this->taskCardOperation($request, 'checklist');
    }

    public function taskCardChecklistItem(Request $request): JsonResponse
    {
        return $this->taskCardOperation($request, 'checklist_item');
    }

    public function taskCardAttachment(Request $request): JsonResponse
    {
        return $this->taskCardOperation($request, 'attachment');
    }

    public function taskCardStatus(Request $request): JsonResponse
    {
        return $this->taskCardOperation($request, 'status');
    }

    public function taskCardFinish(Request $request): JsonResponse
    {
        return $this->taskCardOperation($request, 'finish');
    }

    public function workspaceAccess(Request $request): JsonResponse
    {
        try {
            $actor = (string)$request->query('actor_profile', '');
            $workspaceId = (string)$request->query('workspace_id', '');
            return $this->json(200, [
                'ok' => true,
                'access' => $this->access->listWorkspaceAccess($actor, $workspaceId, $this->actorPhone($request)),
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(403, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function grantWorkspaceAccess(Request $request): JsonResponse
    {
        try {
            return $this->json(200, [
                'ok' => true,
                'grant' => $this->access->grantWorkspaceAccess(
                    (string)$request->input('actor_profile', ''),
                    (string)$request->input('profile_key', ''),
                    (string)$request->input('workspace_id', ''),
                    (string)$request->input('role', 'workspace_user'),
                    $this->actorPhone($request),
                ),
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(403, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function revokeWorkspaceAccess(Request $request): JsonResponse
    {
        try {
            $this->access->revokeWorkspaceAccess(
                (string)$request->input('actor_profile', ''),
                (string)$request->input('profile_key', ''),
                (string)$request->input('workspace_id', ''),
                $this->actorPhone($request),
            );
            return $this->json(200, ['ok' => true]);
        } catch (InvalidArgumentException $e) {
            return $this->json(403, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function audit(Request $request): JsonResponse
    {
        try {
            return $this->json(200, [
                'ok' => true,
                'audit' => $this->access->auditLogs(
                    (string)$request->query('actor_profile', ''),
                    (int)$request->query('limit', 100),
                    $this->actorPhone($request),
                ),
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(403, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    /** @return array<string, mixed> */
    private function buildPolicy(Request $request): array
    {
        return $this->access->agentPolicy(
            (string) $request->input('actor_profile', ''),
            (string) $request->input('task_type', 'feature'),
            (string) $request->input('requested_mode', ''),
            (string) $request->input('workspace_id', ''),
            (string) $request->input('task_id', ''),
            $this->actorPhone($request),
        );
    }

    private function taskCardOperation(Request $request, string $operation): JsonResponse
    {
        try {
            $policy = $this->buildPolicy($request);
            if (!((bool)($policy['allowed'] ?? false))) {
                return $this->json(403, [
                    'ok' => false,
                    'policy' => $policy,
                    'error' => (string)($policy['reason'] ?? 'Нет прав на операцию карточки.'),
                ]);
            }
            $this->validateTaskCardPolicyTicket($request, $policy);

            $snapshot = $this->agentTasks->applyTaskCardOperation(
                (string)$request->input('actor_profile', ''),
                (string)$request->input('task_id', ''),
                (string)$request->input('workspace_id', ''),
                (string)$request->input('agent_session_id', ''),
                $operation,
                $request->all(),
                $policy,
            );

            return $this->json(200, [
                'ok' => true,
                'policy' => $policy,
                'snapshot' => $snapshot,
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(403, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    /** @param array<string, mixed> $policy */
    private function validateTaskCardPolicyTicket(Request $request, array $policy): void
    {
        $ticketPolicy = $this->access->validatePolicyTicket(
            (string)$request->input('policy_ticket', ''),
            (string)config('sync.agent_policy_ticket_secret', ''),
        );
        foreach (['task_id', 'workspace_id', 'mode'] as $key) {
            if ((string)($ticketPolicy[$key] ?? '') !== (string)($policy[$key] ?? '')) {
                throw new InvalidArgumentException('policy ticket does not match task card request');
            }
        }
        $ticketProfile = (string)($ticketPolicy['profile_key'] ?? '');
        if ($ticketProfile !== '' && $ticketProfile !== (string)($policy['profile_key'] ?? '')) {
            throw new InvalidArgumentException('policy ticket does not match actor');
        }
    }

    private function json(int $status, array $payload): JsonResponse
    {
        return response()->json($payload, $status, [], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }

    private function actorPhone(Request $request): string
    {
        return trim((string) $request->query(
            'phone',
            (string) $request->input('actor_phone', (string) $request->input('phone', '')),
        ));
    }
}
