<?php

declare(strict_types=1);

function load_config(): array
{
    $root = dirname(__DIR__);
    $configPath = $root . '/config.php';
    if (!is_file($configPath)) {
        $examplePath = $root . '/config.example.php';
        if (is_file($examplePath)) {
            return require $examplePath;
        }
        throw new RuntimeException('Config file is missing');
    }
    return require $configPath;
}

function json_response(int $status, array $payload): void
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
}

function read_json_body(): array
{
    $raw = file_get_contents('php://input');
    if (!is_string($raw) || trim($raw) === '') {
        return [];
    }
    $decoded = json_decode($raw, true);
    if (!is_array($decoded)) {
        throw new InvalidArgumentException('Invalid JSON body');
    }
    return $decoded;
}

function iso_now(): string
{
    return (new DateTimeImmutable('now'))->format('Y-m-d\TH:i:s');
}

