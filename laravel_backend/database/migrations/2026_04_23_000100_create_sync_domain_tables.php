<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tasks', function (Blueprint $table): void {
            $table->string('id', 64)->primary();
            $table->string('owner_key', 32);
            $table->boolean('is_family')->default(false);
            $table->string('title', 255);
            $table->text('details');
            $table->string('due_date', 16)->default('');
            $table->string('time_value', 16)->default('');
            $table->string('workflow_status', 32)->default('todo');
            $table->string('priority', 32)->default('medium');
            $table->json('tags_json');
            $table->json('participants_json');
            $table->integer('duration_minutes')->default(0);
            $table->string('updated_at', 32);
            $table->integer('version')->default(1);

            $table->index('updated_at', 'idx_tasks_updated_at');
            $table->index('owner_key', 'idx_tasks_owner');
        });

        Schema::create('family_tasks', function (Blueprint $table): void {
            $table->string('id', 64)->primary();
            $table->string('title', 255);
            $table->text('details');
            $table->string('due_date', 16)->default('');
            $table->string('time_value', 16)->default('');
            $table->string('workflow_status', 32)->default('todo');
            $table->json('participants_json');
            $table->integer('duration_minutes')->default(0);
            $table->string('updated_at', 32);
            $table->integer('version')->default(1);

            $table->index('updated_at', 'idx_family_tasks_updated_at');
        });

        Schema::create('sync_events', function (Blueprint $table): void {
            $table->string('event_id', 128)->primary();
            $table->string('source', 32);
            $table->string('created_at', 32);

            $table->index('created_at', 'idx_sync_events_created');
        });

        Schema::create('telegram_outbox', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->string('event_id', 128)->unique('uq_telegram_outbox_event');
            $table->json('payload_json');
            $table->string('status', 16)->default('pending');
            $table->integer('retry_count')->default(0);
            $table->string('next_retry_at', 32);
            $table->string('created_at', 32);
            $table->string('updated_at', 32);

            $table->index(['status', 'next_retry_at'], 'idx_telegram_outbox_status_next');
        });

        Schema::create('device_tokens', function (Blueprint $table): void {
            $table->string('token', 255)->primary();
            $table->string('profile_key', 32);
            $table->string('platform', 32)->default('android');
            $table->string('app_version', 64)->default('');
            $table->string('device_id', 128)->nullable();
            $table->boolean('is_active')->default(true);
            $table->string('last_seen_at', 32);
            $table->string('created_at', 32);
            $table->string('updated_at', 32);

            $table->index(['profile_key', 'is_active'], 'idx_device_tokens_profile_active');
            $table->index('last_seen_at', 'idx_device_tokens_seen');
        });

        Schema::create('push_outbox', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->string('event_id', 128);
            $table->string('token', 255);
            $table->string('profile_key', 32);
            $table->string('title', 180);
            $table->string('body_text', 512);
            $table->json('data_json');
            $table->string('status', 16)->default('pending');
            $table->integer('retry_count')->default(0);
            $table->string('next_retry_at', 32);
            $table->string('last_error', 512)->default('');
            $table->string('created_at', 32);
            $table->string('updated_at', 32);

            $table->unique(['event_id', 'token'], 'uq_push_outbox_event_token');
            $table->index(['status', 'next_retry_at'], 'idx_push_outbox_status_next');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('push_outbox');
        Schema::dropIfExists('device_tokens');
        Schema::dropIfExists('telegram_outbox');
        Schema::dropIfExists('sync_events');
        Schema::dropIfExists('family_tasks');
        Schema::dropIfExists('tasks');
    }
};
