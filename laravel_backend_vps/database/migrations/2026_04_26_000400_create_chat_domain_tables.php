<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('chat_conversations', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->string('conversation_key', 64)->unique('uq_chat_conversations_key');
            $table->string('kind', 16);
            $table->string('title', 120)->default('');
            $table->string('created_at', 32);
            $table->string('updated_at', 32);
        });

        Schema::create('chat_conversation_members', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->unsignedBigInteger('conversation_id');
            $table->string('profile_key', 32);
            $table->string('joined_at', 32);

            $table->unique(['conversation_id', 'profile_key'], 'uq_chat_members_conv_profile');
            $table->index('profile_key', 'idx_chat_members_profile');
            $table->index('joined_at', 'idx_chat_members_joined');
        });

        Schema::create('chat_messages', function (Blueprint $table): void {
            $table->string('id', 32)->primary();
            $table->unsignedBigInteger('conversation_id');
            $table->string('sender_profile', 32);
            $table->string('message_type', 16);
            $table->text('text')->nullable();
            $table->string('sticker_id', 64)->nullable();
            $table->string('image_url', 1024)->nullable();
            $table->json('image_meta_json')->nullable();
            $table->string('client_message_id', 96)->nullable();
            $table->string('created_at', 32);
            $table->string('edited_at', 32)->nullable();
            $table->string('deleted_at', 32)->nullable();

            $table->index(['conversation_id', 'created_at'], 'idx_chat_messages_conv_created');
            $table->index(['sender_profile', 'created_at'], 'idx_chat_messages_sender_created');
            $table->unique(['conversation_id', 'sender_profile', 'client_message_id'], 'uq_chat_messages_idem');
        });

        Schema::create('chat_stickers', function (Blueprint $table): void {
            $table->string('sticker_id', 64)->primary();
            $table->string('pack_key', 64);
            $table->string('title', 120);
            $table->string('asset_url', 1024);
            $table->boolean('is_active')->default(true);
            $table->integer('sort_order')->default(0);
            $table->string('created_at', 32);
            $table->string('updated_at', 32);

            $table->index(['pack_key', 'sort_order'], 'idx_chat_stickers_pack_sort');
            $table->index('is_active', 'idx_chat_stickers_active');
        });

        $now = now()->format('Y-m-d\TH:i:s');
        DB::table('chat_stickers')->insert([
            [
                'sticker_id' => 'builtin-smile-wave',
                'pack_key' => 'default',
                'title' => 'Smile Wave',
                'asset_url' => '/stickers/default/smile-wave.png',
                'is_active' => 1,
                'sort_order' => 10,
                'created_at' => $now,
                'updated_at' => $now,
            ],
            [
                'sticker_id' => 'builtin-party-cat',
                'pack_key' => 'default',
                'title' => 'Party Cat',
                'asset_url' => '/stickers/default/party-cat.png',
                'is_active' => 1,
                'sort_order' => 20,
                'created_at' => $now,
                'updated_at' => $now,
            ],
        ]);
    }

    public function down(): void
    {
        Schema::dropIfExists('chat_stickers');
        Schema::dropIfExists('chat_messages');
        Schema::dropIfExists('chat_conversation_members');
        Schema::dropIfExists('chat_conversations');
    }
};
