<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tasks', function (Blueprint $table): void {
            $table->json('reminder_offsets_json')->nullable()->after('participants_json');
        });

        Schema::table('family_tasks', function (Blueprint $table): void {
            $table->json('reminder_offsets_json')->nullable()->after('participants_json');
        });

        Schema::create('task_reminders', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->string('entity', 16);
            $table->string('task_storage_id', 64);
            $table->string('recipient_key', 32);
            $table->integer('offset_minutes');
            $table->string('due_at', 32);
            $table->string('remind_at', 32);
            $table->json('payload_json');
            $table->string('status', 16)->default('pending');
            $table->string('sent_event_id', 128)->nullable();
            $table->string('created_at', 32);
            $table->string('updated_at', 32);

            $table->unique(
                ['entity', 'task_storage_id', 'recipient_key', 'due_at', 'offset_minutes'],
                'uq_task_reminders_slot'
            );
            $table->index(['status', 'remind_at'], 'idx_task_reminders_status_due');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('task_reminders');

        Schema::table('family_tasks', function (Blueprint $table): void {
            $table->dropColumn('reminder_offsets_json');
        });

        Schema::table('tasks', function (Blueprint $table): void {
            $table->dropColumn('reminder_offsets_json');
        });
    }
};
