<?php

namespace App\Domain\Chat;

use App\Domain\Sync\Profiles;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use InvalidArgumentException;

final class ChatRepository
{
    private const GROUP_KEY = 'group:common';

    public function bootstrap(string $actor): array
    {
        $this->ensureActor($actor);
        $this->ensureDefaultConversations();

        $contacts = [];
        $conversations = [];

        foreach (Profiles::ALLOWED as $profile) {
            if ($profile === $actor) {
                continue;
            }
            $dmKey = $this->directConversationKey($actor, $profile);
            $contacts[] = [
                'profile_key' => $profile,
                'conversation_key' => $dmKey,
            ];
            $conversations[] = [
                'conversation_key' => $dmKey,
                'kind' => 'direct',
                'title' => '',
                'members' => [$actor, $profile],
            ];
        }

        $conversations[] = [
            'conversation_key' => self::GROUP_KEY,
            'kind' => 'group',
            'title' => 'Общий',
            'members' => Profiles::ALLOWED,
        ];

        return [
            'contacts' => $contacts,
            'group' => [
                'conversation_key' => self::GROUP_KEY,
                'title' => 'Общий',
            ],
            'conversations' => $conversations,
            'sticker_packs' => $this->stickerPacks(),
        ];
    }

    public function stickerPacks(): array
    {
        $this->ensureDefaultStickerPacks();

        $rows = DB::table('chat_stickers')
            ->where('is_active', 1)
            ->orderBy('pack_key')
            ->orderBy('sort_order')
            ->orderBy('sticker_id')
            ->get();

        $packs = [];
        foreach ($rows as $row) {
            $packKey = (string)$row->pack_key;
            if (!array_key_exists($packKey, $packs)) {
                $packs[$packKey] = [
                    'pack_key' => $packKey,
                    'title' => $this->stickerPackTitle($packKey),
                    'items' => [],
                ];
            }
            $packs[$packKey]['items'][] = [
                'sticker_id' => (string)$row->sticker_id,
                'title' => (string)$row->title,
                'asset_url' => (string)$row->asset_url,
                'sort_order' => (int)$row->sort_order,
            ];
        }

        return array_values($packs);
    }

    public function listMessages(string $actor, string $conversationKey, ?string $cursor, int $limit): array
    {
        $conversation = $this->resolveConversationForActor($actor, $conversationKey);

        $query = DB::table('chat_messages')
            ->where('conversation_id', (int)$conversation->id)
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->limit($limit);

        if ($cursor !== null && trim($cursor) !== '') {
            $query->where('created_at', '<', trim($cursor));
        }

        $rows = $query->get();
        $mapped = [];
        foreach ($rows as $row) {
            $mapped[] = $this->mapMessageRow($row, $conversationKey);
        }

        $mapped = array_reverse($mapped);
        $nextCursor = null;
        if (count($rows) === $limit && !empty($mapped)) {
            $nextCursor = (string)$mapped[0]['created_at'];
        }

        return [
            'messages' => $mapped,
            'next_cursor' => $nextCursor,
        ];
    }

