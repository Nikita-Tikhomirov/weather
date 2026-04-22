<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
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
    }
}
