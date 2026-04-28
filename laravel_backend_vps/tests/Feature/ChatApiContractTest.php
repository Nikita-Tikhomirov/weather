<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class ChatApiContractTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function bootstrap_returns_contacts_group_and_sticker_packs(): void
    {
        config(['sync.api_key' => 'prod-key']);

        $response = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/chat/bootstrap?actor_profile=nik');

        $response
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('actor_profile', 'nik')
            ->assertJsonPath('group.conversation_key', 'group:common');

        $contacts = data_get($response->json(), 'contacts', []);
        $this->assertCount(3, $contacts);
        $this->assertSame('nastya', data_get($contacts, '0.profile_key'));

        $packs = data_get($response->json(), 'sticker_packs', []);
        $this->assertNotEmpty($packs);
    }

    #[Test]
    public function send_and_read_text_message_returns_message_history(): void
    {
        config(['sync.api_key' => 'prod-key']);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/chat/bootstrap?actor_profile=nik')
            ->assertStatus(200);

        $send = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/messages/send', [
                'actor_profile' => 'nik',
                'conversation_key' => 'dm:nik:nastya',
                'message_type' => 'text',
                'text' => 'Привет, Настя!',
                'client_message_id' => 'msg-1',
            ]);

        $send
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('message.sender_profile', 'nik')
            ->assertJsonPath('message.message_type', 'text');

        $messages = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/chat/messages?actor_profile=nastya&conversation_key=dm:nik:nastya&limit=20');

        $messages
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('messages.0.text', 'Привет, Настя!');
    }

    #[Test]
    public function send_with_same_client_message_id_is_idempotent(): void
    {
        config(['sync.api_key' => 'prod-key']);

        $payload = [
            'actor_profile' => 'nik',
            'conversation_key' => 'dm:nik:misha',
            'message_type' => 'text',
            'text' => 'Повтор не дублируй',
            'client_message_id' => 'dup-42',
        ];

        $first = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/messages/send', $payload)
            ->assertStatus(200);

        $second = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/messages/send', $payload)
            ->assertStatus(200);

        $this->assertSame(
            data_get($first->json(), 'message.id'),
            data_get($second->json(), 'message.id')
        );
    }

    #[Test]
    public function actor_cannot_read_direct_conversation_where_not_member(): void
    {
        config(['sync.api_key' => 'prod-key']);

        $response = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/chat/messages?actor_profile=arisha&conversation_key=dm:nik:nastya');

        $response
            ->assertStatus(400)
            ->assertJsonPath('ok', false);
    }

    #[Test]
    public function upload_sticker_endpoint_returns_asset_url_and_meta(): void
    {
        Storage::fake('public');
        config(['sync.api_key' => 'prod-key']);

        $response = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->post('/chat/stickers/upload', [
                'actor_profile' => 'nik',
                'image' => UploadedFile::fake()->image('sticker.png', 256, 256),
            ]);

        $response
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonStructure(['asset_url', 'image_meta']);
    }

    #[Test]
    public function send_builtin_sticker_message_is_accepted(): void
    {
        config(['sync.api_key' => 'prod-key']);

        $response = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/messages/send', [
                'actor_profile' => 'misha',
                'conversation_key' => 'group:common',
                'message_type' => 'sticker',
                'sticker_id' => 'builtin-party-cat',
                'client_message_id' => 'sticker-1',
            ]);

        $response
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('message.message_type', 'sticker')
            ->assertJsonPath('message.sticker_id', 'builtin-party-cat');
    }

    #[Test]
    public function sender_can_edit_and_delete_own_text_message(): void
    {
        config(['sync.api_key' => 'prod-key']);

        $send = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/messages/send', [
                'actor_profile' => 'nik',
                'conversation_key' => 'dm:nik:nastya',
                'message_type' => 'text',
                'text' => 'Первый текст',
                'client_message_id' => 'edit-delete-1',
            ])
            ->assertStatus(200);

        $messageId = data_get($send->json(), 'message.id');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/messages/edit', [
                'actor_profile' => 'nik',
                'message_id' => $messageId,
                'text' => 'Исправленный текст',
            ])
            ->assertStatus(200)
            ->assertJsonPath('message.text', 'Исправленный текст')
            ->assertJsonPath('message.is_deleted', false);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/messages/delete', [
                'actor_profile' => 'nik',
                'message_id' => $messageId,
            ])
            ->assertStatus(200)
            ->assertJsonPath('message.text', '')
            ->assertJsonPath('message.is_deleted', true);
    }

    #[Test]
    public function actor_cannot_edit_or_delete_foreign_message(): void
    {
        config(['sync.api_key' => 'prod-key']);

        $send = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/messages/send', [
                'actor_profile' => 'nik',
                'conversation_key' => 'dm:nik:nastya',
                'message_type' => 'text',
                'text' => 'Чужой текст',
                'client_message_id' => 'foreign-1',
            ])
            ->assertStatus(200);

        $messageId = data_get($send->json(), 'message.id');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/messages/edit', [
                'actor_profile' => 'nastya',
                'message_id' => $messageId,
                'text' => 'Попытка правки',
            ])
            ->assertStatus(400)
            ->assertJsonPath('ok', false);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/messages/delete', [
                'actor_profile' => 'nastya',
                'message_id' => $messageId,
            ])
            ->assertStatus(400)
            ->assertJsonPath('ok', false);
    }
}
