<?php

namespace Tests\Unit;

use App\Services\Push\PushMessageFactory;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

class PushMessageFactoryTest extends TestCase
{
    #[Test]
    public function it_builds_readable_russian_message_for_family_task(): void
    {
        $factory = new PushMessageFactory();

        $message = $factory->build(
            'nik',
            'family_task',
            'upsert',
            ['title' => 'Проверка'],
            'evt-ru-1'
        );

        $this->assertSame('Семейные задачи', $message['title']);
        $this->assertStringContainsString('Ник', $message['body']);
        $this->assertStringContainsString('Проверка', $message['body']);
        $this->assertStringNotContainsString('Р ', $message['title']);
    }
}
