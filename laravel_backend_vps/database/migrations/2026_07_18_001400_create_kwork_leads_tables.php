<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('kwork_leads')) {
            Schema::create('kwork_leads', function (Blueprint $table): void {
                $table->bigIncrements('id');
                $table->string('external_key', 128)->unique();
                $table->string('owner_profile_key', 64);
                $table->string('source', 32)->default('kwork');
                $table->text('source_url');
                $table->string('title', 255);
                $table->text('raw_brief');
                $table->text('summary');
                $table->text('attachment_report');
                $table->text('draft_reply');
                $table->string('proposal_title', 70)->default('');
                $table->unsignedInteger('proposal_price_rub')->nullable();
                $table->unsignedTinyInteger('proposal_days')->nullable();
                $table->unsignedInteger('offer_count')->nullable();
                $table->string('status', 16)->default('new');
                $table->string('executor_id', 128)->nullable();
                $table->string('executor_claimed_at', 32)->nullable();
                $table->string('last_error', 2000)->default('');
                $table->unsignedInteger('version')->default(1);
                $table->string('created_at', 32);
                $table->string('updated_at', 32);

                $table->index(['owner_profile_key', 'status'], 'idx_kwork_leads_owner_status');
                $table->index('updated_at', 'idx_kwork_leads_updated');
            });
        }

        if (!Schema::hasTable('kwork_lead_audits')) {
            Schema::create('kwork_lead_audits', function (Blueprint $table): void {
                $table->bigIncrements('id');
                $table->unsignedBigInteger('lead_id');
                $table->string('actor_profile', 64)->default('');
                $table->string('action', 32);
                $table->json('payload_json')->nullable();
                $table->string('created_at', 32);

                $table->index(['lead_id', 'id'], 'idx_kwork_lead_audits_lead');
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('kwork_lead_audits');
        Schema::dropIfExists('kwork_leads');
    }
};
