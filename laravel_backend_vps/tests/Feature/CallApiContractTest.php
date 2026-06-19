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
    public function initiate_queues_incoming_call_push_with_native_identity_fields(): void
    {
        $now = now()->format('Y-m-d\TH:i:s');
        DB::table('messenger_users')->insert([
            'profile_key' => 'nik',
            'phone_normalized' => '79679812438',
            'display_name' => 'Мармеладка',
            'primary_device_id' => 'caller-device',
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        DB::table('device_tokens')->insert([
            'token' => 'callee-token',
            'profile_key' => 'nastya',
            'platform' => 'android',
            'app_version' => '0.1.0',
            'device_id' => 'callee-device',
            'is_active' => 1,
            'last_seen_at' => $now,
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $response = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/call/initiate', [
                'actor_profile' => 'nik',
                'conversation_key' => 'dm:nik:nastya',
                'call_type' => 'video',
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('session.status', 'ringing');

        $sessionId = (string) data_get($response->json(), 'session.session_id');
        $row = DB::table('push_outbox')
            ->where('event_id', 'call-incoming-' . $sessionId)
            ->where('profile_key', 'nastya')
            ->first();

        $this->assertNotNull($row);
        $this->assertSame('Видеозвонок', (string) $row->title);
        $this->assertSame('Входящий звонок от Мармеладка', (string) $row->body_text);

        $data = json_decode((string) $row->data_json, true);
        $this->assertIsArray($data);
        $this->assertSame('call_incoming', $data['type'] ?? null);
        $this->assertSame($sessionId, $data['session_id'] ?? null);
        $this->assertSame('video', $data['call_type'] ?? null);
        $this->assertSame('nik', $data['caller_profile'] ?? null);
        $this->assertSame('Мармеладка', $data['caller_display_name'] ?? null);
        $this->assertSame('Мармеладка', $data['caller_name'] ?? null);
        $this->assertSame('nastya', $data['callee_profile'] ?? null);
        $this->assertSame('nastya', $data['recipient_profile'] ?? null);
        $this->assertSame('dm:nik:nastya', $data['conversation_key'] ?? null);
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
