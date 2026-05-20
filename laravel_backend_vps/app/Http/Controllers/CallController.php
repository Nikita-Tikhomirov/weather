<?php

namespace App\Http\Controllers;

use App\Domain\Call\CallRepository;
use App\Domain\Sync\ActorProfileGuard;
use App\Services\Push\PushOutboxService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use InvalidArgumentException;
use Throwable;

class CallController extends Controller
{
    public function __construct(
        private readonly CallRepository $call,
        private readonly PushOutboxService $pushOutbox,
    ) {
    }

    public function initiate(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed(
                (string) $request->input('actor_profile', '')
            );
            $conversationKey = (string) $request->input('conversation_key', '');
            $callType = (string) $request->input('call_type', 'audio');
            $calleeProfile = $request->input('callee_profile');

            $session = $this->call->initiate(
                $actor,
                $conversationKey,
                $callType,
                is_string($calleeProfile) ? $calleeProfile : null,
            );

            // Send push to callee
            $callee = $session['callee_profile'];
            $eventId = 'call-incoming-' . $session['session_id'];
            $typeLabel = $callType === 'video' ? 'Видеозвонок' : 'Аудиозвонок';
            $title = $typeLabel;
            $body = sprintf(
                'Входящий звонок от %s',
                $this->profileLabel($actor),
            );

            $this->pushOutbox->enqueueRawToRecipients(
                $eventId,
                [$callee],
                $title,
                $body,
                [
                    'type' => 'call_incoming',
                    'event_id' => $eventId,
                    'session_id' => $session['session_id'],
                    'call_type' => $callType,
                    'caller_profile' => $actor,
                    'conversation_key' => $conversationKey,
                ],
            );
            $this->pushOutbox->retryDue();

            return $this->json(200, [
                'ok' => true,
                'session' => $session,
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function accept(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed(
                (string) $request->input('actor_profile', '')
            );
            $sessionId = trim((string) $request->input('session_id', ''));

            $session = $this->call->accept($actor, $sessionId);

            // Notify caller that callee accepted
            $caller = $session['caller_profile'];
            $eventId = 'call-accepted-' . $sessionId;
            $this->pushOutbox->enqueueRawToRecipients(
                $eventId,
                [$caller],
                'Звонок принят',
                sprintf('%s принял(а) звонок', $this->profileLabel($actor)),
                [
                    'type' => 'call_accepted',
                    'event_id' => $eventId,
                    'session_id' => $sessionId,
                ],
            );
            $this->pushOutbox->retryDue();

            return $this->json(200, [
                'ok' => true,
                'session' => $session,
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function reject(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed(
                (string) $request->input('actor_profile', '')
            );
            $sessionId = trim((string) $request->input('session_id', ''));

            $session = $this->call->reject($actor, $sessionId);

            // Notify caller
            $caller = $session['caller_profile'];
            $eventId = 'call-rejected-' . $sessionId;
            $this->pushOutbox->enqueueRawToRecipients(
                $eventId,
                [$caller],
                'Звонок отклонён',
                sprintf('%s отклонил(а) звонок', $this->profileLabel($actor)),
                [
                    'type' => 'call_rejected',
                    'event_id' => $eventId,
                    'session_id' => $sessionId,
                ],
            );
            $this->pushOutbox->retryDue();

            return $this->json(200, [
                'ok' => true,
                'session' => $session,
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function end(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed(
                (string) $request->input('actor_profile', '')
            );
            $sessionId = trim((string) $request->input('session_id', ''));

            $session = $this->call->end($actor, $sessionId);

            return $this->json(200, [
                'ok' => true,
                'session' => $session,
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function signal(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed(
                (string) $request->input('actor_profile', '')
            );
            $sessionId = trim((string) $request->input('session_id', ''));
            $signalType = trim((string) $request->input('signal_type', ''));
            $sdp = $request->input('sdp');
            $candidate = $request->input('candidate');

            $encodedSdp = null;
            if ($sdp !== null) {
                $encodedSdp = is_string($sdp) ? $sdp : json_encode($sdp, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            }

            $encodedCandidate = null;
            if ($candidate !== null) {
                $encodedCandidate = is_string($candidate)
                    ? $candidate
                    : json_encode($candidate, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            }

            $this->call->storeSignal(
                $actor,
                $sessionId,
                $signalType,
                $encodedSdp,
                $encodedCandidate,
            );

            return $this->json(200, ['ok' => true]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function pollSignals(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed(
                (string) $request->input('actor_profile', '')
            );
            $sessionId = trim((string) $request->input('session_id', ''));
            $cursor = $request->input('cursor');
            $cursorStr = $cursor !== null ? trim((string) $cursor) : null;

            $result = $this->call->pollSignals($actor, $sessionId, $cursorStr);

            return $this->json(200, [
                'ok' => true,
                'signals' => $result['signals'],
                'cursor' => $result['cursor'],
                'session_status' => $result['session_status'],
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function incomingCall(Request $request): JsonResponse
    {
        try {
            $actor = ActorProfileGuard::ensureAllowed(
                (string) $request->input('actor_profile', '')
            );

            $session = $this->call->incomingCall($actor);

            return $this->json(200, [
                'ok' => true,
                'incoming_call' => $session,
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    private function json(int $status, array $payload): JsonResponse
    {
        return response()->json(
            $payload,
            $status,
            [],
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
        );
    }

    private function profileLabel(string $profile): string
    {
        return match (trim($profile)) {
            'nik' => 'Ник',
            'nastya' => 'Настя',
            'misha' => 'Миша',
            'arisha' => 'Ариша',
            default => 'Пользователь',
        };
    }
}
