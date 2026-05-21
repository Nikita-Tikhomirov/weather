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
    public function chat_messages_are_sent_data_only_so_apk_can_render_actions(): void
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
                'conversation_key' => 'dm:nik:nastya',
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
                && ($message['data']['conversation_key'] ?? '') === 'dm:nik:nastya';
        });
    }
}
