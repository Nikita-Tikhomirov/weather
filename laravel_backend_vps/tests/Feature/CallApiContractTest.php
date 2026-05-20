<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class CallApiContractTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        config(['sync.api_key' => 'prod-key', 'sync.locked_actor_profile' => '']);
    }

    #[Test]
    public function ended_direct_call_does_not_block_new_call_between_same_profiles(): void
    {
        $first = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/call/initiate', [
                'actor_profile' => 'nik',
                'conversation_key' => 'dm:nik:nastya',
                'call_type' => 'audio',
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true);

        $sessionId = data_get($first->json(), 'session.session_id');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/call/end', [
                'actor_profile' => 'nik',
                'session_id' => $sessionId,
            ])
            ->assertStatus(200)
            ->assertJsonPath('session.status', 'ended');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/call/initiate', [
                'actor_profile' => 'nik',
                'conversation_key' => 'dm:nik:nastya',
                'call_type' => 'audio',
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('session.status', 'ringing');
    }

    #[Test]
    public function stale_active_call_does_not_block_new_call_between_same_profiles(): void
    {
        $first = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/call/initiate', [
                'actor_profile' => 'nik',
                'conversation_key' => 'dm:nik:nastya',
                'call_type' => 'audio',
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true);

        $sessionId = data_get($first->json(), 'session.session_id');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/call/accept', [
                'actor_profile' => 'nastya',
                'session_id' => $sessionId,
            ])
            ->assertStatus(200)
            ->assertJsonPath('session.status', 'active');

        DB::table('call_sessions')->where('session_id', $sessionId)->update([
            'created_at' => now()->subMinutes(15)->format('Y-m-d\TH:i:s'),
            'updated_at' => now()->subMinutes(15)->format('Y-m-d\TH:i:s'),
        ]);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/call/initiate', [
                'actor_profile' => 'nik',
                'conversation_key' => 'dm:nik:nastya',
                'call_type' => 'audio',
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('session.status', 'ringing');
    }
}
