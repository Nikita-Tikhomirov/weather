<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class FamilyTask extends Model
{
    protected $table = 'family_tasks';
    protected $primaryKey = 'id';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;

    protected $fillable = [
        'id', 'title', 'details', 'due_date', 'time_value', 'workflow_status',
        'participants_json', 'duration_minutes', 'updated_at', 'version',
    ];

    protected $casts = [
        'participants_json' => 'array',
        'duration_minutes' => 'integer',
        'version' => 'integer',
    ];
}
