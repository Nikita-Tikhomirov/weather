import 'dart:convert';

import '../models/pending_event.dart';
import '../models/task_item.dart';
import 'api_client.dart';
import 'local_db.dart';

class SyncService {
  SyncService({
    required this.db,
    required this.api,
    required this.actorProfile,
  });

  final LocalDb db;
  final ApiClient api;
  final String actorProfile;

  Future<void> enqueueUpsert(TaskItem task) async {
    final now = DateTime.now().toIso8601String();
    await db.upsertTask(task);
    await db.putPending(
      PendingEvent(
        eventId: _eventId('task-upsert'),
        entity: 'task',
        action: 'upsert',
        payloadJson: jsonEncode(task.toJson()),
        happenedAt: now,
      ),
    );
  }

  Future<void> enqueueDelete(String id, {required String ownerKey, required bool isFamily}) async {
    final now = DateTime.now().toIso8601String();
    await db.deleteTask(id);
    await db.putPending(
      PendingEvent(
        eventId: _eventId('task-delete'),
        entity: 'task',
        action: 'delete',
        payloadJson: jsonEncode({'id': id, 'owner_key': ownerKey, 'is_family': isFamily}),
        happenedAt: now,
      ),
    );
  }

  Future<void> sync() async {
    final pending = await db.readPending();
    if (pending.isNotEmpty) {
      await api.push(actorProfile: actorProfile, events: pending, source: 'mobile');
      await db.removePending(pending.map((e) => e.eventId).toList());
    }
    final since = await db.readSince();
    final (tasks, serverTime) = await api.pull(since: since);
    for (final task in tasks) {
      await db.upsertTask(task);
    }
    await db.writeSince(serverTime);
  }

  String _eventId(String prefix) {
    final t = DateTime.now().microsecondsSinceEpoch;
    return '$prefix-$actorProfile-$t';
  }
}

