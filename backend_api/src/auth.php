<?php

declare(strict_types=1);

const ADULTS = ['nik', 'nastya'];
const ALLOWED_PROFILES = ['nik', 'nastya', 'misha', 'arisha'];
const ALLOWED_WORKFLOW = ['todo', 'in_progress', 'in_review', 'done'];

function require_api_key(array $config): void
{
    $expected = (string)($config['api_key'] ?? '');
    if ($expected === '') {
        throw new RuntimeException('api_key is empty in config');
    }
    $provided = (string)($_SERVER['HTTP_X_API_KEY'] ?? '');
    if (!hash_equals($expected, $provided)) {
        throw new UnexpectedValueException('Invalid API key');
    }
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

