<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('kwork_leads')) {
            return;
        }

        Schema::table('kwork_leads', function (Blueprint $table): void {
            if (!Schema::hasColumn('kwork_leads', 'buyer_desired_budget_rub')) {
                $table->unsignedInteger('buyer_desired_budget_rub')->nullable()->after('proposal_days');
            }
            if (!Schema::hasColumn('kwork_leads', 'kwork_max_price_rub')) {
                $table->unsignedInteger('kwork_max_price_rub')->nullable()->after('buyer_desired_budget_rub');
            }
        });
    }

    public function down(): void
    {
        if (!Schema::hasTable('kwork_leads')) {
            return;
        }

        Schema::table('kwork_leads', function (Blueprint $table): void {
            $drop = [];
            if (Schema::hasColumn('kwork_leads', 'buyer_desired_budget_rub')) {
                $drop[] = 'buyer_desired_budget_rub';
            }
            if (Schema::hasColumn('kwork_leads', 'kwork_max_price_rub')) {
                $drop[] = 'kwork_max_price_rub';
            }
            if ($drop !== []) {
                $table->dropColumn($drop);
            }
        });
    }
};
