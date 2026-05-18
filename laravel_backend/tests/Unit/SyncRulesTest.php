<?php

namespace Tests\Unit;

use App\Domain\Sync\SyncRules;
use InvalidArgumentException;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class SyncRulesTest extends TestCase
{
    #[Test]
    public function child_cannot_edit_family_task(): void
    {
        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('Only adults can edit family tasks');

        SyncRules::ensureTaskPermissions('misha', [
            'owner_key' => 'family',
            'is_family' => true,
        ]);
    }

    #[Test]
    public function personal_task_owner_must_match_actor(): void
    {
        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('Personal task can be changed only by owner');

        SyncRules::ensureTaskPermissions('nik', [
            'owner_key' => 'misha',
            'is_family' => false,
        ]);
    }

    #[Test]
    public function family_task_targets_all_profiles(): void
    {
        $targets = SyncRules::recipientsForPush('nastya', 'family_task', 'upsert', []);
        $this->assertSame(['nik', 'nastya', 'misha', 'arisha'], $targets);
    }

    #[Test]
    public function personal_task_targets_owner_only(): void
    {
        $targets = SyncRules::recipientsForPush('nik', 'task', 'upsert', [
            'owner_key' => 'misha',
            'is_family' => false,
        ]);
        $this->assertSame(['misha'], $targets);
    }

    #[Test]
    public function normalize_assignees_filters_unknown_and_duplicates(): void
    {
        $assignees = SyncRules::normalizeAssignees([
            'assignees' => ['misha', 'misha', 'bad_profile', 'nik'],
        ]);

        $this->assertSame(['misha', 'nik'], $assignees);
    }

    #[Test]
    public function invalid_workflow_falls_back_to_todo(): void
    {
        $this->assertSame('todo', SyncRules::ensureWorkflow('invalid_status'));
        $this->assertSame('done', SyncRules::ensureWorkflow('done'));
    }
}
