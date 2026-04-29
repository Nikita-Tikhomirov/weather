<?php

namespace App\Http\Controllers;

use App\Domain\Chat\ChatRepository;
use App\Domain\Sync\ProfileRequestGuard;
use App\Services\Push\PushOutboxService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use InvalidArgumentException;
use Throwable;

class ChatController extends Controller
{
    public function __construct(
        private readonly ChatRepository $chat,
        private readonly PushOutboxService $pushOutbox,
    )
    {
    }

    public function bootstrap(Request $request): JsonResponse
    {
        try {
            $actor = ProfileRequestGuard::ensureAllowed($request, (string)$request->query('actor_profile', ''));
            $payload = $this->chat->bootstrap($actor);

            return $this->json(200, [
                'ok' => true,
                'actor_profile' => $actor,
                'contacts' => $payload['contacts'],
                'group' => $payload['group'],
                'conversations' => $payload['conversations'],
                'sticker_packs' => $payload['sticker_packs'],
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function messages(Request $request): JsonResponse
    {
        try {
            $actor = ProfileRequestGuard::ensureAllowed($request, (string)$request->query('actor_profile', ''));
            $conversationKey = trim((string)$request->query('conversation_key', ''));
            $cursor = trim((string)$request->query('cursor', ''));
            $limitRaw = (int)$request->query('limit', 50);
            $limit = max(1, min(100, $limitRaw));

            $result = $this->chat->listMessages(
                $actor,
                $conversationKey,
                $cursor !== '' ? $cursor : null,
                $limit,
            );

            return $this->json(200, [
                'ok' => true,
                'conversation_key' => $conversationKey,
                'messages' => $result['messages'],
                'next_cursor' => $result['next_cursor'],
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function sendMessage(Request $request): JsonResponse
    {
        try {
            $actor = ProfileRequestGuard::ensureAllowed($request, (string)$request->input('actor_profile', ''));
            $conversationKey = trim((string)$request->input('conversation_key', ''));
            $messageType = trim((string)$request->input('message_type', 'text'));
            $text = (string)$request->input('text', '');
            $stickerId = $request->input('sticker_id');
            $imageUrl = $request->input('image_url');
            $imageMeta = $request->input('image_meta');
            $clientMessageId = $request->input('client_message_id');

            $message = $this->chat->sendMessage(
                $actor,
                $conversationKey,
                $messageType,
                $text,
                is_string($stickerId) ? $stickerId : null,
                is_string($imageUrl) ? $imageUrl : null,
                is_array($imageMeta) ? $imageMeta : null,
                is_string($clientMessageId) ? $clientMessageId : null,
            );

            $recipients = $this->chat->conversationMembers($actor, $conversationKey);
            $recipients = array_values(array_filter($recipients, static fn (string $profile) => $profile !== $actor));
            if ($recipients !== []) {
                $eventId = sprintf('chat-msg-%s', $message['id']);
                $title = sprintf('Сообщение от %s', $this->profileLabel($actor));
                $body = $this->chatMessageBody($message);
                $data = [
                    'event_id' => $eventId,
                    'entity' => 'chat_message',
                    'action' => 'created',
                    'actor_profile' => $actor,
                    'conversation_key' => $conversationKey,
                    'message_id' => (string)$message['id'],
                ];
                $this->pushOutbox->enqueueRawToRecipients($eventId, $recipients, $title, $body, $data);
                $this->pushOutbox->retryDue();
            }

            return $this->json(200, [
                'ok' => true,
                'message' => $message,
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function uploadSticker(Request $request): JsonResponse
    {
        try {
            $actor = ProfileRequestGuard::ensureAllowed($request, (string)$request->input('actor_profile', ''));

            $upload = $request->file('image');
            if ($upload === null || !$upload->isValid()) {
                throw new InvalidArgumentException('image file is required');
            }

            $ext = strtolower((string)$upload->getClientOriginalExtension());
            if (!in_array($ext, ['jpg', 'jpeg', 'png', 'webp'], true)) {
                $ext = 'png';
            }

            $filename = sprintf('%s.%s', Str::ulid(), $ext);
            $path = Storage::disk('public')->putFileAs('chat_stickers', $upload, $filename);
            if ($path === false) {
                throw new InvalidArgumentException('Failed to upload image');
            }
            $publicDir = public_path('chat_stickers');
            if (!is_dir($publicDir) && !mkdir($publicDir, 0755, true) && !is_dir($publicDir)) {
                throw new InvalidArgumentException('Failed to prepare public image directory');
            }
            $publicPath = $publicDir . DIRECTORY_SEPARATOR . $filename;
            if (!copy(Storage::disk('public')->path($path), $publicPath)) {
                throw new InvalidArgumentException('Failed to publish uploaded image');
            }

            $url = sprintf('/chat_stickers/%s', $filename);
            $meta = [
                'size_bytes' => (int)$upload->getSize(),
                'mime_type' => (string)$upload->getMimeType(),
                'original_name' => (string)$upload->getClientOriginalName(),
            ];

            return $this->json(200, [
                'ok' => true,
                'asset_url' => $url,
                'image_meta' => $meta,
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function editMessage(Request $request): JsonResponse
    {
        try {
            $actor = ProfileRequestGuard::ensureAllowed($request, (string)$request->input('actor_profile', ''));
            $messageId = trim((string)$request->input('message_id', ''));
            $text = (string)$request->input('text', '');
            $message = $this->chat->editMessage($actor, $messageId, $text);

            return $this->json(200, [
                'ok' => true,
                'message' => $message,
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function deleteMessage(Request $request): JsonResponse
    {
        try {
            $actor = ProfileRequestGuard::ensureAllowed($request, (string)$request->input('actor_profile', ''));
            $messageId = trim((string)$request->input('message_id', ''));
            $message = $this->chat->deleteMessage($actor, $messageId);

            return $this->json(200, [
                'ok' => true,
                'message' => $message,
            ]);
        } catch (InvalidArgumentException $e) {
            return $this->json(400, ['ok' => false, 'error' => $e->getMessage()]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    public function stickerPacks(): JsonResponse
    {
        try {
            return $this->json(200, [
                'ok' => true,
                'sticker_packs' => $this->chat->stickerPacks(),
            ]);
        } catch (Throwable $e) {
            return $this->json(500, ['ok' => false, 'error' => $e->getMessage()]);
        }
    }

    private function json(int $status, array $payload): JsonResponse
    {
        return response()->json($payload, $status, [], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }

    private function profileLabel(string $profile): string
    {
        return match (trim($profile)) {
            'nik' => 'Ник',
            'nastya' => 'Настя',
            'misha' => 'Миша',
            'arisha' => 'Ариша',
            default => 'Семья',
        };
    }

    private function chatMessageBody(array $message): string
    {
        $type = trim((string)($message['message_type'] ?? 'text'));
        if ($type === 'sticker') {
            return 'Отправлен стикер';
        }
        if ($type === 'image') {
            return 'Отправлено изображение';
        }

        $text = trim((string)($message['text'] ?? ''));
        if ($text === '') {
            return 'Новое сообщение';
        }

        return mb_strlen($text) > 120 ? mb_substr($text, 0, 120).'…' : $text;
    }
}
