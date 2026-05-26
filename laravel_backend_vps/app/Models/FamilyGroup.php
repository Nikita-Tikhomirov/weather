<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class FamilyGroup extends Model
{
    protected $table = 'family_groups';
    protected $primaryKey = 'id';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;

    protected $fillable = [
        'id', 'name', 'members', 'owner_key', 'created_at', 'updated_at',
    ];

    protected $casts = [
        'members' => 'array',
    ];
}
