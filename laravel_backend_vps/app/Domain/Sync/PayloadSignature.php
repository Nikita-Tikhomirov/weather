<?php

namespace App\Domain\Sync;

final class PayloadSignature
{
    private const VOLATILE_FIELDS = [
        'event_id', 'happened_at', 'updated_at', 'version', 'server_time', 'dedup_signature',
    ];

    public static function build(array $payload): string
    {
        $canonical = self::normalize(self::withoutVolatileFields($payload));
        return hash('sha256', json_encode($canonical, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    }

    private static function withoutVolatileFields(array $payload): array
    {
        foreach (self::VOLATILE_FIELDS as $key) {
            unset($payload[$key]);
        }
        return $payload;
    }

    private static function normalize(mixed $value): mixed
    {
        if (!is_array($value)) {
            if (is_bool($value) || is_int($value) || is_float($value) || is_string($value) || $value === null) {
                return $value;
            }
            return (string)$value;
        }

        $isList = array_keys($value) === range(0, count($value) - 1);
        if ($isList) {
            $normalized = array_map([self::class, 'normalize'], $value);
            $allScalars = true;
            foreach ($normalized as $item) {
                if (is_array($item)) {
                    $allScalars = false;
                    break;
                }
            }
            if ($allScalars) {
                sort($normalized);
            }
            return $normalized;
        }

        ksort($value);
        $normalized = [];
        foreach ($value as $key => $item) {
            $normalized[(string)$key] = self::normalize($item);
        }
        return $normalized;
    }
}
