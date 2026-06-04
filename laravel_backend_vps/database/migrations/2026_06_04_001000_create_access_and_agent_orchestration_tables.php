<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('user_roles')) {
            Schema::create('user_roles', function (Blueprint $table): void {
                $table->bigIncrements('id');
                $table->string('profile_key', 64);
                $table->string('role', 64);
                $table->string('granted_by', 64)->default('');
                $table->string('created_at', 32);
                $table->string('updated_at', 32);

                $table->unique(['profile_key', 'role'], 'uq_user_roles_profile_role');
                $table->index('role', 'idx_user_roles_role');
            });
        }

        if (!Schema::hasTable('role_capabilities')) {
            Schema::create('role_capabilities', function (Blueprint $table): void {
                $table->bigIncrements('id');
                $table->string('role', 64);
                $table->string('capability', 96);
                $table->string('created_at', 32);
                $table->string('updated_at', 32);

                $table->unique(['role', 'capability'], 'uq_role_capabilities_role_cap');
                $table->index('capability', 'idx_role_capabilities_capability');
            });
        }

        if (!Schema::hasTable('workspace_access')) {
            Schema::create('workspace_access', function (Blueprint $table): void {
                $table->bigIncrements('id');
                $table->string('workspace_id', 128);
                $table->string('profile_key', 64);
                $table->string('role', 64)->default('workspace_user');
                $table->string('granted_by', 64)->default('');
                $table->string('created_at', 32);
                $table->string('updated_at', 32);
                $table->string('revoked_at', 32)->nullable();

                $table->unique(['workspace_id', 'profile_key'], 'uq_workspace_access_workspace_profile');
                $table->index(['profile_key', 'revoked_at'], 'idx_workspace_access_profile_active');
            });
        }

        if (!Schema::hasTable('agent_mode_catalog')) {
            Schema::create('agent_mode_catalog', function (Blueprint $table): void {
                $table->string('key', 64)->primary();
                $table->string('label', 128);
                $table->text('description')->nullable();
                $table->string('created_at', 32);
                $table->string('updated_at', 32);
            });
        }

        if (!Schema::hasTable('agent_plugin_catalog')) {
            Schema::create('agent_plugin_catalog', function (Blueprint $table): void {
                $table->string('key', 64)->primary();
                $table->string('label', 128);
                $table->text('description')->nullable();
                $table->string('created_at', 32);
                $table->string('updated_at', 32);
            });
        }

        if (!Schema::hasTable('task_agent_sessions')) {
            Schema::create('task_agent_sessions', function (Blueprint $table): void {
                $table->string('id', 96)->primary();
                $table->string('task_id', 128);
                $table->string('workspace_id', 128);
                $table->string('session_id', 128)->default('');
                $table->string('actor_profile', 64);
                $table->string('mode', 64)->default('chat');
                $table->string('status', 64)->default('pending');
                $table->string('title', 255)->default('');
                $table->json('policy_json')->nullable();
                $table->string('created_at', 32);
                $table->string('updated_at', 32);

                $table->index(['task_id', 'workspace_id'], 'idx_task_agent_sessions_task_workspace');
                $table->index('session_id', 'idx_task_agent_sessions_session');
            });
        }

        if (!Schema::hasTable('task_agent_events')) {
            Schema::create('task_agent_events', function (Blueprint $table): void {
                $table->string('id', 96)->primary();
                $table->string('task_id', 128);
                $table->string('agent_session_id', 96)->default('');
                $table->string('workspace_id', 128)->default('');
                $table->string('type', 96);
                $table->string('actor_profile', 64)->default('');
                $table->json('payload_json')->nullable();
                $table->string('created_at', 32);

                $table->index(['task_id', 'created_at'], 'idx_task_agent_events_task_created');
                $table->index('agent_session_id', 'idx_task_agent_events_session');
            });
        }

        if (!Schema::hasTable('agent_policy_tickets')) {
            Schema::create('agent_policy_tickets', function (Blueprint $table): void {
                $table->string('id', 96)->primary();
                $table->string('actor_profile', 64);
                $table->string('task_id', 128);
                $table->string('workspace_id', 128);
                $table->string('mode', 64);
                $table->json('allowed_commands_json')->nullable();
                $table->string('expires_at', 32);
                $table->string('created_at', 32);
                $table->string('revoked_at', 32)->nullable();

                $table->index(['actor_profile', 'workspace_id'], 'idx_policy_tickets_actor_workspace');
                $table->index('expires_at', 'idx_policy_tickets_expires');
            });
        }

        if (!Schema::hasTable('audit_logs')) {
            Schema::create('audit_logs', function (Blueprint $table): void {
                $table->string('id', 96)->primary();
                $table->string('actor_profile', 64);
                $table->string('action', 128);
                $table->string('target_type', 64);
                $table->string('target_id', 128);
                $table->json('payload_json')->nullable();
                $table->string('created_at', 32);

                $table->index(['actor_profile', 'created_at'], 'idx_audit_logs_actor_created');
                $table->index(['target_type', 'target_id'], 'idx_audit_logs_target');
            });
        }

        $this->seedRoleCapabilities();
        $this->seedCatalogs();
    }

    public function down(): void
    {
        Schema::dropIfExists('audit_logs');
        Schema::dropIfExists('agent_policy_tickets');
        Schema::dropIfExists('task_agent_events');
        Schema::dropIfExists('task_agent_sessions');
        Schema::dropIfExists('agent_plugin_catalog');
        Schema::dropIfExists('agent_mode_catalog');
        Schema::dropIfExists('workspace_access');
        Schema::dropIfExists('role_capabilities');
        Schema::dropIfExists('user_roles');
    }

    private function seedRoleCapabilities(): void
    {
        if (!Schema::hasTable('role_capabilities')) {
            return;
        }
        $now = now()->format('Y-m-d\TH:i:s');
        $capabilitiesByRole = [
            'messenger_user' => ['messenger.use'],
            'project_member' => ['messenger.use', 'projects.view', 'tasks.view', 'tasks.comment'],
            'project_admin' => [
                'messenger.use',
                'projects.view',
                'projects.manage',
                'tasks.view',
                'tasks.comment',
                'tasks.edit',
                'tasks.change_status',
                'tasks.manage_agent',
            ],
            'workspace_user' => [
                'messenger.use',
                'projects.view',
                'tasks.view',
                'tasks.comment',
                'workspaces.view',
                'workspaces.use',
                'ai.use',
            ],
            'agent_operator' => [
                'messenger.use',
                'projects.view',
                'tasks.view',
                'tasks.comment',
                'tasks.edit',
                'tasks.change_status',
                'tasks.manage_agent',
                'workspaces.view',
                'workspaces.use',
                'ai.use',
                'ai.write_task_comments',
                'ai.change_task_status',
                'ai.manage_checklists',
                'agent.git_write',
            ],
        ];

        foreach ($capabilitiesByRole as $role => $capabilities) {
            foreach ($capabilities as $capability) {
                DB::table('role_capabilities')->updateOrInsert(
                    ['role' => $role, 'capability' => $capability],
                    ['created_at' => $now, 'updated_at' => $now],
                );
            }
        }
    }

    private function seedCatalogs(): void
    {
        $now = now()->format('Y-m-d\TH:i:s');
        if (Schema::hasTable('agent_mode_catalog')) {
            foreach ([
                'planner' => 'План',
                'chat' => 'Чат',
                'commentator' => 'Комментатор',
                'executor' => 'Исполнитель',
                'reviewer' => 'Ревьюер',
                'autopilot' => 'Автопилот',
                'yolo' => 'YOLO',
            ] as $key => $label) {
                DB::table('agent_mode_catalog')->updateOrInsert(
                    ['key' => $key],
                    ['label' => $label, 'description' => null, 'created_at' => $now, 'updated_at' => $now],
                );
            }
        }

        if (Schema::hasTable('agent_plugin_catalog')) {
            foreach ([
                'task_context' => 'Контекст задачи',
                'task_write' => 'Запись в задачу',
                'workspace_read' => 'Чтение воркспейса',
                'workspace_write' => 'Запись в воркспейс',
                'git' => 'Git',
                'github' => 'GitHub',
                'browser' => 'Браузер',
                'deploy' => 'Деплой',
                'audit' => 'Аудит',
            ] as $key => $label) {
                DB::table('agent_plugin_catalog')->updateOrInsert(
                    ['key' => $key],
                    ['label' => $label, 'description' => null, 'created_at' => $now, 'updated_at' => $now],
                );
            }
        }
    }
};