    public function sendMessage(
        string $actor,
        string $conversationKey,
        string $messageType,
        string $text,
        ?string $stickerId,
        ?string $imageUrl,
        ?array $imageMeta,
        ?string $clientMessageId,
    ): array {
        $conversation = $this->resolveConversationForActor($actor, $conversationKey);
        $type = $this->normalizeMessageType($messageType);

        $normalizedText = trim($text);
        $normalizedSticker = $stickerId !== null ? trim($stickerId) : null;
        $normalizedImageUrl = $imageUrl !== null ? trim($imageUrl) : null;
        $normalizedClientMessageId = $clientMessageId !== null ? trim($clientMessageId) : null;

        if ($normalizedClientMessageId !== null && $normalizedClientMessageId !== '') {
            $existing = DB::table('chat_messages')
                ->where('conversation_id', (int)$conversation->id)
                ->where('sender_profile', $actor)
                ->where('client_message_id', $normalizedClientMessageId)
                ->first();
            if ($existing !== null) {
                return $this->mapMessageRow($existing, $conversationKey);
            }
        }

        if ($type === 'text' && $normalizedText === '') {
            throw new InvalidArgumentException('text is required for message_type=text');
        }
        if ($type === 'sticker' && ($normalizedSticker === null || $normalizedSticker === '')) {
            throw new InvalidArgumentException('sticker_id is required for message_type=sticker');
        }
        if ($type === 'image' && ($normalizedImageUrl === null || $normalizedImageUrl === '')) {
            throw new InvalidArgumentException('image_url is required for message_type=image');
        }

        $id = (string)Str::ulid();
        $createdAt = $this->nowIso();

        DB::table('chat_messages')->insert([
            'id' => $id,
            'conversation_id' => (int)$conversation->id,
            'sender_profile' => $actor,
            'message_type' => $type,
            'text' => $normalizedText !== '' ? $normalizedText : null,
            'sticker_id' => $normalizedSticker !== '' ? $normalizedSticker : null,
            'image_url' => $normalizedImageUrl !== '' ? $normalizedImageUrl : null,
            'image_meta_json' => $imageMeta !== null ? json_encode($imageMeta, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) : null,
            'client_message_id' => $normalizedClientMessageId !== '' ? $normalizedClientMessageId : null,
            'created_at' => $createdAt,
        ]);

        $row = DB::table('chat_messages')->where('id', $id)->first();
        if ($row === null) {
            throw new InvalidArgumentException('Failed to persist chat message');
        }

        return $this->mapMessageRow($row, $conversationKey);
    }

    /**
     * @return array<int, string>
     */
    public function conversationMembers(string $actor, string $conversationKey): array
    {
        $conversation = $this->resolveConversationForActor($actor, $conversationKey);
        $rows = DB::table('chat_conversation_members')
            ->where('conversation_id', (int)$conversation->id)
            ->orderBy('profile_key')
            ->pluck('profile_key')
            ->all();

        return array_values(array_filter(array_map(static fn ($item) => trim((string)$item), $rows)));
    }

    public function editMessage(string $actor, string $messageId, string $text): array
    {
        $this->ensureActor($actor);
        $id = trim($messageId);
        $normalizedText = trim($text);
        if ($id === '') {
            throw new InvalidArgumentException('message_id is required');
        }
        if ($normalizedText === '') {
            throw new InvalidArgumentException('text is required');
        }

        $row = DB::table('chat_messages')->where('id', $id)->first();
        if ($row === null) {
            throw new InvalidArgumentException('Message not found');
        }
        if ((string)$row->sender_profile !== $actor) {
            throw new InvalidArgumentException('Only sender can edit message');
        }
        if ((string)$row->message_type !== 'text') {
            throw new InvalidArgumentException('Only text messages can be edited');
        }
        if (($row->deleted_at ?? null) !== null) {
            throw new InvalidArgumentException('Deleted message cannot be edited');
        }

        $editedAt = $this->nowIso();
        DB::table('chat_messages')
            ->where('id', $id)
            ->update([
                'text' => $normalizedText,
                'edited_at' => $editedAt,
            ]);

        $updated = DB::table('chat_messages')->where('id', $id)->first();
        $conversationKey = $this->conversationKeyById((int)$row->conversation_id);

        return $this->mapMessageRow($updated, $conversationKey);
    }

    public function deleteMessage(string $actor, string $messageId): array
    {
        $this->ensureActor($actor);
        $id = trim($messageId);
        if ($id === '') {
            throw new InvalidArgumentException('message_id is required');
        }

        $row = DB::table('chat_messages')->where('id', $id)->first();
        if ($row === null) {
            throw new InvalidArgumentException('Message not found');
        }
        if ((string)$row->sender_profile !== $actor) {
            throw new InvalidArgumentException('Only sender can delete message');
        }

        $deletedAt = $this->nowIso();
        DB::table('chat_messages')
            ->where('id', $id)
            ->update([
                'text' => null,
                'sticker_id' => null,
                'image_url' => null,
                'image_meta_json' => null,
                'deleted_at' => $deletedAt,
            ]);

        $updated = DB::table('chat_messages')->where('id', $id)->first();
        $conversationKey = $this->conversationKeyById((int)$row->conversation_id);

        return $this->mapMessageRow($updated, $conversationKey);
    }

