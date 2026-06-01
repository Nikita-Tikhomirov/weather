<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasColumn('tasks', 'collaboration_json')) {
            Schema::table('tasks', function (Blueprint $table): void {
                $table->json('collaboration_json')->nullable()->after('participants_json');
            });
        }

        if (!Schema::hasColumn('family_tasks', 'collaboration_json')) {
            Schema::table('family_tasks', function (Blueprint $table): void {
                $table->json('collaboration_json')->nullable()->after('participants_json');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('family_tasks', 'collaboration_json')) {
            Schema::table('family_tasks', function (Blueprint $table): void {
                $table->dropColumn('collaboration_json');
            });
        }

        if (Schema::hasColumn('tasks', 'collaboration_json')) {
            Schema::table('tasks', function (Blueprint $table): void {
                $table->dropColumn('collaboration_json');
            });
        }
    }
};
