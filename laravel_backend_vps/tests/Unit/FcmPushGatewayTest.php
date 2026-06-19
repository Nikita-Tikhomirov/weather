<?php

namespace Tests\Unit;

use App\Services\Push\FcmPushGateway;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class FcmPushGatewayTest extends TestCase
{
    #[Test]
    public function chat_messages_are_data_only_so_native_service_can_show_actions(): void
    {
        config([
            'push.enabled' => true,
            'push.fcm.project_id' => 'demo-project',
            'push.fcm.client_email' => 'demo@example.com',
            'push.fcm.private_key' => 'configured',
        ]);
        Cache::put('push.fcm.oauth_token', 'oauth-token', now()->addMinutes(5));

        Http::fake([
            'https://fcm.googleapis.com/*' => Http::response(['name' => 'ok'], 200),
        ]);

        $result = (new FcmPushGateway())->sendToToken(
            'device-token',
            'Сообщение',
            'Текст',
            [
                'type' => 'chat_message',
                'entity' => 'chat_message',
                'conversation_key' => 'dm:u_001:u_042',
            ],
        );

        $this->assertTrue($result['success']);
        Http::assertSent(function ($request): bool {
            $payload = $request->data();
            $message = $payload['message'] ?? [];

            return !array_key_exists('notification', $message)
                && !array_key_exists('notification', $message['android'] ?? [])
                && ($message['android']['priority'] ?? '') === 'high'
                && ($message['data']['title'] ?? '') === 'Сообщение'
                && ($message['data']['body'] ?? '') === 'Текст'
                && ($message['data']['conversation_key'] ?? '') === 'dm:u_001:u_042';
        });
    }

    #[Test]
    public function incoming_calls_are_data_only_so_android_can_show_call_ui(): void
    {
        config([
            'push.enabled' => true,
            'push.fcm.project_id' => 'demo-project',
            'push.fcm.client_email' => 'demo@example.com',
            'push.fcm.private_key' => 'configured',
        ]);
        Cache::put('push.fcm.oauth_token', 'oauth-token', now()->addMinutes(5));

        Http::fake([
            'https://fcm.googleapis.com/*' => Http::response(['name' => 'ok'], 200),
        ]);

        $result = (new FcmPushGateway())->sendToToken(
            'device-token',
            'Аудиозвонок',
            'Входящий звонок от Мармеладка',
            [
                'type' => 'call_incoming',
                'event_id' => 'call-incoming-session-1',
                'session_id' => 'session-1',
                'call_type' => 'audio',
                'caller_profile' => 'marmeladka',
            ],
        );

        $this->assertTrue($result['success']);
        Http::assertSent(function ($request): bool {
            $payload = $request->data();
            $message = $payload['message'] ?? [];

            return !array_key_exists('notification', $message)
                && !array_key_exists('notification', $message['android'] ?? [])
                && ($message['android']['priority'] ?? '') === 'high'
                && ($message['android']['ttl'] ?? '') === '60s'
                && ($message['data']['type'] ?? '') === 'call_incoming'
                && ($message['data']['title'] ?? '') === 'Аудиозвонок'
                && ($message['data']['body'] ?? '') === 'Входящий звонок от Мармеладка'
                && ($message['data']['session_id'] ?? '') === 'session-1';
        });
    }

    #[Test]
    public function task_reminder_pushes_keep_notification_payload_for_system_delivery(): void
    {
        config([
            'push.enabled' => true,
            'push.fcm.project_id' => 'demo-project',
            'push.fcm.client_email' => 'demo@example.com',
            'push.fcm.private_key' => 'configured',
        ]);
        Cache::put('push.fcm.oauth_token', 'oauth-token', now()->addMinutes(5));

        Http::fake([
            'https://fcm.googleapis.com/*' => Http::response(['name' => 'ok'], 200),
        ]);

        $result = (new FcmPushGateway())->sendToToken(
            'device-token',
            'Напоминание',
            'Через 15 минут',
            [
                'type' => 'task_reminder',
                'entity' => 'task',
            ],
        );

        $this->assertTrue($result['success']);
        Http::assertSent(function ($request): bool {
            $payload = $request->data();
            $message = $payload['message'] ?? [];

            return ($message['notification']['title'] ?? '') === 'Напоминание'
                && ($message['notification']['body'] ?? '') === 'Через 15 минут'
                && ($message['android']['notification']['channel_id'] ?? '') === 'family_updates'
                && ($message['android']['priority'] ?? '') === 'high';
        });
    }
}
