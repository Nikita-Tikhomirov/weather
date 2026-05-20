<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('call_sessions', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->string('session_id', 64)->unique('uq_call_sessions_sid');
            $table->string('caller_profile', 32);
            $table->string('callee_profile', 32);
            $table->string('conversation_key', 128);
            $table->string('call_type', 8)->default('audio'); // audio | video
            $table->string('status', 16)->default('ringing'); // ringing | active | ended | rejected | missed
            $table->string('created_at', 32);
            $table->string('updated_at', 32);
            $table->string('ended_at', 32)->nullable();

            $table->index('caller_profile', 'idx_call_sessions_caller');
            $table->index('callee_profile', 'idx_call_sessions_callee');
            $table->index('status', 'idx_call_sessions_status');
            $table->index('created_at', 'idx_call_sessions_created');
        });

        Schema::create('call_signals', function (Blueprint $table): void {
            $table->bigIncrements('id');
            $table->string('session_id', 64);
            $table->string('from_profile', 32);
            $table->string('signal_type', 16); // offer | answer | ice_candidate | hangup
            $table->text('sdp')->nullable();       // JSON SDP for offer/answer
            $table->text('candidate')->nullable(); // JSON ICE candidate
            $table->string('created_at', 32);

            $table->index(['session_id', 'created_at'], 'idx_call_signals_session_created');
            $table->index('from_profile', 'idx_call_signals_from');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('call_signals');
        Schema::dropIfExists('call_sessions');
    }
};
