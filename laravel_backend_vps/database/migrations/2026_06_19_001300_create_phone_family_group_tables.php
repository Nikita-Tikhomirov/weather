<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        if (!Schema::hasTable('phone_family_groups')) {
            Schema::create('phone_family_groups', function (Blueprint $table): void {
                $table->bigIncrements('id');
                $table->string('owner_profile_key', 32);
                $table->string('title', 120)->default('Family');
                $table->string('created_at', 32);
                $table->string('updated_at', 32);

                $table->index('owner_profile_key', 'idx_phone_family_groups_owner');
            });
        }

        if (!Schema::hasTable('phone_family_group_members')) {
            Schema::create('phone_family_group_members', function (Blueprint $table): void {
                $table->bigIncrements('id');
                $table->unsignedBigInteger('family_group_id');
                $table->string('profile_key', 32);
                $table->string('role', 32)->default('member');
                $table->string('joined_at', 32);

                $table->unique(['family_group_id', 'profile_key'], 'uq_phone_family_group_profile');
                $table->index('profile_key', 'idx_phone_family_members_profile');
            });
        }

        $this->copyLegacyPhoneFamilyGroups();
    }

    public function down(): void
    {
        Schema::dropIfExists('phone_family_group_members');
        Schema::dropIfExists('phone_family_groups');
    }

    private function copyLegacyPhoneFamilyGroups(): void
    {
        if (
            !Schema::hasTable('family_groups') ||
            !Schema::hasColumn('family_groups', 'owner_profile_key')
        ) {
            return;
        }

        $now = now()->format('Y-m-d\\TH:i:s');
        $legacyGroups = DB::table('family_groups')->orderBy('id')->get();
        foreach ($legacyGroups as $legacyGroup) {
            $owner = trim((string) ($legacyGroup->owner_profile_key ?? ''));
            if ($owner === '') {
                continue;
            }

            $title = trim((string) ($legacyGroup->title ?? ''));
            DB::table('phone_family_groups')->updateOrInsert(
                ['owner_profile_key' => $owner],
                [
                    'title' => $title !== '' ? $title : 'Family',
                    'created_at' => (string) ($legacyGroup->created_at ?? $now),
                    'updated_at' => (string) ($legacyGroup->updated_at ?? $now),
                ],
            );

            $newGroupId = (int) DB::table('phone_family_groups')
                ->where('owner_profile_key', $owner)
                ->value('id');
            if ($newGroupId <= 0) {
                continue;
            }

            $legacyId = (string) ($legacyGroup->id ?? '');
            if ($legacyId !== '' && Schema::hasTable('family_group_members')) {
                $legacyMembers = DB::table('family_group_members')
                    ->where('family_group_id', $legacyId)
                    ->get();
                foreach ($legacyMembers as $legacyMember) {
                    $profile = trim((string) ($legacyMember->profile_key ?? ''));
                    if ($profile === '') {
                        continue;
                    }
                    DB::table('phone_family_group_members')->updateOrInsert(
                        ['family_group_id' => $newGroupId, 'profile_key' => $profile],
                        [
                            'role' => (string) ($legacyMember->role ?? 'member'),
                            'joined_at' => (string) ($legacyMember->joined_at ?? $now),
                        ],
                    );
                }
            }

            DB::table('phone_family_group_members')->updateOrInsert(
                ['family_group_id' => $newGroupId, 'profile_key' => $owner],
                ['role' => 'owner', 'joined_at' => $now],
            );
        }
    }
};
