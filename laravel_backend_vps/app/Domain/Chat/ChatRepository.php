<?php

namespace App\Domain\Chat;

use App\Domain\Sync\Profiles;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Str;
use InvalidArgumentException;

final class ChatRepository
{
    private const GROUP_KEY = 'group:common';

    public function bootstrap(string $actor): array
    {
        $actor = $this->resolveLegacyProfile($actor);
        $this->ensureActor($actor);
        $contacts = [];
        $conversations = [];

        foreach ($this->availableProfiles() as $profile) {
            if ($profile === $actor) {
                continue;
            }
            $dmKey = $this->directConversationKey($actor, $profile);
            $contacts[] = [
                'profile_key' => $profile,
                'display_name' => $this->profileLabel($profile),
                'phone' => $this->profilePhone($profile),
                'avatar_url' => $this->profileAvatarUrl($profile),
                'conversation_key' => $dmKey,
            ];
            $conversations[] = [
                'conversation_key' => $dmKey,
                'kind' => 'direct',
                'title' => '',
                'members' => [$actor, $profile],
            ];
        }
        if (DB::table('messenger_users')->count() === 0) {
            $this->ensureGroupConversation();
            $groupTitle = (string) (DB::table('chat_conversations')
                ->where('conversation_key', self::GROUP_KEY)
                ->value('title') ?? 'Общий');
            $conversations[] = [
                'conversation_key' => self::GROUP_KEY,
                'kind' => 'group',
                'title' => $groupTitle,
                'members' => Profiles::ALLOWED,
            ];
        }

        return [
            'contacts' => $contacts,
            'group' => DB::table('messenger_users')->count() === 0
                ? ['conversation_key' => self::GROUP_KEY, 'title' => $groupTitle ?? 'Общий']
                : ['conversation_key' => '', 'title' => ''],
            'conversations' => array_merge($conversations, $this->storedGroupConversations($actor)),
            'sticker_packs' => $this->stickerPacks(),
        ];
    }

    public function createGroupConversation(string $actor, string $title, array $members): array
    {
        $actor = $this->resolveLegacyProfile($actor);
        $this->ensureActor($actor);
        $profiles = [$actor];
        foreach ($members as $member) {
            $profile = trim((string)$member);
            if ($profile === '' || $profile === $actor) {
                continue;
            }
            $this->ensureActor($profile);
            if (!in_array($profile, $profiles, true)) {
                $profiles[] = $profile;
            }
        }
        if (count($profiles) < 2) {
            throw new InvalidArgumentException('Group requires at least two members');
        }

        $now = $this->nowIso();
        $key = 'grp:'.strtolower((string) Str::ulid());
        $name = trim($title) !== '' ? trim($title) : 'Group';
        DB::table('chat_conversations')->insert([
            'conversation_key' => $key,
            'kind' => 'group',
            'title' => $name,
            'created_at' => $now,
            'updated_at' => $now,
        ]);
        $conversationId = (int) DB::table('chat_conversations')->where('conversation_key', $key)->value('id');
        foreach ($profiles as $profile) {
            DB::table('chat_conversation_members')->insert([
                'conversation_id' => $conversationId,
                'profile_key' => $profile,
                'joined_at' => $now,
            ]);
        }

        return [
            'conversation_key' => $key,
            'kind' => 'group',
            'title' => $name,
            'members' => $profiles,
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
            $packKey = (string) $row->pack_key;
            $packs[$packKey] ??= ['pack_key' => $packKey, 'title' => $this->stickerPackTitle($packKey), 'items' => []];
            $packs[$packKey]['items'][] = [
                'sticker_id' => (string) $row->sticker_id,
                'title' => (string) $row->title,
                'asset_url' => (string) $row->asset_url,
                'sort_order' => (int) $row->sort_order,
            ];
        }

        return array_values($packs);
    }

