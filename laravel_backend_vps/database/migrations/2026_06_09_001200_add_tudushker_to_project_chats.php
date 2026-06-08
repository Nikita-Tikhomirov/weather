<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('chat_conversations') || !Schema::hasTable('chat_conversation_members')) {
            return;
        }

        $now = now()->toIso8601String();
        $ids = DB::table('chat_conversations')
            ->where('conversation_key', 'like', 'grp:project:%')
            ->pluck('id');

        foreach ($ids as $id) {
            DB::table('chat_conversation_members')->updateOrInsert(
                [
                    'conversation_id' => (int) $id,
                    'profile_key' => 'tudushker',
                ],
                ['joined_at' => $now],
            );
        }
    }

    public function down(): void
    {
        if (!Schema::hasTable('chat_conversation_members') || !Schema::hasTable('chat_conversations')) {
            return;
        }

        $ids = DB::table('chat_conversations')
            ->where('conversation_key', 'like', 'grp:project:%')
            ->pluck('id')
            ->map(static fn ($id): int => (int) $id)
            ->all();

        if ($ids === []) {
            return;
        }

        DB::table('chat_conversation_members')
            ->where('profile_key', 'tudushker')
            ->whereIn('conversation_id', $ids)
            ->delete();
    }
};
