<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasColumn('messenger_users', 'avatar_url')) {
            Schema::table('messenger_users', function (Blueprint $table): void {
                $table->string('avatar_url', 1024)->default('')->after('display_name');
            });
        }
    }

    public function down(): void
    {
        if (Schema::hasColumn('messenger_users', 'avatar_url')) {
            Schema::table('messenger_users', function (Blueprint $table): void {
                $table->dropColumn('avatar_url');
            });
        }
    }
};