    private function resolveConversationForActor(string $actor, string $conversationKey): object
    {
        $this->ensureActor($actor);
        $key = trim($conversationKey);
        if ($key === '') {
            throw new InvalidArgumentException('conversation_key is required');
        }

        if ($key === self::GROUP_KEY) {
            $this->ensureGroupConversation();
        } else {
            $members = $this->parseDirectMembers($key);
            if ($members === null) {
                throw new InvalidArgumentException('Unsupported conversation_key');
            }
            if (!in_array($actor, $members, true)) {
                throw new InvalidArgumentException('Actor is not a member of this conversation');
            }
            $this->ensureDirectConversation($members[0], $members[1]);
        }

        $conversation = DB::table('chat_conversations')->where('conversation_key', $key)->first();
        if ($conversation === null) {
            throw new InvalidArgumentException('Conversation not found');
        }

        $isMember = DB::table('chat_conversation_members')
            ->where('conversation_id', (int)$conversation->id)
            ->where('profile_key', $actor)
            ->exists();
        if (!$isMember) {
            throw new InvalidArgumentException('Actor is not a member of this conversation');
        }

        return $conversation;
    }

    private function ensureDefaultConversations(): void
    {
        $this->ensureGroupConversation();

        $profiles = Profiles::ALLOWED;
        sort($profiles);
        $count = count($profiles);

        for ($i = 0; $i < $count; $i++) {
            for ($j = $i + 1; $j < $count; $j++) {
                $this->ensureDirectConversation($profiles[$i], $profiles[$j]);
            }
        }
    }

    private function ensureGroupConversation(): void
    {
        $now = $this->nowIso();
        DB::table('chat_conversations')->updateOrInsert(
            ['conversation_key' => self::GROUP_KEY],
            [
                'kind' => 'group',
                'title' => 'Общий',
                'created_at' => $now,
                'updated_at' => $now,
            ]
        );

        $conversationId = (int)DB::table('chat_conversations')
            ->where('conversation_key', self::GROUP_KEY)
            ->value('id');

        foreach (Profiles::ALLOWED as $profile) {
            DB::table('chat_conversation_members')->updateOrInsert(
                ['conversation_id' => $conversationId, 'profile_key' => $profile],
                ['joined_at' => $now]
            );
        }
    }

    private function ensureDirectConversation(string $a, string $b): void
    {
        $this->ensureActor($a);
        $this->ensureActor($b);
        if ($a === $b) {
            throw new InvalidArgumentException('Direct conversation requires two different profiles');
        }

        $key = $this->directConversationKey($a, $b);
        $now = $this->nowIso();

        DB::table('chat_conversations')->updateOrInsert(
            ['conversation_key' => $key],
            [
                'kind' => 'direct',
                'title' => '',
                'created_at' => $now,
                'updated_at' => $now,
            ]
        );

        $conversationId = (int)DB::table('chat_conversations')
            ->where('conversation_key', $key)
            ->value('id');

        foreach ([$a, $b] as $profile) {
            DB::table('chat_conversation_members')->updateOrInsert(
                ['conversation_id' => $conversationId, 'profile_key' => $profile],
                ['joined_at' => $now]
            );
        }
    }

