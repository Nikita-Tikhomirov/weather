<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class SyncEvent extends Model
{
    protected $table = 'sync_events';
    protected $primaryKey = 'event_id';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;

    protected $fillable = ['event_id', 'source', 'created_at'];
}
