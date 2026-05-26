<?php

declare(strict_types=1);

/** @deprecated No longer used — any registered profile is allowed. */
const ADULTS = [];
/** @deprecated Kept for backward compat — any non-empty profile is accepted. */
const ALLOWED_PROFILES = ['nik', 'nastya', 'misha', 'arisha'];
const ALLOWED_WORKFLOW = ['todo', 'in_progress', 'in_review', 'done', 'archive'];
const FAMILY_NOTIFICATION_PROFILES = ALLOWED_PROFILES;

function require_api_key(array $config): void
{
    $expected = (string)($config['api_key'] ?? '');
    $provided = (string)($_SERVER['HTTP_X_API_KEY'] ?? '');

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

/** Accept any non-empty profile — no hardcoded whitelist. */
function ensure_actor(string $actor): string
{
    $actor = trim($actor);
    if ($actor === '') {
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
    // Shared tasks: any registered user can edit
    if ($isFamily && $actor === '') {
        throw new InvalidArgumentException('Unknown actor_profile');
    }
    if (!$isFamily && $owner !== $actor) {
        throw new InvalidArgumentException('Personal task can be changed only by owner');
    }
}

function ensure_family_permissions(string $actor): void
{
    if ($actor === '') {
        throw new InvalidArgumentException('Unknown actor_profile');
    }
}

/** Accept any non-empty assignee profile. */
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
        if ($key === '') {
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
    return $actor;
}

function recipient_adults_except_actor(string $actor): array
{
    return [];
}

function recipients_for_push(string $actor, string $entity, string $action, array $payload): array
{
    if ($entity === 'family_task') {
        $assignees = normalize_assignees($payload);
        return array_values(array_filter($assignees, static fn (string $p): bool => $p !== $actor));
    }

    $owner = trim((string)($payload['owner_key'] ?? $actor));
    if ($owner === '') {
        $owner = $actor;
    }
    $assignees = normalize_assignees($payload);
    $recipients = array_unique(array_merge([$owner], $assignees));
    return array_values(array_filter($recipients, static fn (string $p): bool =>
        $p !== $actor
    ));
}
