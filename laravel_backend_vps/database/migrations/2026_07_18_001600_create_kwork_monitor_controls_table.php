<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (Schema::hasTable('kwork_monitor_controls')) {
            return;
        }

        Schema::create('kwork_monitor_controls', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->string('owner_profile_key', 64)->unique();
            $table->string('desired_state', 16)->default('stopped');
            $table->string('scan_requested_at', 32)->nullable();
            $table->string('executor_id', 128)->nullable();
            $table->string('last_seen_at', 32)->nullable();
            $table->string('last_scan_started_at', 32)->nullable();
            $table->string('last_scan_finished_at', 32)->nullable();
            $table->string('last_error', 2000)->default('');
            $table->string('created_at', 32);
            $table->string('updated_at', 32);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('kwork_monitor_controls');
    }
};
