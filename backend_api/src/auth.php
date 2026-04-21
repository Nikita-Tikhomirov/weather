<?php

declare(strict_types=1);

const ADULTS = ['nik', 'nastya'];
const ALLOWED_PROFILES = ['nik', 'nastya', 'misha', 'arisha'];
const ALLOWED_WORKFLOW = ['todo', 'in_progress', 'in_review', 'done'];

function require_api_key(array $config): void
{
    $expected = (string)($config['api_key'] ?? '');
    $provided = (string)($_SERVER['HTTP_X_API_KEY'] ?? '');

    // Family mode: allow explicit dev key for mobile CI builds.
    if ($provided === 'dev-local-key') {
        return;
    }

    if ($expected === '' && $provided === '') {
        return;
    }

    if ($expected !== '' && hash_equals($expected, $provided)) {
        return;
    }

    throw new UnexpectedValueException('Invalid API key');
}

function ensure_actor(string $actor): string
{
    $actor = trim($actor);
    if (!in_array($actor, ALLOWED_PROFILES, true)) {
        throw new InvalidArgumentException('Unknown actor_profile');
    }
    return $actor;
}

function ensure_workflow(string $value): string
{
    if (!in_array($value, ALLOWED_WORKFLOW, true)) {
        return 'todo';
    }
    return $value;
}

function ensure_task_permissions(string $actor, array $task): void
{
    $owner = (string)($task['owner_key'] ?? '');
    $isFamily = (bool)($task['is_family'] ?? false);
    if ($owner === '') {
        throw new InvalidArgumentException('owner_key is required');
    }
    if ($isFamily && !in_array($actor, ADULTS, true)) {
        throw new InvalidArgumentException('Only adults can edit family tasks');
    }
    if (!$isFamily && $owner !== $actor) {
        throw new InvalidArgumentException('Personal task can be changed only by owner');
    }
}

function ensure_family_permissions(string $actor): void
{
    if (!in_array($actor, ADULTS, true)) {
        throw new InvalidArgumentException('Only adults can edit family tasks');
    }
}

function normalize_assignees(array $payload): array
{
    $source = $payload['assignees'] ?? null;
    if (!is_array($source)) {
        $source = $payload['participants'] ?? null;
    }
    if (!is_array($source)) {
        $source = [];
    }
    $normalized = [];
    foreach ($source as $item) {
        $key = trim((string)$item);
        if ($key === '' || !in_array($key, ALLOWED_PROFILES, true)) {
            continue;
        }
        if (!in_array($key, $normalized, true)) {
            $normalized[] = $key;
        }
    }
    return $normalized;
}

function actor_display_name(string $actor): string
{
    return match ($actor) {
        'nik' => 'Nik',
        'nastya' => 'Nastya',
        'misha' => 'Misha',
        'arisha' => 'Arisha',
        default => $actor,
    };
}

function recipient_adults_except_actor(string $actor): array
{
    return array_values(array_filter(ADULTS, static fn(string $candidate): bool => $candidate !== $actor));
}

function recipients_for_push(string $actor, string $entity, string $action, array $payload): array
{
    if ($entity === 'family_task') {
        return ALLOWED_PROFILES;
    }

    $owner = trim((string)($payload['owner_key'] ?? $actor));
    if ($owner === '') {
        $owner = $actor;
    }
    if (in_array($owner, ADULTS, true)) {
        return [$owner];
    }
    if (in_array($owner, ALLOWED_PROFILES, true)) {
        return array_values(array_unique(array_merge([$owner], ADULTS)));
    }
    return [];
}
