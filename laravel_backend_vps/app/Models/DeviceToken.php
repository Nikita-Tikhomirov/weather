<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class DeviceToken extends Model
{
    protected $table = 'device_tokens';
    protected $primaryKey = 'token';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;

    protected $fillable = [
        'token', 'profile_key', 'platform', 'app_version', 'device_id',
        'is_active', 'last_seen_at', 'created_at', 'updated_at',
    ];

    protected $casts = [
        'is_active' => 'boolean',
    ];
}
