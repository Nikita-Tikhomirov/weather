<?php

namespace Tests\Feature;

use App\Contracts\PushGateway;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class SyncApiContractTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function health_endpoint_returns_contract_shape(): void
    {
        $response = $this->getJson('/health');

        $response
            ->assertStatus(200)
            ->assertJsonStructure(['ok', 'time'])
            ->assertJson(['ok' => true]);
    }

    #[Test]
    public function protected_sync_endpoint_rejects_missing_api_key_when_configured(): void
    {
        config(['sync.api_key' => 'prod-key']);

        $response = $this->getJson('/sync/pull?since=1970-01-01T00:00:00');

        $response
            ->assertStatus(401)
            ->assertJson([
                'ok' => false,
                'error' => 'Invalid API key',
            ]);
    }

    #[Test]
    public function push_then_changes_returns_expected_contract_fields(): void
    {
        config(['sync.api_key' => 'prod-key']);

        $pushPayload = [
            'actor_profile' => 'nik',
            'source' => 'mobile',
            'events' => [[
                'event_id' => 'feature-contract-1',
                'entity' => 'task',
                'action' => 'upsert',
                'payload' => [
                    'id' => 'feature-1',
                    'owner_key' => 'nik',
                    'is_family' => false,
                    'title' => 'Feature test task',
                    'details' => '',
                    'due_date' => '2026-04-23',
                    'time' => '11:00',
                    'workflow_status' => 'todo',
                    'priority' => 'medium',
                    'tags' => [],
                    'participants' => [],
                    'reminder_offsets_minutes' => [1440, 60, 30],
                    'duration_minutes' => 0,
                    'updated_at' => '2026-04-23T11:00:00',
                    'version' => 1,
                ],
                'happened_at' => '2026-04-23T11:00:00',
            ]],
        ];

        $push = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/sync_push.php', $pushPayload);

        $push
            ->assertStatus(200)
            ->assertJsonStructure([
                'ok',
                'accepted',
                'duplicates',
                'telegram',
                'push',
                'server_time',
            ])
            ->assertJson(['ok' => true, 'accepted' => 1]);

        $changes = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/sync/changes?cursor=1970-01-01T00:00:00&actor_profile=nik');

        $changes
            ->assertStatus(200)
            ->assertJsonStructure([
                'ok',
                'tasks',
                'family_tasks',
                'server_time',
                'cursor',
                'next_cursor',
                'mode',
                'routing_contract' => ['family_task_recipients', 'personal_task_visibility'],
            ])
            ->assertJsonPath('mode', 'changes');

        $this->assertSame('feature-1', data_get($changes->json(), 'tasks.0.id'));
        $this->assertSame('nik', data_get($changes->json(), 'tasks.0.owner_key'));
        $this->assertSame([1440, 60, 30], data_get($changes->json(), 'tasks.0.reminder_offsets_minutes'));
    }

    #[Test]
    public function device_register_returns_debug_fields(): void
    {
        config(['sync.api_key' => 'prod-key']);

        $response = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/devices_register.php', [
                'actor_profile' => 'nik',
                'token' => 'token-contract-1',
                'platform' => 'android',
                'app_version' => '0.1.3',
                'play_services' => 'available',
                'token_status' => 'active',
                'last_error' => '',
            ]);

        $response
            ->assertStatus(200)
            ->assertJsonStructure(['ok', 'token_status', 'play_services', 'registered_at'])
            ->assertJson([
                'ok' => true,
                'token_status' => 'active',
                'play_services' => 'available',
            ]);
    }

    #[Test]
    public function push_device_status_endpoint_returns_latest_status_for_actor(): void
    {
        config(['sync.api_key' => 'prod-key']);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/devices_status.php', [
                'actor_profile' => 'nik',
                'platform' => 'android',
                'token_status' => 'token_unavailable',
                'play_services' => 'unavailable_or_restricted',
                'last_error' => 'SERVICE_NOT_AVAILABLE',
                'app_version' => '0.1.3',
            ])
            ->assertStatus(200)
            ->assertJson(['ok' => true]);

        $response = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/push/device_status?actor_profile=nik');

        $response
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('result.actor_profile', 'nik')
            ->assertJsonPath('result.status.token_status', 'token_unavailable')
            ->assertJsonPath('result.status.play_services', 'unavailable_or_restricted');
    }

    #[Test]
    public function push_diagnostics_endpoint_returns_configuration_and_token_state(): void
    {
        config(['sync.api_key' => 'prod-key']);
        config(['push.enabled' => true]);

        DB::table('device_tokens')->insert([
            'token' => 'token-diag-1',
            'profile_key' => 'nik',
            'platform' => 'android',
            'app_version' => '0.1.6',
            'device_id' => 'device-diag-1',
            'is_active' => 1,
            'token_status' => 'active',
            'play_services' => 'available',
            'last_error' => '',
            'registered_at' => now()->format('Y-m-d\TH:i:s'),
            'last_seen_at' => now()->format('Y-m-d\TH:i:s'),
            'created_at' => now()->format('Y-m-d\TH:i:s'),
            'updated_at' => now()->format('Y-m-d\TH:i:s'),
        ]);

        DB::table('device_status')->insert([
            'profile_key' => 'nik',
            'platform' => 'android',
            'token_status' => 'active',
            'play_services' => 'available',
            'last_error' => '',
            'app_version' => '0.1.6',
            'device_id' => 'device-diag-1',
            'token' => 'token-diag-1',
            'updated_at' => now()->format('Y-m-d\TH:i:s'),
            'created_at' => now()->format('Y-m-d\TH:i:s'),
        ]);

        $response = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/push/diagnostics?actor_profile=nik');

        $response
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('actor_profile', 'nik')
            ->assertJsonPath('push.enabled', true)
            ->assertJsonPath('device_status.actor_profile', 'nik')
            ->assertJsonPath('tokens.0.profile_key', 'nik');
    }

    #[Test]
    public function push_test_endpoint_queues_and_attempts_delivery_for_actor(): void
    {
        config(['sync.api_key' => 'prod-key']);
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
            'token' => 'token-push-test-1',
            'profile_key' => 'nik',
            'platform' => 'android',
            'app_version' => '0.1.6',
            'device_id' => 'device-push-test-1',
            'is_active' => 1,
            'token_status' => 'active',
            'play_services' => 'available',
            'last_error' => '',
            'registered_at' => now()->format('Y-m-d\TH:i:s'),
            'last_seen_at' => now()->format('Y-m-d\TH:i:s'),
            'created_at' => now()->format('Y-m-d\TH:i:s'),
            'updated_at' => now()->format('Y-m-d\TH:i:s'),
        ]);

        $response = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/push/test', [
                'actor_profile' => 'nik',
                'title' => 'Diagnostic',
                'body' => 'Push test',
            ]);

        $response
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('queued', 1)
            ->assertJsonPath('push.sent', 1);
    }
}
