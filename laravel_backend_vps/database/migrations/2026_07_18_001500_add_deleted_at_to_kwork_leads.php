<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasColumn('kwork_leads', 'deleted_at')) {
            Schema::table('kwork_leads', function (Blueprint $table): void {
                $table->string('deleted_at', 32)->nullable()->after('updated_at');
                $table->index('deleted_at', 'idx_kwork_leads_deleted');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('kwork_leads', 'deleted_at')) {
            Schema::table('kwork_leads', function (Blueprint $table): void {
                $table->dropIndex('idx_kwork_leads_deleted');
                $table->dropColumn('deleted_at');
            });
        }
    }
};
