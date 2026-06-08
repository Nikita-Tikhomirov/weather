<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('project_chat_bindings')) {
            Schema::create('project_chat_bindings', function (Blueprint $table): void {
                $table->bigIncrements('id');
                $table->string('project_id', 64);
                $table->string('conversation_key', 128);
                $table->string('group_id', 64)->default('');
                $table->string('source', 32)->default('manual');
                $table->boolean('is_primary')->default(false);
                $table->string('created_at', 32);
                $table->string('updated_at', 32);

                $table->unique(['project_id', 'conversation_key'], 'uq_project_chat_project_conversation');
                $table->index('conversation_key', 'idx_project_chat_conversation');
                $table->index('group_id', 'idx_project_chat_group');
            });
        }

        if (!Schema::hasTable('project_automation_configs')) {
            Schema::create('project_automation_configs', function (Blueprint $table): void {
                $table->string('project_id', 64)->primary();
                $table->string('primary_workspace_id', 128)->default('');
                $table->boolean('agent_enabled')->default(false);
                $table->string('default_agent_mode', 64)->default('planner');
                $table->unsignedInteger('chat_analysis_message_limit')->default(40);
                $table->string('created_at', 32);
                $table->string('updated_at', 32);
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('project_automation_configs');
        Schema::dropIfExists('project_chat_bindings');
    }
};
