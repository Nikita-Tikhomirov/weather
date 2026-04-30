<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('messenger_users', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->string('profile_key', 32)->unique('uq_messenger_users_profile');
            $table->string('phone_normalized', 32)->unique('uq_messenger_users_phone');
            $table->string('display_name', 120)->default('');
            $table->string('primary_device_id', 160);
            $table->string('created_at', 32);
            $table->string('updated_at', 32);

            $table->index('primary_device_id', 'idx_messenger_users_device');
        });

        Schema::create('messenger_devices', function (Blueprint $table): void {
            $table->string('device_id', 160)->primary();
            $table->unsignedBigInteger('user_id');
            $table->string('platform', 32)->default('android');
            $table->string('app_version', 64)->default('');
            $table->string('created_at', 32);
            $table->string('updated_at', 32);

            $table->index('user_id', 'idx_messenger_devices_user');
        });

        Schema::create('family_groups', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->string('owner_profile_key', 32);
            $table->string('title', 120)->default('Family');
            $table->string('created_at', 32);
            $table->string('updated_at', 32);

            $table->index('owner_profile_key', 'idx_family_groups_owner');
        });

        Schema::create('family_group_members', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->unsignedBigInteger('family_group_id');
            $table->string('profile_key', 32);
            $table->string('role', 32)->default('member');
            $table->string('joined_at', 32);

            $table->unique(['family_group_id', 'profile_key'], 'uq_family_group_profile');
            $table->index('profile_key', 'idx_family_members_profile');
        });

        Schema::create('chat_message_attachments', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->string('message_id', 32);
            $table->string('kind', 24);
            $table->string('asset_url', 1024);
            $table->json('image_meta_json')->nullable();
            $table->integer('sort_order')->default(0);
            $table->string('created_at', 32);

            $table->index(['message_id', 'sort_order'], 'idx_chat_attachments_message_sort');
        });

        Schema::create('chat_message_reactions', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->string('message_id', 32);
            $table->string('profile_key', 32);
            $table->string('reaction', 16);
            $table->string('created_at', 32);
            $table->string('updated_at', 32);

            $table->unique(['message_id', 'profile_key'], 'uq_chat_reaction_message_profile');
            $table->index(['message_id', 'reaction'], 'idx_chat_reaction_message_value');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('chat_message_reactions');
        Schema::dropIfExists('chat_message_attachments');
        Schema::dropIfExists('family_group_members');
        Schema::dropIfExists('family_groups');
        Schema::dropIfExists('messenger_devices');
        Schema::dropIfExists('messenger_users');
    }
};
