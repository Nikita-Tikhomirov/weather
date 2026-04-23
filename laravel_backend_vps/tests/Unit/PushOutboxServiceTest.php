<?php

namespace Tests\Unit;

use App\Contracts\PushGateway;
use App\Services\Push\PushOutboxService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class PushOutboxServiceTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function it_enqueues_and_sends_push_for_registered_device(): void
    {
        config(['push.enabled' => true]);
        $gateway = new class implements PushGateway
        {
            public function isConfigured(): bool
            {
                return true;
            }

            public function sendToToken(string $token, string $title, string $body, array $data): array
            {
                return ['success' => true, 'permanent_failure' => false, 'error' => ''];
            }
        };
        $this->app->instance(PushGateway::class, $gateway);

        DB::table('device_tokens')->insert([
            'token' => 'token-1',
            'profile_key' => 'nik',
            'platform' => 'android',
            'app_version' => '0.1.0',
            'device_id' => 'dev-1',
            'is_active' => 1,
            'last_seen_at' => now()->format('Y-m-d\TH:i:s'),
            'created_at' => now()->format('Y-m-d\TH:i:s'),
            'updated_at' => now()->format('Y-m-d\TH:i:s'),
        ]);

        /** @var PushOutboxService $service */
        $service = $this->app->make(PushOutboxService::class);
        $queued = $service->enqueueFromEvent(
            'evt-1',
            'nik',
            'task',
            'upsert',
            ['owner_key' => 'nik', 'title' => 'Тест']
        );

        $this->assertSame(1, $queued);
        $stats = $service->retryDue();

        $this->assertFalse($stats['disabled']);
        $this->assertSame(1, $stats['sent']);
        $this->assertSame(0, $stats['failed']);
        $this->assertSame(0, $stats['pending']);

        $this->assertDatabaseHas('push_outbox', [
            'event_id' => 'evt-1',
            'token' => 'token-1',
            'status' => 'sent',
        ]);
    }

    #[Test]
    public function retry_due_returns_disabled_when_gateway_not_configured(): void
    {
        config(['push.enabled' => true]);
        $gateway = new class implements PushGateway
        {
            public function isConfigured(): bool
            {
                return false;
            }

            public function sendToToken(string $token, string $title, string $body, array $data): array
            {
                return ['success' => false, 'permanent_failure' => false, 'error' => 'disabled'];
            }
        };
        $this->app->instance(PushGateway::class, $gateway);

        DB::table('push_outbox')->insert([
            'event_id' => 'evt-2',
            'token' => 'token-2',
            'profile_key' => 'nik',
            'title' => 'Title',
            'body_text' => 'Body',
            'data_json' => '{}',
            'status' => 'pending',
            'retry_count' => 0,
            'next_retry_at' => now()->format('Y-m-d\TH:i:s'),
            'last_error' => '',
            'created_at' => now()->format('Y-m-d\TH:i:s'),
            'updated_at' => now()->format('Y-m-d\TH:i:s'),
        ]);

        /** @var PushOutboxService $service */
        $service = $this->app->make(PushOutboxService::class);
        $stats = $service->retryDue();

        $this->assertTrue($stats['disabled']);
        $this->assertSame(1, $stats['pending']);
    }
}
