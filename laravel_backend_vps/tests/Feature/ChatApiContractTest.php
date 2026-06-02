<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class ChatApiContractTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        config(['sync.locked_actor_profile' => '']);
    }

    #[Test]
    public function sticker_import_activates_generated_v2_stickers_and_deactivates_old_rows(): void
    {
        config(['chat.media_disk' => 'public']);
        Storage::fake('public');
        DB::table('chat_stickers')->insert([
            'sticker_id' => 'builtin-emoji-smile',
            'pack_key' => 'emoji',
            'title' => ':)',
            'asset_url' => 'emoji://grinning-face',
            'is_active' => 1,
            'sort_order' => 1,
            'created_at' => now()->format('Y-m-d\TH:i:s'),
            'updated_at' => now()->format('Y-m-d\TH:i:s'),
        ]);

        $source = sys_get_temp_dir().DIRECTORY_SEPARATOR.'stickers_'.bin2hex(random_bytes(6));
        $v2Dir = $source.DIRECTORY_SEPARATOR.'library_v2'.DIRECTORY_SEPARATOR.'rats'.DIRECTORY_SEPARATOR.'plush_3d'.DIRECTORY_SEPARATOR.'emotions';
        $gen1Dir = $source.DIRECTORY_SEPARATOR.'library'.DIRECTORY_SEPARATOR.'rats'.DIRECTORY_SEPARATOR.'plush_3d'.DIRECTORY_SEPARATOR.'emotions';
        mkdir($v2Dir, 0777, true);
        mkdir($gen1Dir, 0777, true);
        file_put_contents($v2Dir.DIRECTORY_SEPARATOR.'rats_plush_3d_emotions_001.png', 'png-v2');
        file_put_contents($gen1Dir.DIRECTORY_SEPARATOR.'rats_plush_3d_emotions_001.png', 'png-gen1');

        Artisan::call('chat:stickers-import', ['source' => $source]);

        $this->assertSame(
            0,
            (int) DB::table('chat_stickers')
                ->where('sticker_id', 'builtin-emoji-smile')
                ->value('is_active'),
        );
        $this->assertDatabaseHas('chat_stickers', [
            'sticker_id' => 'rats_plush_3d_emotions_001',
            'pack_key' => 'rats_plush_3d_emotions',
            'is_active' => 1,
        ]);
        $this->assertDatabaseHas('chat_stickers', [
            'sticker_id' => 'gen1_rats_plush_3d_emotions_001',
            'pack_key' => 'rats_plush_3d_emotions',
            'is_active' => 1,
        ]);
        $this->assertSame(
            2,
            (int) DB::table('chat_stickers')->where('is_active', 1)->count(),
        );
        Storage::disk('public')->assertExists('chat_stickers/rats_plush_3d_emotions/rats_plush_3d_emotions_001.png');
        Storage::disk('public')->assertExists('chat_stickers/gen1/rats_plush_3d_emotions/rats_plush_3d_emotions_001.png');
    }

    #[Test]
    public function bootstrap_returns_contacts_group_and_sticker_packs(): void
    {
        config(['sync.api_key' => 'prod-key']);
        DB::table('chat_stickers')->insert([
            'sticker_id' => 'rats_plush_3d_emotions_001',
            'pack_key' => 'rats_plush_3d_emotions',
            'title' => 'happy nod',
            'asset_url' => 'https://s3.example.test/stickers/rats_plush_3d_emotions_001.png',
            'is_active' => 1,
            'sort_order' => 1,
            'created_at' => now()->format('Y-m-d\TH:i:s'),
            'updated_at' => now()->format('Y-m-d\TH:i:s'),
        ]);

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
        $conversations = data_get($response->json(), 'conversations', []);
        $this->assertSame(
            [],
            array_values(array_filter(
                $conversations,
                static fn (array $item): bool => ($item['kind'] ?? '') === 'direct',
            )),
        );

        $packs = data_get($response->json(), 'sticker_packs', []);
        $this->assertNotEmpty($packs);
        $this->assertSame('rats_plush_3d_emotions', data_get($packs, '0.pack_key'));
        $this->assertSame(
            'https://s3.example.test/stickers/rats_plush_3d_emotions_001.png',
            data_get($packs, '0.items.0.asset_url'),
        );
        $this->assertFalse(
            collect($packs)->pluck('pack_key')->contains('emoji'),
        );
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
    public function locked_actor_profile_rejects_chat_requests_for_other_profiles(): void
    {
        config([
            'sync.api_key' => 'prod-key',
            'sync.locked_actor_profile' => 'misha',
        ]);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/chat/bootstrap?actor_profile=misha')
            ->assertStatus(200)
            ->assertJsonPath('actor_profile', 'misha');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/chat/bootstrap?actor_profile=nik')
            ->assertStatus(400)
            ->assertJsonPath('ok', false)
            ->assertJsonPath('error', 'Profile switching is disabled');
    }

    #[Test]
    public function upload_sticker_endpoint_returns_asset_url_and_meta(): void
    {
        Storage::fake('public');
        config(['sync.api_key' => 'prod-key']);

        $response = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->post('/chat/stickers/upload', [
                'actor_profile' => 'nik',
                'image' => UploadedFile::fake()->create(
                    'sticker.png',
                    16,
                    'image/png'
                ),
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
    public function group_conversation_can_be_renamed_and_deleted(): void
    {
        config(['sync.api_key' => 'prod-key']);

        $created = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/conversations', [
                'actor_profile' => 'nik',
                'title' => 'Старая группа',
                'member_profiles' => ['nastya', 'misha'],
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true);

        $conversationKey = data_get($created->json(), 'conversation.conversation_key');
        $this->assertNotEmpty($conversationKey);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/conversations/rename', [
                'actor_profile' => 'nik',
                'conversation_key' => $conversationKey,
                'title' => 'Нужная группа',
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/chat/bootstrap?actor_profile=nik')
            ->assertStatus(200)
            ->assertJsonFragment([
                'conversation_key' => $conversationKey,
                'title' => 'Нужная группа',
            ])
            ->assertJsonPath('conversations.0.members.0', 'nik');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/conversations/delete', [
                'actor_profile' => 'nik',
                'conversation_key' => $conversationKey,
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/chat/messages?actor_profile=nik&conversation_key='.$conversationKey)
            ->assertStatus(400)
            ->assertJsonPath('ok', false);
    }

    #[Test]
    public function common_group_title_can_be_changed_and_group_can_be_deleted(): void
    {
        config(['sync.api_key' => 'prod-key']);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/chat/bootstrap?actor_profile=nik')
            ->assertStatus(200);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/conversations/rename', [
                'actor_profile' => 'nik',
                'conversation_key' => 'group:common',
                'title' => 'Дом',
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/chat/bootstrap?actor_profile=nik')
            ->assertStatus(200)
            ->assertJsonFragment([
                'conversation_key' => 'group:common',
                'title' => 'Дом',
            ]);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/conversations/delete', [
                'actor_profile' => 'nik',
                'conversation_key' => 'group:common',
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true);
    }

    #[Test]
    public function legacy_group_without_actor_membership_can_be_deleted(): void
    {
        config(['sync.api_key' => 'prod-key']);

        \Illuminate\Support\Facades\DB::table('chat_conversations')->insert([
            'conversation_key' => 'grp:legacy_without_member',
            'kind' => 'group',
            'title' => 'Старый общий',
            'created_at' => now()->format('Y-m-d\TH:i:s'),
            'updated_at' => now()->format('Y-m-d\TH:i:s'),
        ]);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/conversations/delete', [
                'actor_profile' => 'nik',
                'conversation_key' => 'grp:legacy_without_member',
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true);

        $this->assertDatabaseMissing('chat_conversations', [
            'conversation_key' => 'grp:legacy_without_member',
        ]);
    }

    #[Test]
    public function typing_profiles_are_reported_to_other_members(): void
    {
        config(['sync.api_key' => 'prod-key']);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/typing', [
                'actor_profile' => 'nik',
                'conversation_key' => 'dm:nik:nastya',
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/chat/messages?actor_profile=nastya&conversation_key=dm:nik:nastya')
            ->assertStatus(200)
            ->assertJsonPath('typing_profiles.0', 'nik');
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