    private function ensureDefaultStickerPacks(): void
    {
        $now = $this->nowIso();
        $stickers = [
            ['builtin-emoji-smile', 'emoji', '😀', 'emoji://grinning-face', 10],
            ['builtin-emoji-laugh', 'emoji', '😂', 'emoji://face-with-tears-of-joy', 20],
            ['builtin-emoji-heart-eyes', 'emoji', '😍', 'emoji://smiling-face-with-heart-eyes', 30],
            ['builtin-emoji-hug', 'emoji', '🤗', 'emoji://hugging-face', 40],
            ['builtin-emoji-kiss', 'emoji', '😘', 'emoji://face-blowing-a-kiss', 50],
            ['builtin-emoji-thumbs-up', 'emoji', '👍', 'emoji://thumbs-up', 60],
            ['builtin-emoji-fire', 'emoji', '🔥', 'emoji://fire', 70],
            ['builtin-emoji-party', 'emoji', '🥳', 'emoji://partying-face', 80],
            ['builtin-funny-cat', 'funny', '😺', 'emoji://grinning-cat', 10],
            ['builtin-funny-monkey', 'funny', '🙈', 'emoji://see-no-evil-monkey', 20],
            ['builtin-funny-clown', 'funny', '🤡', 'emoji://clown-face', 30],
            ['builtin-funny-poop', 'funny', '💩', 'emoji://pile-of-poo', 40],
            ['builtin-funny-ghost', 'funny', '👻', 'emoji://ghost', 50],
            ['builtin-funny-alien', 'funny', '👽', 'emoji://alien', 60],
            ['builtin-funny-robot', 'funny', '🤖', 'emoji://robot', 70],
            ['builtin-funny-unicorn', 'funny', '🦄', 'emoji://unicorn', 80],
        ];

        foreach ($stickers as $item) {
            DB::table('chat_stickers')->updateOrInsert(
                ['sticker_id' => $item[0]],
                [
                    'pack_key' => $item[1],
                    'title' => $item[2],
                    'asset_url' => $item[3],
                    'is_active' => 1,
                    'sort_order' => $item[4],
                    'created_at' => $now,
                    'updated_at' => $now,
                ]
            );
        }
    }

    private function stickerPackTitle(string $packKey): string
    {
        return match ($packKey) {
            'emoji' => 'Эмодзи',
            'funny' => 'Весёлые',
            'default' => 'Стандартные',
            default => ucfirst($packKey),
        };
    }

    private function directConversationKey(string $a, string $b): string
    {
        $members = [$a, $b];
        sort($members);
        return sprintf('dm:%s:%s', $members[0], $members[1]);
    }

    /**
     * @return array<int, string>|null
     */
    private function parseDirectMembers(string $conversationKey): ?array
    {
        if (!preg_match('/^dm:([a-z0-9_]+):([a-z0-9_]+)$/', $conversationKey, $matches)) {
            return null;
        }

        $a = $matches[1];
        $b = $matches[2];
        if (!Profiles::isAllowed($a) || !Profiles::isAllowed($b) || $a === $b) {
            return null;
        }

        $members = [$a, $b];
        sort($members);

        if ($conversationKey !== sprintf('dm:%s:%s', $members[0], $members[1])) {
            return null;
        }

        return $members;
    }

    private function mapMessageRow(object $row, string $conversationKey): array
    {
        $meta = [];
        if (is_string($row->image_meta_json ?? null) && trim((string)$row->image_meta_json) !== '') {
            $decoded = json_decode((string)$row->image_meta_json, true);
            if (is_array($decoded)) {
                $meta = $decoded;
            }
        }

        return [
            'id' => (string)$row->id,
            'conversation_key' => $conversationKey,
            'sender_profile' => (string)$row->sender_profile,
            'message_type' => (string)$row->message_type,
            'text' => (string)($row->text ?? ''),
            'sticker_id' => $row->sticker_id !== null ? (string)$row->sticker_id : null,
            'image_url' => $row->image_url !== null ? (string)$row->image_url : null,
            'image_meta' => $meta,
            'client_message_id' => $row->client_message_id !== null ? (string)$row->client_message_id : null,
            'created_at' => (string)$row->created_at,
            'edited_at' => ($row->edited_at ?? null) !== null ? (string)$row->edited_at : null,
            'deleted_at' => ($row->deleted_at ?? null) !== null ? (string)$row->deleted_at : null,
            'is_deleted' => ($row->deleted_at ?? null) !== null,
        ];
    }

    private function conversationKeyById(int $conversationId): string
    {
        $key = DB::table('chat_conversations')
            ->where('id', $conversationId)
            ->value('conversation_key');
        if ($key === null) {
            throw new InvalidArgumentException('Conversation not found');
        }

        return (string)$key;
    }

    private function normalizeMessageType(string $value): string
    {
        $type = trim($value);
        return in_array($type, ['text', 'sticker', 'image'], true) ? $type : 'text';
    }

    private function ensureActor(string $actor): void
    {
        if (!Profiles::isAllowed(trim($actor))) {
            throw new InvalidArgumentException('Unknown actor_profile');
        }
    }

    private function nowIso(): string
    {
        return now()->format('Y-m-d\\TH:i:s');
    }
}
