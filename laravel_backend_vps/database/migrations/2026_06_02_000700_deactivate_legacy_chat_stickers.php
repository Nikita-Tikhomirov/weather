<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::table('chat_stickers')
            ->whereIn('pack_key', ['emoji', 'default'])
            ->orWhere('asset_url', 'like', 'emoji://%')
            ->orWhere('asset_url', 'like', '/stickers/default/%')
            ->orWhere('sticker_id', 'like', 'builtin-%')
            ->update([
                'is_active' => 0,
                'updated_at' => now()->format('Y-m-d\TH:i:s'),
            ]);
    }

    public function down(): void
    {
        DB::table('chat_stickers')
            ->whereIn('pack_key', ['emoji', 'default'])
            ->orWhere('asset_url', 'like', 'emoji://%')
            ->orWhere('asset_url', 'like', '/stickers/default/%')
            ->orWhere('sticker_id', 'like', 'builtin-%')
            ->update([
                'is_active' => 1,
                'updated_at' => now()->format('Y-m-d\TH:i:s'),
            ]);
    }
};
