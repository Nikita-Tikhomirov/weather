<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('chat_messages', function (Blueprint $table): void {
            if (!Schema::hasColumn('chat_messages', 'edited_at')) {
                $table->string('edited_at', 32)->nullable()->after('created_at');
            }
            if (!Schema::hasColumn('chat_messages', 'deleted_at')) {
                $table->string('deleted_at', 32)->nullable()->after('edited_at');
            }
        });
    }

    public function down(): void
    {
        Schema::table('chat_messages', function (Blueprint $table): void {
            if (Schema::hasColumn('chat_messages', 'deleted_at')) {
                $table->dropColumn('deleted_at');
            }
            if (Schema::hasColumn('chat_messages', 'edited_at')) {
                $table->dropColumn('edited_at');
            }
        });
    }
};
