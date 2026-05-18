<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class PushOutbox extends Model
{
    protected $table = 'push_outbox';
    public $timestamps = false;

    protected $fillable = [
        'event_id', 'token', 'profile_key', 'title', 'body_text', 'data_json',
        'status', 'retry_count', 'next_retry_at', 'last_error', 'created_at', 'updated_at',
    ];

    protected $casts = [
        'data_json' => 'array',
        'retry_count' => 'integer',
    ];
}