    public function listMessages(string $actor, string $conversationKey, ?string $cursor, int $limit): array
    {
        $actor = $this->resolveLegacyProfile($actor);
        $conversation = $this->resolveConversationForActor($actor, $conversationKey);
        $responseConversationKey = $this->responseConversationKey(
            $conversationKey,
            (string) $conversation->conversation_key,
        );
        $query = DB::table('chat_messages')
            ->where('conversation_id', (int) $conversation->id)
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->limit($limit);

        if ($cursor !== null && trim($cursor) !== '') {
            $query->where('created_at', '<', trim($cursor));
        }

        $rows = $query->get();
        $mapped = [];
        foreach ($rows as $row) {
            $mapped[] = $this->mapMessageRow($row, $responseConversationKey, $actor);
        }

        $mapped = array_reverse($mapped);
        return [
            'conversation_key' => $responseConversationKey,
            'resolved_conversation_key' => (string) $conversation->conversation_key,
            'messages' => $mapped,
            'typing_profiles' => $this->typingProfiles(
                (int) $conversation->id,
                $actor,
                $this->conversationMembers($actor, (string) $conversation->conversation_key),
            ),
            'next_cursor' => count($rows) === $limit && $mapped !== [] ? (string) $mapped[0]['created_at'] : null,
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
        ?array $attachments,
        ?string $clientMessageId,
    ): array {
        $actor = $this->resolveLegacyProfile($actor);
        $conversation = $this->resolveConversationForActor($actor, $conversationKey);
        $type = $this->normalizeMessageType($messageType);
        $normalizedText = trim($text);
        $normalizedSticker = $stickerId !== null ? trim($stickerId) : null;
        $normalizedImageUrl = $imageUrl !== null ? trim($imageUrl) : null;
        $normalizedClientMessageId = $clientMessageId !== null ? trim($clientMessageId) : null;
        $normalizedAttachments = $this->normalizeAttachments($attachments ?? []);

        if ($normalizedClientMessageId !== null && $normalizedClientMessageId !== '') {
            $existing = DB::table('chat_messages')
                ->where('conversation_id', (int) $conversation->id)
                ->where('sender_profile', $actor)
                ->where('client_message_id', $normalizedClientMessageId)
                ->first();
            if ($existing !== null) {
                return $this->mapMessageRow($existing, (string) $conversation->conversation_key, $actor);
            }
        }

        if ($type === 'text' && $normalizedText === '') {
            throw new InvalidArgumentException('text is required for message_type=text');
        }
        if ($type === 'sticker' && ($normalizedSticker === null || $normalizedSticker === '')) {
            throw new InvalidArgumentException('sticker_id is required for message_type=sticker');
        }
        if ($type === 'image' && ($normalizedImageUrl === null || $normalizedImageUrl === '') && $normalizedAttachments === []) {
            throw new InvalidArgumentException('image_url is required for message_type=image');
        }
        if ($type === 'image_group' && $normalizedAttachments === []) {
            throw new InvalidArgumentException('attachments are required for message_type=image_group');
        }
        if ($type === 'video' && $normalizedAttachments === []) {
            throw new InvalidArgumentException('attachments are required for message_type=video');
        }
        if ($type === 'video_group' && $normalizedAttachments === []) {
            throw new InvalidArgumentException('attachments are required for message_type=video_group');
        }
        if ($type === 'audio' && $normalizedAttachments === []) {
            throw new InvalidArgumentException('attachments are required for message_type=audio');
        }

        $id = (string) Str::ulid();
        $createdAt = $this->nowIso();
        DB::table('chat_messages')->insert([
            'id' => $id,
            'conversation_id' => (int) $conversation->id,
            'sender_profile' => $actor,
            'message_type' => $type,
            'text' => $normalizedText !== '' ? $normalizedText : null,
            'sticker_id' => $normalizedSticker !== '' ? $normalizedSticker : null,
            'image_url' => $normalizedImageUrl !== '' ? $normalizedImageUrl : null,
            'image_meta_json' => $imageMeta !== null ? json_encode($imageMeta, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) : null,
            'client_message_id' => $normalizedClientMessageId !== '' ? $normalizedClientMessageId : null,
            'created_at' => $createdAt,
        ]);

        if ($type === 'image' && $normalizedImageUrl !== null && $normalizedImageUrl !== '') {
            $normalizedAttachments[] = ['kind' => 'image', 'asset_url' => $normalizedImageUrl, 'image_meta' => $imageMeta ?? [], 'sort_order' => 0];
        }
        foreach ($normalizedAttachments as $attachment) {
            DB::table('chat_message_attachments')->insert([
                'message_id' => $id,
                'kind' => $attachment['kind'],
                'asset_url' => $attachment['asset_url'],
                'image_meta_json' => json_encode($attachment['image_meta'], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES),
                'sort_order' => (int) $attachment['sort_order'],
                'created_at' => $createdAt,
            ]);
        }

        $row = DB::table('chat_messages')->where('id', $id)->first();
        return $this->mapMessageRow($row, (string) $conversation->conversation_key, $actor);
    }

    public function setReaction(string $actor, string $messageId, string $reaction): array
    {
        $actor = $this->resolveLegacyProfile($actor);
        $this->ensureActor($actor);
        $id = trim($messageId);
        if ($id === '') {
            throw new InvalidArgumentException('message_id is required');
        }
        $row = DB::table('chat_messages')->where('id', $id)->first();
        if ($row === null) {
            throw new InvalidArgumentException('Message not found');
        }
        $conversationKey = $this->conversationKeyById((int) $row->conversation_id);
        $this->resolveConversationForActor($actor, $conversationKey);

        $value = trim($reaction);
        if ($value === '') {
            DB::table('chat_message_reactions')->where('message_id', $id)->where('profile_key', $actor)->delete();
        } else {
            DB::table('chat_message_reactions')->updateOrInsert(
                ['message_id' => $id, 'profile_key' => $actor],
                ['reaction' => mb_substr($value, 0, 8), 'created_at' => $this->nowIso(), 'updated_at' => $this->nowIso()]
            );
        }

        $updated = DB::table('chat_messages')->where('id', $id)->first();
        return $this->mapMessageRow($updated, $conversationKey, $actor);
    }

    public function conversationMembers(string $actor, string $conversationKey): array
    {
        $actor = $this->resolveLegacyProfile($actor);
        $conversation = $this->resolveConversationForActor($actor, $conversationKey);
        return DB::table('chat_conversation_members')
            ->where('conversation_id', (int) $conversation->id)
            ->orderBy('profile_key')
            ->pluck('profile_key')
            ->map(static fn ($item): string => trim((string) $item))
            ->filter()
            ->values()
            ->all();
    }

    public function addMember(string $actor, string $conversationKey, string $profile): void
    {
        $actor = $this->resolveLegacyProfile($actor);
        $profile = $this->resolveLegacyProfile($profile);
        $this->ensureActor($profile);
        $conversation = $this->resolveConversationForActor($actor, $conversationKey);

        // Only group conversations support member management
        $convKind = (string) $conversation->kind;
        if ($convKind !== 'group') {
            throw new InvalidArgumentException('Can only add members to group conversations');
        }

        // Check if already a member
        $isMember = DB::table('chat_conversation_members')
            ->where('conversation_id', (int) $conversation->id)
            ->where('profile_key', $profile)
            ->exists();
        if ($isMember) {
            return;
        }

        $now = $this->nowIso();
        DB::table('chat_conversation_members')->insert([
            'conversation_id' => (int) $conversation->id,
            'profile_key' => $profile,
            'joined_at' => $now,
        ]);
    }

    public function markRead(string $actor, string $conversationKey): void
    {
        $actor = $this->resolveLegacyProfile($actor);
        $conversation = $this->resolveConversationForActor($actor, $conversationKey);
        if (!$this->hasTable('chat_read_cursors')) {
            return;
        }
        $now = $this->nowIso();
        DB::table('chat_read_cursors')->updateOrInsert(
            ['conversation_id' => (int)$conversation->id, 'profile_key' => $actor],
            ['read_at' => $now, 'updated_at' => $now],
        );
    }

    public function recordTyping(string $actor, string $conversationKey): void
    {
        $actor = $this->resolveLegacyProfile($actor);
        $conversation = $this->resolveConversationForActor($actor, $conversationKey);
        Cache::put($this->typingCacheKey((int) $conversation->id, $actor), $this->nowIso(), now()->addSeconds(7));
    }

    public function removeMember(string $actor, string $conversationKey, string $profile): void
    {
        $actor = $this->resolveLegacyProfile($actor);
        $profile = $this->resolveLegacyProfile($profile);
        $conversation = $this->resolveConversationForActor($actor, $conversationKey);

        $convKind = (string) $conversation->kind;
        if ($convKind !== 'group') {
            throw new InvalidArgumentException('Can only remove members from group conversations');
        }

        if ($profile === $actor) {
            throw new InvalidArgumentException('Cannot remove yourself');
        }

        DB::table('chat_conversation_members')
            ->where('conversation_id', (int) $conversation->id)
            ->where('profile_key', $profile)
            ->delete();
    }

    public function renameGroup(string $actor, string $conversationKey, string $title): void
    {
        $actor = $this->resolveLegacyProfile($actor);
        $conversation = $this->resolveGroupConversationForManagement($actor, $conversationKey);
        if ((string) $conversation->kind !== 'group') {
            throw new InvalidArgumentException('Can only rename group conversations');
        }
        $normalizedTitle = trim($title);
        if ($normalizedTitle === '') {
            throw new InvalidArgumentException('title is required');
        }
        if (mb_strlen($normalizedTitle) > 60) {
            $normalizedTitle = mb_substr($normalizedTitle, 0, 60);
        }
        DB::table('chat_conversations')
            ->where('id', (int) $conversation->id)
            ->update(['title' => $normalizedTitle, 'updated_at' => $this->nowIso()]);
    }

    public function deleteGroup(string $actor, string $conversationKey): void
    {
        $actor = $this->resolveLegacyProfile($actor);
        $conversation = $this->resolveGroupConversationForManagement($actor, $conversationKey);
        if ((string) $conversation->kind !== 'group') {
            throw new InvalidArgumentException('Can only delete group conversations');
        }
        $conversationId = (int) $conversation->id;
        $messageIds = DB::table('chat_messages')
            ->where('conversation_id', $conversationId)
            ->pluck('id')
            ->map(static fn ($item): string => (string) $item)
            ->all();

        DB::transaction(static function () use ($conversationId, $messageIds): void {
            if ($messageIds !== []) {
                DB::table('chat_message_attachments')->whereIn('message_id', $messageIds)->delete();
                DB::table('chat_message_reactions')->whereIn('message_id', $messageIds)->delete();
            }
            DB::table('chat_messages')->where('conversation_id', $conversationId)->delete();
            if (DB::getSchemaBuilder()->hasTable('chat_read_cursors')) {
                DB::table('chat_read_cursors')->where('conversation_id', $conversationId)->delete();
            }
            DB::table('chat_conversation_members')->where('conversation_id', $conversationId)->delete();
            DB::table('chat_conversations')->where('id', $conversationId)->delete();
        });
    }

    public function editMessage(string $actor, string $messageId, string $text): array
    {
        $actor = $this->resolveLegacyProfile($actor);
        $this->ensureActor($actor);
        $id = trim($messageId);
        $normalizedText = trim($text);
        if ($id === '' || $normalizedText === '') {
            throw new InvalidArgumentException('text is required');
        }
        $row = DB::table('chat_messages')->where('id', $id)->first();
        if ($row === null || (string) $row->sender_profile !== $actor || (string) $row->message_type !== 'text') {
            throw new InvalidArgumentException('Only sender can edit text message');
        }
        if (($row->deleted_at ?? null) !== null) {
            throw new InvalidArgumentException('Deleted message cannot be edited');
        }
        DB::table('chat_messages')->where('id', $id)->update(['text' => $normalizedText, 'edited_at' => $this->nowIso()]);
        $updated = DB::table('chat_messages')->where('id', $id)->first();
        return $this->mapMessageRow($updated, $this->conversationKeyById((int) $row->conversation_id), $actor);
    }

    public function deleteMessage(string $actor, string $messageId): array
    {
        $actor = $this->resolveLegacyProfile($actor);
        $this->ensureActor($actor);
        $id = trim($messageId);
        if ($id === '') {
            throw new InvalidArgumentException('message_id is required');
        }
        $row = DB::table('chat_messages')->where('id', $id)->first();
        if ($row === null || (string) $row->sender_profile !== $actor) {
            throw new InvalidArgumentException('Only sender can delete message');
        }
        DB::table('chat_messages')->where('id', $id)->update([
            'text' => null,
            'sticker_id' => null,
            'image_url' => null,
            'image_meta_json' => null,
            'deleted_at' => $this->nowIso(),
        ]);
        DB::table('chat_message_attachments')->where('message_id', $id)->delete();
        $updated = DB::table('chat_messages')->where('id', $id)->first();
        return $this->mapMessageRow($updated, $this->conversationKeyById((int) $row->conversation_id), $actor);
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
        } elseif (str_starts_with($key, 'grp:')) {
            // Dynamic group already stored.
        } else {
            $members = $this->parseDirectMembers($key);
            if ($members === null) {
                throw new InvalidArgumentException('Actor is not a member of this conversation');
            }
            $members = $this->resolveLegacyDirectMembers($members);
            if (!in_array($actor, $members, true)) {
                throw new InvalidArgumentException('Actor is not a member of this conversation');
            }
            $key = $this->directConversationKey($members[0], $members[1]);
            $this->ensureDirectConversation($members[0], $members[1]);
        }

        $conversation = DB::table('chat_conversations')->where('conversation_key', $key)->first();
        if ($conversation === null) {
            throw new InvalidArgumentException('Conversation not found');
        }
        $isMember = DB::table('chat_conversation_members')
            ->where('conversation_id', (int) $conversation->id)
            ->where('profile_key', $actor)
            ->exists();
        if (!$isMember) {
            throw new InvalidArgumentException('Actor is not a member of this conversation');
        }

        return $conversation;
    }

