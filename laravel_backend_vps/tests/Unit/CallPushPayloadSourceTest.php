<?php

namespace Tests\Unit;

use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class CallPushPayloadSourceTest extends TestCase
{
    #[Test]
    public function incoming_call_push_contains_native_action_identity_fields(): void
    {
        $source = file_get_contents(base_path('app/Http/Controllers/CallController.php'));

        $this->assertIsString($source);
        $this->assertStringContainsString('$callerLabel = $this->profileLabel($actor);', $source);
        $this->assertStringContainsString("'caller_display_name' => \$callerLabel", $source);
        $this->assertStringContainsString("'caller_name' => \$callerLabel", $source);
        $this->assertStringContainsString("'callee_profile' => \$callee", $source);
        $this->assertStringContainsString("'recipient_profile' => \$callee", $source);
    }
}
