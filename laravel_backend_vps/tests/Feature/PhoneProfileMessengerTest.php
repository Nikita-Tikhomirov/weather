<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class PhoneProfileMessengerTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        config(['sync.api_key' => 'prod-key', 'sync.locked_actor_profile' => '']);
    }

    #[Test]
    public function device_start_creates_and_restores_phone_profile_for_same_device(): void
    {
        $payload = [
            'phone' => '+7 (999) 111-22-33',
            'device_id' => 'device-a',
            'display_name' => 'Nikita',
        ];

        $first = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', $payload)
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('user.phone', '79991112233')
            ->assertJsonPath('user.display_name', 'Nikita');

        $second = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', $payload)
            ->assertStatus(200)
            ->assertJsonPath('ok', true);

        $this->assertSame(
            data_get($first->json(), 'user.profile_key'),
            data_get($second->json(), 'user.profile_key')
        );
    }

    #[Test]
    public function phone_reinstall_keeps_direct_chat_history_available(): void
    {
        $nik = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', [
                'phone' => '+7 999 111 22 33',
                'device_id' => 'nik-device-a',
                'display_name' => 'Nikita',
            ])
            ->assertStatus(200)
            ->json('user.profile_key');

        $silach = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', [
                'phone' => '+7 999 444 55 66',
                'device_id' => 'silach-device-a',
                'display_name' => 'Silach',
            ])
            ->assertStatus(200)
            ->json('user.profile_key');

        $conversationKey = collect([$nik, $silach])->sort()->values()->implode(':');
        $conversationKey = 'dm:'.$conversationKey;

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/messages/send', [
                'actor_profile' => $silach,
                'conversation_key' => $conversationKey,
                'message_type' => 'text',
                'text' => 'history survives reinstall',
                'client_message_id' => 'silach-1',
            ])
            ->assertStatus(200);

        $restoredNik = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', [
                'phone' => '+7 999 111 22 33',
                'device_id' => 'nik-device-after-reinstall',
                'display_name' => 'Nikita',
            ])
            ->assertStatus(200)
            ->json('user.profile_key');

        $this->assertSame($nik, $restoredNik);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/chat/messages?actor_profile='.$restoredNik.'&conversation_key='.$conversationKey.'&limit=20')
            ->assertStatus(200)
            ->assertJsonPath('messages.0.text', 'history survives reinstall');
    }

    #[Test]
    public function contacts_return_conversation_keys_that_load_history(): void
    {
        $nik = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', [
                'phone' => '+7 999 111 22 33',
                'device_id' => 'nik-device',
                'display_name' => 'Nikita',
            ])
            ->assertStatus(200)
            ->json('user.profile_key');

        $silach = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', [
                'phone' => '+7 999 444 55 66',
                'device_id' => 'silach-device',
                'display_name' => 'Silach',
            ])
            ->assertStatus(200)
            ->json('user.profile_key');

        $contact = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/contacts/resolve', [
                'actor_profile' => $nik,
                'phones' => ['+7 999 444 55 66'],
            ])
            ->assertStatus(200)
            ->assertJsonPath('contacts.0.profile_key', $silach)
            ->json('contacts.0');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/messages/send', [
                'actor_profile' => $silach,
                'conversation_key' => $contact['conversation_key'],
                'message_type' => 'text',
                'text' => 'opened from phone contact',
                'client_message_id' => 'silach-contact-1',
            ])
            ->assertStatus(200);

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->getJson('/chat/messages?actor_profile='.$nik.'&conversation_key='.$contact['conversation_key'].'&limit=20')
            ->assertStatus(200)
            ->assertJsonPath('messages.0.conversation_key', $contact['conversation_key'])
            ->assertJsonPath('messages.0.text', 'opened from phone contact');
    }

    #[Test]
    public function device_start_restores_existing_phone_from_new_device(): void
    {
        $first = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', [
                'phone' => '+7 999 111 22 33',
                'device_id' => 'device-a',
                'display_name' => 'Nikita',
            ])
            ->assertStatus(200)
            ->json('user.profile_key');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', [
                'phone' => '+7 999 111 22 33',
                'device_id' => 'device-b',
                'display_name' => 'Other',
            ])
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonPath('user.profile_key', $first);
    }

    #[Test]
    public function phone_profile_can_move_between_devices_without_losing_profile_key(): void
    {
        $first = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', [
                'phone' => '+7 999 111 22 33',
                'device_id' => 'device-a',
                'display_name' => 'Nikita',
            ])
            ->assertStatus(200)
            ->json('user.profile_key');

        $second = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', [
                'phone' => '+7 999 111 22 33',
                'device_id' => 'device-b',
                'display_name' => 'Nikita',
            ])
            ->assertStatus(200)
            ->assertJsonPath('user.device_id', 'device-b')
            ->json('user.profile_key');

        $this->assertSame($first, $second);

        $third = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', [
                'phone' => '+7 999 111 22 33',
                'device_id' => 'device-c',
                'display_name' => 'Other',
            ])
            ->assertStatus(200)
            ->json('user.profile_key');

        $this->assertSame($first, $third);
    }

    #[Test]
    public function contacts_resolve_returns_only_registered_phone_contacts(): void
    {
        $nik = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', [
                'phone' => '+7 999 111 22 33',
                'device_id' => 'device-a',
                'display_name' => 'Nikita',
            ])
            ->json('user.profile_key');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', [
                'phone' => '+7 999 444 55 66',
                'device_id' => 'device-b',
                'display_name' => 'Nastya',
            ])
            ->assertStatus(200);

        $response = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/contacts/resolve', [
                'actor_profile' => $nik,
                'phones' => ['+7 999 444 55 66', '+7 000 000 00 00'],
            ]);

        $response
            ->assertStatus(200)
            ->assertJsonPath('ok', true)
            ->assertJsonCount(1, 'contacts')
            ->assertJsonPath('contacts.0.display_name', 'Nastya');
    }

    #[Test]
    public function dynamic_users_can_create_groups_react_and_send_photo_group(): void
    {
        $nik = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', [
                'phone' => '+7 999 111 22 33',
                'device_id' => 'device-a',
                'display_name' => 'Nikita',
            ])
            ->json('user.profile_key');

        $nastya = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/auth/device-start', [
                'phone' => '+7 999 444 55 66',
                'device_id' => 'device-b',
                'display_name' => 'Nastya',
            ])
            ->json('user.profile_key');

        $groupKey = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/conversations', [
                'actor_profile' => $nik,
                'title' => 'Family',
                'member_profiles' => [$nastya],
            ])
            ->assertStatus(200)
            ->json('conversation.conversation_key');

        $message = $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/messages/send', [
                'actor_profile' => $nik,
                'conversation_key' => $groupKey,
                'message_type' => 'image_group',
                'attachments' => [
                    ['kind' => 'image', 'asset_url' => '/chat_uploads/1.jpg', 'image_meta' => ['w' => 1], 'sort_order' => 0],
                    ['kind' => 'image', 'asset_url' => '/chat_uploads/2.jpg', 'image_meta' => ['w' => 2], 'sort_order' => 1],
                ],
                'client_message_id' => 'photos-1',
            ])
            ->assertStatus(200)
            ->assertJsonPath('message.message_type', 'image_group')
            ->assertJsonCount(2, 'message.attachments')
            ->json('message');

        $this->withHeaders(['X-Api-Key' => 'prod-key'])
            ->postJson('/chat/messages/reaction', [
                'actor_profile' => $nastya,
                'message_id' => $message['id'],
                'reaction' => '❤️',
            ])
            ->assertStatus(200)
            ->assertJsonPath('message.reactions.0.reaction', '❤️')
            ->assertJsonPath('message.reactions.0.count', 1)
            ->assertJsonPath('message.my_reaction', '❤️');
    }
}
