<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Task projects — grouping tasks into separate projects
        if (!Schema::hasTable('task_projects')) {
            Schema::create('task_projects', function (Blueprint $table): void {
                $table->string('id', 64)->primary();
                $table->string('name', 128);
                $table->text('description')->default('');
                $table->string('owner_key', 32);
                $table->string('created_at', 32);
                $table->string('updated_at', 32);

                $table->index('owner_key', 'idx_task_projects_owner');
            });
        }

        // Family groups — named sets of family members
        if (!Schema::hasTable('family_groups')) {
            Schema::create('family_groups', function (Blueprint $table): void {
                $table->string('id', 64)->primary();
                $table->string('name', 128);
                $table->json('members_json');
                $table->string('owner_key', 32);
                $table->string('created_at', 32);
                $table->string('updated_at', 32);

                $table->index('owner_key', 'idx_family_groups_owner');
            });
        }

        // Junction: which groups belong to which projects
        Schema::create('project_family_groups', function (Blueprint $table): void {
            $table->string('project_id', 64);
            $table->string('group_id', 64);

            $table->primary(['project_id', 'group_id']);
            $table->index('group_id', 'idx_pfg_group');
        });

        // Add project_id to personal tasks (if not already present)
        if (!Schema::hasColumn('tasks', 'project_id')) {
            Schema::table('tasks', function (Blueprint $table): void {
                $table->string('project_id', 64)->default('')->after('owner_key');
                $table->index('project_id', 'idx_tasks_project');
            });
        }

        // Add project_id to family tasks (if not already present)
        if (!Schema::hasColumn('family_tasks', 'project_id')) {
            Schema::table('family_tasks', function (Blueprint $table): void {
                $table->string('project_id', 64)->default('')->after('id');
                $table->index('project_id', 'idx_family_tasks_project');
            });
        }

        // Add group_id to personal tasks (if not already present)
        if (!Schema::hasColumn('tasks', 'group_id')) {
            Schema::table('tasks', function (Blueprint $table): void {
                $table->string('group_id', 64)->default('')->after('project_id');
                $table->index('group_id', 'idx_tasks_group');
            });
        }

        // Add group_id to family tasks (if not already present)
        if (!Schema::hasColumn('family_tasks', 'group_id')) {
            Schema::table('family_tasks', function (Blueprint $table): void {
                $table->string('group_id', 64)->default('')->after('project_id');
                $table->index('group_id', 'idx_family_tasks_group');
            });
        }
    }

    public function down(): void
    {
        Schema::table('family_tasks', function (Blueprint $table): void {
            $table->dropIndex('idx_family_tasks_group');
            $table->dropColumn('group_id');
            $table->dropIndex('idx_family_tasks_project');
            $table->dropColumn('project_id');
        });

        Schema::table('tasks', function (Blueprint $table): void {
            $table->dropIndex('idx_tasks_group');
            $table->dropColumn('group_id');
            $table->dropIndex('idx_tasks_project');
            $table->dropColumn('project_id');
        });

        Schema::dropIfExists('project_family_groups');
        Schema::dropIfExists('family_groups');
        Schema::dropIfExists('task_projects');
    }
};