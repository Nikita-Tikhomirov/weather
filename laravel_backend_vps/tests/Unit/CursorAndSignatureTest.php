<?php

namespace Tests\Unit;

use App\Domain\Sync\Cursor;
use App\Domain\Sync\PayloadSignature;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class CursorAndSignatureTest extends TestCase
{
    #[Test]
    public function cursor_uses_max_updated_at_from_buckets(): void
    {
        $cursor = Cursor::nextSyncCursor(
            [
                ['updated_at' => '2026-04-22T10:00:00'],
                ['updated_at' => '2026-04-22T11:00:00'],
            ],
            [
                ['updated_at' => '2026-04-22T12:30:00'],
            ],
            '2026-04-22T09:00:00'
        );

        $this->assertSame('2026-04-22T12:30:00', $cursor);
    }

    #[Test]
    public function signature_ignores_volatile_fields(): void
    {
        $a = PayloadSignature::build([
            'id' => '1',
            'title' => '????',
            'updated_at' => '2026-04-22T10:00:00',
            'version' => 2,
            'event_id' => 'a',
        ]);

        $b = PayloadSignature::build([
            'id' => '1',
            'title' => '????',
            'updated_at' => '2026-04-22T10:05:00',
            'version' => 9,
            'event_id' => 'b',
        ]);

        $this->assertSame($a, $b);
    }

    #[Test]
    public function signature_changes_for_meaningful_payload_changes(): void
    {
        $a = PayloadSignature::build(['id' => '1', 'title' => '????']);
        $b = PayloadSignature::build(['id' => '1', 'title' => '??????????']);

        $this->assertNotSame($a, $b);
    }
}
