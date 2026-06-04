<?php

namespace App\Http\Controllers;

use App\Domain\Access\AccessPolicyService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use InvalidArgumentException;
use Throwable;

class AgentPolicyController extends Controller
{
    public function __construct(private readonly AccessPolicyService $access)
    {
    }

    public function access(Request $request): JsonResponse
    {
        try {
            $actor = trim((string) $request->query('actor_profile', (string) $request->input('actor_profile', '')));
            $phone = trim((string) $request->query('phone', (string) $request->input('phone', '')));
            $payload = $actor !== ''
                ? $this->access->accessForActor($actor)
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

    /** @return array<string, mixed> */
    private function buildPolicy(Request $request): array
    {
        return $this->access->agentPolicy(
            (string) $request->input('actor_profile', ''),
            (string) $request->input('task_type', 'feature'),
            (string) $request->input('requested_mode', ''),
            (string) $request->input('workspace_id', ''),
            (string) $request->input('task_id', ''),
        );
    }

    private function json(int $status, array $payload): JsonResponse
    {
        return response()->json($payload, $status, [], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }
}
