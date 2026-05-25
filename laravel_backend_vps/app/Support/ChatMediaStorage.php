<?php

namespace App\Support;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use InvalidArgumentException;
use Symfony\Component\HttpFoundation\StreamedResponse;

final class ChatMediaStorage
{
    public static function putUploadedFile(string $directory, UploadedFile $upload, string $extension): array
    {
        $filename = sprintf('%s.%s', Str::ulid(), $extension);
        $path = Storage::disk(self::disk())->putFileAs($directory, $upload, $filename);
        if ($path === false) {
            throw new InvalidArgumentException('Failed to upload file');
        }

        return [
            'path' => $path,
            'url' => self::urlForPath($path),
        ];
    }

    public static function urlForPath(string $path): string
    {
        return '/chat/media/'.self::encodePath($path);
    }

    public static function responseForEncodedPath(string $encodedPath): StreamedResponse
    {
        $path = self::decodePath($encodedPath);
        $disk = Storage::disk(self::disk());
        if (!$disk->exists($path)) {
            abort(404);
        }

        $stream = $disk->readStream($path);
        if ($stream === false) {
            abort(404);
        }

        return response()->stream(static function () use ($stream): void {
            fpassthru($stream);
            if (is_resource($stream)) {
                fclose($stream);
            }
        }, 200, [
            'Content-Type' => $disk->mimeType($path) ?: 'application/octet-stream',
            'Cache-Control' => 'public, max-age=31536000, immutable',
        ]);
    }

    public static function disk(): string
    {
        return trim((string) config('chat.media_disk', 'public')) ?: 'public';
    }

    private static function encodePath(string $path): string
    {
        return rtrim(strtr(base64_encode($path), '+/', '-_'), '=');
    }

    private static function decodePath(string $encodedPath): string
    {
        $raw = base64_decode(strtr($encodedPath, '-_', '+/'), true);
        if ($raw === false || trim($raw) === '' || str_contains($raw, '..')) {
            abort(404);
        }

        return $raw;
    }
}
