<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Task extends Model
{
    protected $table = 'tasks';
    protected $primaryKey = 'id';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;

    protected $fillable = [
        'id', 'owner_key', 'is_family', 'title', 'details', 'due_date', 'time_value',
        'workflow_status', 'priority', 'tags_json', 'participants_json',
        'duration_minutes', 'updated_at', 'version',
    ];

    protected $casts = [
        'is_family' => 'boolean',
        'tags_json' => 'array',
        'participants_json' => 'array',
        'duration_minutes' => 'integer',
        'version' => 'integer',
    ];
}
