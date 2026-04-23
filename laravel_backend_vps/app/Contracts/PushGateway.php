<?php

namespace App\Contracts;

interface PushGateway
{
    public function isConfigured(): bool;

    /**
     * @return array{success:bool,permanent_failure:bool,error:string}
     */
    public function sendToToken(string $token, string $title, string $body, array $data): array;
}
