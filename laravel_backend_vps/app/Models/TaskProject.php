<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class TaskProject extends Model
{
    protected $table = 'task_projects';
    protected $primaryKey = 'id';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;

    protected $fillable = [
        'id', 'name', 'description', 'owner_key', 'created_at', 'updated_at',
    ];
}
