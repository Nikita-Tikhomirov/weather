<?php

namespace App\Http\Controllers;

use App\Domain\Leads\LeadRepository;
use App\Domain\Sync\ActorProfileGuard;
use App\Services\Push\PushOutboxService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use InvalidArgumentException;
use Throwable;

class LeadController extends Controller
{
    public function __construct(
        private readonly LeadRepository $leads,
        private readonly PushOutboxService $pushOutbox,
    ) {
    }

    public function ingest(Request $request): JsonResponse
    {
        try {
            $phone = preg_replace('/\D+/', '', (string)$request->input('owner_phone', '')) ?: '';
            $expected = preg_replace('/\D+/', '', (string)config('sync.superadmin_phone')) ?: '';
            if ($phone === '' || $phone !== $expected) {
                throw new InvalidArgumentException('Lead owner phone is not allowed');
            }
            $lead = $this->leads->ingest($request->all(), $this->leads->profileForPhone($phone));
            $this->notify($lead, 'Новый заказ', (string)$lead['title']);
            return $this->json(200, ['ok' => true, 'lead' => $lead]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function index(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed((string)$request->query('actor_profile', ''));
            return $this->json(200, ['ok' => true, 'leads' => $this->leads->listForOwner($actor)]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function show(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed((string)$request->query('actor_profile', ''));
            $lead = $this->leads->findForOwner((int)$request->query('lead_id', 0), $actor);
            return $this->json(200, ['ok' => true, 'lead' => $lead]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function create(Request $request): JsonResponse
    {
        return $this->ownerAction($request, 'Новый заказ', function (int $leadId, string $actor) use ($request): array {
            unset($leadId);
            return $this->leads->createForOwner($actor, $request->all());
        }, false);
    }

    public function edit(Request $request): JsonResponse
    {
        return $this->ownerAction($request, 'edited', function (int $leadId, string $actor) use ($request): array {
            return $this->leads->edit($leadId, $actor, $request->all());
        });
    }

    public function approve(Request $request): JsonResponse
    {
        return $this->ownerAction($request, 'Одобрен заказ', function (int $leadId, string $actor): array {
            return $this->leads->approve($leadId, $actor);
        });
    }

    public function reject(Request $request): JsonResponse
    {
        return $this->ownerAction($request, 'Заказ отклонен', function (int $leadId, string $actor): array {
            return $this->leads->reject($leadId, $actor);
        });
    }

    public function delete(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed((string)$request->input('actor_profile', ''));
            $lead = $this->leads->delete((int)$request->input('lead_id', 0), $actor);
            $this->notify($lead, 'Заказ удален', (string)$lead['title']);
            return $this->json(200, ['ok' => true, 'deleted' => true]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function commands(Request $request): JsonResponse
    {
        return $this->json(200, ['ok' => true, 'commands' => $this->leads->approvedCommands()]);
    }

    public function claim(Request $request): JsonResponse
    {
        try {
            $lead = $this->leads->claim((int)$request->input('lead_id', 0), trim((string)$request->input('executor_id', '')));
            return $this->json(200, ['ok' => true, 'lead' => $lead]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function result(Request $request): JsonResponse
    {
        try {
            $lead = $this->leads->reportResult(
                (int)$request->input('lead_id', 0),
                trim((string)$request->input('executor_id', '')),
                (bool)$request->input('sent', false),
                (string)$request->input('error', ''),
            );
            $this->notify($lead, $lead['status'] === 'sent' ? 'Отклик отправлен' : 'Ошибка отправки', (string)$lead['title']);
            return $this->json(200, ['ok' => true, 'lead' => $lead]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    private function ownerAction(Request $request, string $title, callable $action, bool $requiresLeadId = true): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed((string)$request->input('actor_profile', ''));
            $lead = $action($requiresLeadId ? (int)$request->input('lead_id', 0) : 0, $actor);
            $this->notify($lead, $title, (string)$lead['title']);
            return $this->json(200, ['ok' => true, 'lead' => $lead]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    private function notify(array $lead, string $title, string $body): void
    {
        $eventId = 'kwork-lead-'.(int)$lead['id'].'-v'.(int)$lead['version'];
        $this->pushOutbox->enqueueRawToRecipients(
            $eventId,
            [(string)$lead['owner_profile']],
            $title,
            mb_strlen($body) > 120 ? mb_substr($body, 0, 120).'…' : $body,
            ['type' => 'kwork_lead', 'lead_id' => (string)$lead['id'], 'status' => (string)$lead['status']],
        );
        $this->pushOutbox->retryDue();
    }

    private function json(int $status, array $payload): JsonResponse
    {
        return response()->json($payload, $status, [], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }
}
