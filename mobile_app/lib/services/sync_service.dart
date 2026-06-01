import 'dart:convert';

import '../contracts/sync_api.dart';
import '../contracts/task_data_source.dart';
import '../models/pending_event.dart';
import '../models/sync_snapshots.dart';
import '../models/task_item.dart';

class SyncService {
  SyncService({
    required this.db,
    required this.api,
    required this.actorProfile,
  }) {
    api.setActorProfileForPull(actorProfile);
  }

  final TaskDataSource db;
  final SyncApi api;
  final String actorProfile;

  Future<void> enqueueUpsert(TaskItem task) async {
    final now = DateTime.now().toIso8601String();
    final entity = task.isFamily ? 'family_task' : 'task';
    final payload = task.isFamily
        ? {
            'id': task.id,
            'owner_key': 'family',
            'is_family': true,
            'project_id': task.projectId,
            'group_id': task.groupId,
            'title': task.title,
            'details': task.details,
            'due_date': task.dueDate,
            'time': task.time,
            'workflow_status': task.workflowStatus.name,
            'assignees': task.assignees,
            'participants': task.assignees,
            'reminder_offsets_minutes': task.reminderOffsetsMinutes,
            'collaboration': task.collaboration.toJson(),
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

  Future<void> enqueueDelete(
    String id, {
    required String ownerKey,
    required bool isFamily,
  }) async {
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
    await syncFull();
  }

  Future<void> syncDelta() async {
    final pending = await db.readPending();
    final localBeforePull = await _readLocalByKey();
    if (pending.isNotEmpty) {
      await api.push(
        actorProfile: actorProfile,
        events: pending,
        source: 'mobile',
      );
      await db.removePending(pending.map((e) => e.eventId).toList());
    }
    final since = await db.readSince();
    final snapshot = await api.pull(
      since: since,
      changesMode: true,
      cursor: since,
    );
    final personal = _preserveLocalCollaboration(
      snapshot.tasks.where((task) => !task.isFamily).toList(),
      localBeforePull,
    );
    final family = snapshot.familyTasks
        .map((task) => task.copyWith(isFamily: true, ownerKey: 'family'))
        .toList();
    final familyWithLocalWork =
        _preserveLocalCollaboration(family, localBeforePull);
    await db.mergePersonalTasks(ownerKey: actorProfile, items: personal);
    await db.mergeFamilyTasks(familyWithLocalWork);
    await _restoreOptimisticUpserts(
      pending,
      remoteItems: [...personal, ...familyWithLocalWork],
    );
    await db.writeSince(snapshot.nextCursor);
  }

  Future<PullSnapshot> syncFull() async {
    final pending = await db.readPending();
    final localBeforePull = await _readLocalByKey();
    if (pending.isNotEmpty) {
      await api.push(
        actorProfile: actorProfile,
        events: pending,
        source: 'mobile',
      );
      await db.removePending(pending.map((e) => e.eventId).toList());
    }
    final snapshot = await api.pull(since: '1970-01-01T00:00:00');
    final personal = _preserveLocalCollaboration(
      snapshot.tasks.where((task) => !task.isFamily).toList(),
      localBeforePull,
    );
    final family = snapshot.familyTasks
        .map((task) => task.copyWith(isFamily: true, ownerKey: 'family'))
        .toList();
    final familyWithLocalWork =
        _preserveLocalCollaboration(family, localBeforePull);
    await db.replacePersonalTasks(ownerKey: actorProfile, items: personal);
    await db.reconcileFamilyTasks(familyWithLocalWork);
    await _restoreOptimisticUpserts(
      pending,
      remoteItems: [...personal, ...familyWithLocalWork],
    );
    await db.writeSince(snapshot.nextCursor);
    return snapshot;
  }

  Future<Map<String, TaskItem>> _readLocalByKey() async {
    final items = await db.readTasks(includeAll: true);
    return {for (final item in items) _taskKey(item): item};
  }

  List<TaskItem> _preserveLocalCollaboration(
    List<TaskItem> remoteItems,
    Map<String, TaskItem> localByKey,
  ) {
    return remoteItems.map((remote) {
      final local = localByKey[_taskKey(remote)];
      if (local == null ||
          local.collaboration.isEmpty ||
          !remote.collaboration.isEmpty) {
        return remote;
      }
      return remote.copyWith(collaboration: local.collaboration);
    }).toList();
  }

  Future<void> _restoreOptimisticUpserts(
    List<PendingEvent> pending, {
    required List<TaskItem> remoteItems,
  }) async {
    final optimistic = _pendingUpserts(pending);
    if (optimistic.isEmpty) return;
    final remoteByKey = {for (final item in remoteItems) _taskKey(item): item};
    for (final local in optimistic) {
      final remote = remoteByKey[_taskKey(local)];
      final taskToKeep = _optimisticTaskToKeep(local, remote);
      if (taskToKeep != null) {
        await db.upsertTask(taskToKeep);
      }
    }
  }

  TaskItem? _optimisticTaskToKeep(TaskItem local, TaskItem? remote) {
    if (remote == null) return local;
    final localIsFresh = local.version > remote.version ||
        (local.version == remote.version &&
            local.updatedAt.compareTo(remote.updatedAt) >= 0);
    if (localIsFresh) return local;
    if (!local.collaboration.isEmpty && remote.collaboration.isEmpty) {
      return remote.copyWith(collaboration: local.collaboration);
    }
    return null;
  }

  List<TaskItem> _pendingUpserts(List<PendingEvent> pending) {
    final byKey = <String, TaskItem>{};
    for (final event in pending) {
      if (event.action != 'upsert') continue;
      if (event.entity != 'task' && event.entity != 'family_task') continue;
      try {
        final decoded = jsonDecode(event.payloadJson);
        if (decoded is! Map) continue;
        final payload = Map<String, dynamic>.from(decoded);
        if (event.entity == 'family_task') {
          payload['owner_key'] = 'family';
          payload['is_family'] = true;
        }
        final task = TaskItem.fromJson(payload);
        if (task.id.isNotEmpty) {
          byKey[_taskKey(task)] = task;
        }
      } catch (_) {
        continue;
      }
    }
    return byKey.values.toList();
  }

  String _taskKey(TaskItem task) {
    return '${task.isFamily ? 'family' : task.ownerKey}:${task.id}';
  }

  String _eventId(String prefix) {
    final t = DateTime.now().microsecondsSinceEpoch;
    return '$prefix-$actorProfile-$t';
  }
}
