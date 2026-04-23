<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('device_tokens', function (Blueprint $table): void {
            if (!Schema::hasColumn('device_tokens', 'token_status')) {
                $table->string('token_status', 32)->default('active')->after('is_active');
            }
            if (!Schema::hasColumn('device_tokens', 'play_services')) {
                $table->string('play_services', 32)->default('unknown')->after('token_status');
            }
            if (!Schema::hasColumn('device_tokens', 'last_error')) {
                $table->string('last_error', 512)->default('')->after('play_services');
            }
            if (!Schema::hasColumn('device_tokens', 'registered_at')) {
                $table->string('registered_at', 32)->default('')->after('last_error');
            }
        });

        Schema::create('device_status', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->string('profile_key', 32);
            $table->string('platform', 32)->default('android');
            $table->string('token', 255)->default('');
            $table->string('token_status', 32)->default('unknown');
            $table->string('play_services', 32)->default('unknown');
            $table->string('last_error', 512)->default('');
            $table->string('app_version', 64)->default('');
            $table->string('device_id', 128)->default('');
            $table->string('updated_at', 32);
            $table->string('created_at', 32);

            $table->index(['profile_key', 'updated_at'], 'idx_device_status_profile_updated');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('device_status');

        Schema::table('device_tokens', function (Blueprint $table): void {
            if (Schema::hasColumn('device_tokens', 'registered_at')) {
                $table->dropColumn('registered_at');
            }
            if (Schema::hasColumn('device_tokens', 'last_error')) {
                $table->dropColumn('last_error');
            }
            if (Schema::hasColumn('device_tokens', 'play_services')) {
                $table->dropColumn('play_services');
            }
            if (Schema::hasColumn('device_tokens', 'token_status')) {
                $table->dropColumn('token_status');
            }
        });
    }
};