    private function resolveGroupConversationForManagement(string $actor, string $conversationKey): object
    {
        $this->ensureActor($actor);
        $key = trim($conversationKey);
        if ($key === '') {
            throw new InvalidArgumentException('conversation_key is required');
        }
        if ($key === self::GROUP_KEY) {
            $this->ensureGroupConversation();
        }
        $conversation = DB::table('chat_conversations')->where('conversation_key', $key)->first();
        if ($conversation === null) {
            throw new InvalidArgumentException('Conversation not found');
        }
        if ((string) $conversation->kind !== 'group') {
            throw new InvalidArgumentException('Can only manage group conversations');
        }
        return $conversation;
    }

    private function ensureGroupConversation(): void
    {
        $now = $this->nowIso();
        $exists = DB::table('chat_conversations')->where('conversation_key', self::GROUP_KEY)->exists();
        if (!$exists) {
            DB::table('chat_conversations')->insert([
                'conversation_key' => self::GROUP_KEY,
                'kind' => 'group',
                'title' => 'Общий',
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }
        $conversationId = (int) DB::table('chat_conversations')->where('conversation_key', self::GROUP_KEY)->value('id');
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
            ['kind' => 'direct', 'title' => '', 'created_at' => $now, 'updated_at' => $now]
        );
        $conversationId = (int) DB::table('chat_conversations')->where('conversation_key', $key)->value('id');
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
        foreach ([
            ['builtin-emoji-smile', 'emoji', ':)', 'emoji://grinning-face', 10],
            ['builtin-emoji-laugh', 'emoji', ':D', 'emoji://face-with-tears-of-joy', 20],
            ['builtin-emoji-heart', 'emoji', '<3', 'emoji://heart', 30],
            ['builtin-emoji-thumbs-up', 'emoji', '+1', 'emoji://thumbs-up', 40],
        ] as $item) {
            DB::table('chat_stickers')->updateOrInsert(
                ['sticker_id' => $item[0]],
                ['pack_key' => $item[1], 'title' => $item[2], 'asset_url' => $item[3], 'is_active' => 1, 'sort_order' => $item[4], 'created_at' => $now, 'updated_at' => $now]
            );
        }
    }

    private function stickerPackTitle(string $packKey): string
    {
        return match ($packKey) {
            'emoji' => 'Emoji',
            'funny' => 'Fun',
            'default' => 'Default',
            default => ucfirst($packKey),
        };
    }

    private function directConversationKey(string $a, string $b): string
    {
        $members = [$a, $b];
        sort($members);
        return sprintf('dm:%s:%s', $members[0], $members[1]);
    }

    private function parseDirectMembers(string $conversationKey): ?array
    {
        if (!preg_match('/^dm:([a-z0-9_]+):([a-z0-9_]+)$/', $conversationKey, $matches)) {
            return null;
        }
        $members = [$matches[1], $matches[2]];
        if ($members[0] === $members[1] || !$this->isAllowedProfile($members[0]) || !$this->isAllowedProfile($members[1])) {
            return null;
        }
        sort($members);
        return $members;
    }

    private function resolveLegacyDirectMembers(array $members): array
    {
        return array_map(fn (string $profile): string => $this->resolveLegacyProfile($profile), $members);
    }

    private function resolveLegacyProfile(string $profile): string
    {
        $key = trim($profile);
        $phone = match ($key) {
            'nik' => '79679812438',
            'misha' => '79206555644',
            'nastya' => '79109764267',
            default => '',
        };
        if ($phone === '') {
            return $key;
        }
        $dynamic = DB::table('messenger_users')->where('phone_normalized', $phone)->value('profile_key');
        return is_string($dynamic) && trim($dynamic) !== '' ? trim($dynamic) : $key;
    }

    private function responseConversationKey(string $requestedKey, string $resolvedKey): string
    {
        $trimmed = trim($requestedKey);
        if ($this->parseDirectMembers($trimmed) !== null) {
            return $trimmed;
        }
        return $resolvedKey;
    }

    private function mapMessageRow(object $row, string $conversationKey, ?string $viewer = null): array
    {
        $meta = $this->decodeJsonObject($row->image_meta_json ?? null);
        $attachments = DB::table('chat_message_attachments')
            ->where('message_id', (string) $row->id)
            ->orderBy('sort_order')
            ->orderBy('id')
            ->get()
            ->map(fn ($item): array => [
                'kind' => (string) $item->kind,
                'asset_url' => (string) $item->asset_url,
                'image_meta' => $this->decodeJsonObject($item->image_meta_json ?? null),
                'sort_order' => (int) $item->sort_order,
            ])
            ->values()
            ->all();
        $reactions = DB::table('chat_message_reactions')
            ->where('message_id', (string) $row->id)
            ->select('reaction', DB::raw('COUNT(*) as count'))
            ->groupBy('reaction')
            ->orderByDesc('count')
            ->orderBy('reaction')
            ->get()
            ->map(fn ($item): array => ['reaction' => (string) $item->reaction, 'count' => (int) $item->count])
            ->values()
            ->all();
        $myReaction = $viewer !== null && $viewer !== ''
            ? DB::table('chat_message_reactions')->where('message_id', (string) $row->id)->where('profile_key', $viewer)->value('reaction')
            : null;

        return [
            'id' => (string) $row->id,
            'conversation_key' => $conversationKey,
            'sender_profile' => (string) $row->sender_profile,
            'message_type' => (string) $row->message_type,
            'text' => (string) ($row->text ?? ''),
            'sticker_id' => $row->sticker_id !== null ? (string) $row->sticker_id : null,
            'image_url' => $row->image_url !== null ? (string) $row->image_url : null,
            'image_meta' => $meta,
            'attachments' => $attachments,
            'reactions' => $reactions,
            'my_reaction' => $myReaction !== null ? (string) $myReaction : null,
            'client_message_id' => $row->client_message_id !== null ? (string) $row->client_message_id : null,
            'created_at' => (string) $row->created_at,
            'edited_at' => ($row->edited_at ?? null) !== null ? (string) $row->edited_at : null,
            'deleted_at' => ($row->deleted_at ?? null) !== null ? (string) $row->deleted_at : null,
            'is_deleted' => ($row->deleted_at ?? null) !== null,
        ];
    }

    private function conversationKeyById(int $conversationId): string
    {
        $key = DB::table('chat_conversations')->where('id', $conversationId)->value('conversation_key');
        if ($key === null) {
            throw new InvalidArgumentException('Conversation not found');
        }
        return (string) $key;
    }

    private function normalizeMessageType(string $value): string
    {
        $type = trim($value);
        return in_array($type, ['text', 'sticker', 'image', 'image_group', 'voice', 'video', 'video_group', 'audio'], true) ? $type : 'text';
    }

    private function ensureActor(string $actor): void
    {
        if (!$this->isAllowedProfile(trim($actor))) {
            throw new InvalidArgumentException('Unknown actor_profile');
        }
    }

    private function hasTable(string $table): bool
    {
        return DB::getSchemaBuilder()->hasTable($table);
    }

    private function typingProfiles(int $conversationId, string $viewer, array $members): array
    {
        $out = [];
        foreach ($members as $member) {
            $profile = trim((string) $member);
            if ($profile === '' || $profile === $viewer) {
                continue;
            }
            if (Cache::has($this->typingCacheKey($conversationId, $profile))) {
                $out[] = $profile;
            }
        }
        return $out;
    }

    private function typingCacheKey(int $conversationId, string $profile): string
    {
        return sprintf('chat.typing.%d.%s', $conversationId, $profile);
    }

    private function isAllowedProfile(string $profile): bool
    {
        return Profiles::isAllowed($profile) || DB::table('messenger_users')->where('profile_key', $profile)->exists();
    }

    private function availableProfiles(): array
    {
        $dynamic = DB::table('messenger_users')->orderBy('display_name')->pluck('profile_key')->map(static fn ($item): string => (string) $item)->all();
        return $dynamic !== [] ? $dynamic : Profiles::ALLOWED;
    }

    private function profileLabel(string $profile): string
    {
        $label = DB::table('messenger_users')->where('profile_key', $profile)->value('display_name');
        return is_string($label) && trim($label) !== '' ? $label : $profile;
    }

    private function profilePhone(string $profile): string
    {
        $phone = DB::table('messenger_users')->where('profile_key', $profile)->value('phone_normalized');
        return is_string($phone) && trim($phone) !== '' ? trim($phone) : '';
    }

    private function profileAvatarUrl(string $profile): string
    {
        $url = DB::table('messenger_users')->where('profile_key', $profile)->value('avatar_url');
        return is_string($url) && trim($url) !== '' ? trim($url) : '';
    }

    private function storedGroupConversations(string $actor): array
    {
        $rows = DB::table('chat_conversation_members')
            ->join('chat_conversations', 'chat_conversations.id', '=', 'chat_conversation_members.conversation_id')
            ->where('chat_conversation_members.profile_key', $actor)
            ->where('chat_conversations.kind', 'group')
            ->orderByDesc('chat_conversations.updated_at')
            ->get(['chat_conversations.id', 'chat_conversations.conversation_key', 'chat_conversations.kind', 'chat_conversations.title']);

        $out = [];
        foreach ($rows as $row) {
            $members = DB::table('chat_conversation_members')
                ->where('conversation_id', (int) $row->id)
                ->orderBy('joined_at')
                ->orderBy('id')
                ->pluck('profile_key')
                ->map(static fn ($item): string => (string) $item)
                ->all();
            $out[] = ['conversation_key' => (string) $row->conversation_key, 'kind' => (string) $row->kind, 'title' => (string) $row->title, 'members' => $members];
        }
        return $out;
    }

    private function normalizeAttachments(array $attachments): array
    {
        $out = [];
        foreach ($attachments as $index => $item) {
            if (!is_array($item)) {
                continue;
            }
            $url = trim((string) ($item['asset_url'] ?? $item['image_url'] ?? ''));
            if ($url === '') {
                continue;
            }
            $meta = $item['image_meta'] ?? [];
            $out[] = ['kind' => trim((string) ($item['kind'] ?? 'image')) ?: 'image', 'asset_url' => $url, 'image_meta' => is_array($meta) ? $meta : [], 'sort_order' => (int) ($item['sort_order'] ?? $index)];
        }
        usort($out, static fn (array $a, array $b): int => $a['sort_order'] <=> $b['sort_order']);
        return $out;
    }

    private function decodeJsonObject(mixed $value): object
    {
        if (is_array($value)) {
            return (object) (array_is_list($value) ? [] : $value);
        }
        if (!is_string($value) || trim($value) === '') {
            return (object) [];
        }
        $decoded = json_decode($value, true);
        return (object) (is_array($decoded) && !array_is_list($decoded) ? $decoded : []);
    }

    private function nowIso(): string
    {
        return now()->format('Y-m-d\\TH:i:s');
    }
}
