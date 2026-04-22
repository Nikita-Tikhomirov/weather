<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class TelegramOutbox extends Model
{
    protected $table = 'telegram_outbox';
    public $timestamps = false;

    protected $fillable = [
        'event_id', 'payload_json', 'status', 'retry_count',
        'next_retry_at', 'created_at', 'updated_at',
    ];

    protected $casts = [
        'payload_json' => 'array',
        'retry_count' => 'integer',
    ];
}
