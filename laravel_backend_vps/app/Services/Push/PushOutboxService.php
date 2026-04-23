<?php

namespace App\Services\Push;

use App\Contracts\PushGateway;
use App\Domain\Sync\SyncRepository;
use Illuminate\Support\Facades\DB;

class PushOutboxService
{
    public function __construct(
        private readonly PushGateway $gateway,
        private readonly PushMessageFactory $factory,
        private readonly SyncRepository $repo,
    ) {
    }

    public function isEnabled(): bool
    {
        return (bool) config('push.enabled', true);
    }

    public function isConfigured(): bool
    {
        return $this->isEnabled() && $this->gateway->isConfigured();
    }

    public function enqueueFromEvent(string $eventId, string $actor, string $entity, string $action, array $payload): int
    {
        if (!$this->isEnabled()) {
            return 0;
        }

        $message = $this->factory->build($actor, $entity, $action, $payload, $eventId);
        $recipients = $message['recipients'];
        if ($recipients === []) {
            return 0;
        }

        $rows = DB::table('device_tokens')
            ->select('token', 'profile_key')
            ->whereIn('profile_key', $recipients)
            ->where('is_active', 1)
            ->get();

        if ($rows->isEmpty()) {
            return 0;
        }

        $now = $this->nowIso();
        $count = 0;

        foreach ($rows as $row) {
            $token = trim((string) $row->token);
            if ($token === '') {
                continue;
            }
            $count++;
            DB::table('push_outbox')->updateOrInsert(
                [
                    'event_id' => $eventId,
                    'token' => $token,
                ],
                [
                    'profile_key' => (string) $row->profile_key,
                    'title' => $message['title'],
                    'body_text' => $message['body'],
                    'data_json' => json_encode($message['data'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                    'status' => 'pending',
                    'retry_count' => 0,
                    'next_retry_at' => $now,
                    'last_error' => '',
                    'created_at' => $now,
                    'updated_at' => $now,
                ]
            );
        }

        return $count;
    }

    /**
     * @return array{disabled:bool,sent:int,failed:int,pending:int,processed:int}
     */
    public function retryDue(int $limit = 100): array
    {
        if (!$this->isConfigured()) {
            return [
                'disabled' => true,
                'sent' => 0,
                'failed' => 0,
                'pending' => (int) DB::table('push_outbox')->where('status', 'pending')->count(),
                'processed' => 0,
            ];
        }

        $now = $this->nowIso();
        $dueRows = DB::table('push_outbox')
            ->where('status', 'pending')
            ->where('next_retry_at', '<=', $now)
            ->orderBy('id')
            ->limit(max(1, $limit))
            ->get();

        $sent = 0;
        $failed = 0;
        $processed = 0;
        $maxRetries = max(1, (int) config('push.max_retries', 5));
        $baseSec = max(5, (int) config('push.retry_base_sec', 20));
        $capSec = max($baseSec, (int) config('push.retry_cap_sec', 900));

        foreach ($dueRows as $row) {
            $processed++;
            $result = $this->gateway->sendToToken(
                (string) $row->token,
                (string) $row->title,
                (string) $row->body_text,
                $this->decodeJsonArray($row->data_json),
            );

            if (($result['success'] ?? false) === true) {
                $sent++;
                DB::table('push_outbox')
                    ->where('id', $row->id)
                    ->update([
                        'status' => 'sent',
                        'last_error' => '',
                        'updated_at' => $this->nowIso(),
                    ]);
                DB::table('device_tokens')
                    ->where('token', $row->token)
                    ->update([
                        'token_status' => 'active',
                        'last_error' => '',
                        'updated_at' => $this->nowIso(),
                    ]);
                continue;
            }

            $retryCount = (int) $row->retry_count + 1;
            $error = trim((string) ($result['error'] ?? 'unknown error'));
            $permanentFailure = (bool) ($result['permanent_failure'] ?? false);
            $exhausted = $retryCount >= $maxRetries;
            $status = ($permanentFailure || $exhausted) ? 'failed' : 'pending';
            if ($status === 'failed') {
                $failed++;
            }

            $delaySec = min($capSec, $baseSec * (2 ** max(0, $retryCount - 1)));
            $nextRetryAt = now()->addSeconds($delaySec)->format('Y-m-d\TH:i:s');

            DB::table('push_outbox')
                ->where('id', $row->id)
                ->update([
                    'status' => $status,
                    'retry_count' => $retryCount,
                    'last_error' => $error,
                    'next_retry_at' => $nextRetryAt,
                    'updated_at' => $this->nowIso(),
                ]);

            $this->repo->markDeviceTokenFailure((string) $row->token, $error, $permanentFailure);
        }

        $pending = (int) DB::table('push_outbox')->where('status', 'pending')->count();

        return [
            'disabled' => false,
            'sent' => $sent,
            'failed' => $failed,
            'pending' => $pending,
            'processed' => $processed,
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

    private function nowIso(): string
    {
        return now()->format('Y-m-d\TH:i:s');
    }
}
