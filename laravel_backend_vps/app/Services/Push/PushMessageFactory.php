<?php

namespace App\Services\Push;

use App\Domain\Sync\SyncRules;

class PushMessageFactory
{
    /**
     * @return array{
     *   recipients: array<int,string>,
     *   title: string,
     *   body: string,
     *   data: array<string,string>
     * }
     */
    public function build(string $actor, string $entity, string $action, array $payload, string $eventId): array
    {
        $recipients = SyncRules::recipientsForPush($actor, $entity, $action, $payload);
        $actorLabel = $this->actorLabel($actor);

        $itemTitle = trim((string) ($payload['title'] ?? ''));
        if ($itemTitle === '') {
            $itemTitle = 'без названия';
        }

        if ($entity === 'family_task') {
            $title = 'Семейные задачи';
            $body = match ($action) {
                'delete' => sprintf('%s удалил семейную задачу "%s"', $actorLabel, $itemTitle),
                'replace_family_tasks' => sprintf('%s обновил список семейных задач', $actorLabel),
                default => sprintf('%s обновил семейную задачу "%s"', $actorLabel, $itemTitle),
            };
        } else {
            $owner = trim((string) ($payload['owner_key'] ?? $actor));
            $ownerLabel = $this->actorLabel($owner);
            $title = sprintf('Задачи: %s', $ownerLabel);
            $body = match ($action) {
                'delete' => sprintf('%s удалил задачу "%s"', $actorLabel, $itemTitle),
                'replace_person_tasks' => sprintf('%s обновил список задач', $actorLabel),
                default => sprintf('%s изменил задачу "%s"', $actorLabel, $itemTitle),
            };
        }

        return [
            'recipients' => $recipients,
            'title' => $title,
            'body' => $body,
            'data' => [
                'event_id' => $eventId,
                'entity' => $entity,
                'action' => $action,
                'actor_profile' => $actor,
            ],
        ];
    }

    private function actorLabel(string $key): string
    {
        return match (trim($key)) {
            'nik' => 'Ник',
            'nastya' => 'Настя',
            'misha' => 'Миша',
            'arisha' => 'Ариша',
            default => 'Семья',
        };
    }
}
