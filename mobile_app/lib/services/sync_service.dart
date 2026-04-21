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
    final entity = task.isFamily ? 'family_task' : 'task';
    final payload = task.isFamily
        ? {
            'id': task.id,
            'title': task.title,
            'details': task.details,
            'due_date': task.dueDate,
            'time': task.time,
            'workflow_status': task.workflowStatus,
            'participants': task.participants,
            'duration_minutes': task.durationMinutes,
            'updated_at': task.updatedAt,
            'version': task.version,
          }
        : task.toJson();
    await db.upsertTask(task);
    await db.putPending(
      PendingEvent(
        eventId: _eventId('task-upsert'),
        entity: entity,
        action: 'upsert',
        payloadJson: jsonEncode(payload),
        happenedAt: now,
      ),
    );
  }

  Future<void> enqueueDelete(String id, {required String ownerKey, required bool isFamily}) async {
    final now = DateTime.now().toIso8601String();
    final entity = isFamily ? 'family_task' : 'task';
    final payload = isFamily
        ? {'id': id}
        : {'id': id, 'owner_key': ownerKey, 'is_family': isFamily};
    await db.deleteTask(id);
    await db.putPending(
      PendingEvent(
        eventId: _eventId('task-delete'),
        entity: entity,
        action: 'delete',
        payloadJson: jsonEncode(payload),
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
    final snapshot = await api.pull(since: '1970-01-01T00:00:00');
    final merged = <TaskItem>[
      ...snapshot.tasks.where((task) => !task.isFamily),
      ...snapshot.familyTasks.map((task) => task.copyWith(isFamily: true, ownerKey: 'family')),
    ];
    await db.replaceTasks(merged);
    await db.writeSince(snapshot.serverTime);
  }

  String _eventId(String prefix) {
    final t = DateTime.now().microsecondsSinceEpoch;
    return '$prefix-$actorProfile-$t';
  }
}
