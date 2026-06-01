import 'dart:convert';

import 'package:family_todo_mobile/services/sync_service.dart';
import 'package:family_todo_mobile/models/task_collaboration.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:family_todo_mobile/models/pending_event.dart';
import 'package:family_todo_mobile/models/sync_snapshots.dart';
import 'package:family_todo_mobile/models/device_snapshots.dart';
import 'package:family_todo_mobile/contracts/sync_api.dart';
import 'package:family_todo_mobile/contracts/task_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake in-memory implementation of TaskDataSource for testing SyncService.
class _FakeDataSource implements TaskDataSource {
  final List<TaskItem> tasks = [];
  final List<PendingEvent> pending = [];
  String since = '1970-01-01T00:00:00';

  @override
  Future<void> upsertTask(TaskItem task) async {
    tasks.removeWhere((t) => t.id == task.id);
    tasks.add(task);
  }

  @override
  Future<void> deleteTask(String id) async {
    tasks.removeWhere((t) => t.id == id);
  }

  @override
  Future<List<TaskItem>> readTasks({
    String? ownerKey,
    bool includeAll = false,
  }) async {
    return tasks.toList();
  }

  @override
  Future<void> replacePersonalTasks({
    required String ownerKey,
    required List<TaskItem> items,
  }) async {
    tasks.removeWhere((t) => t.ownerKey == ownerKey && !t.isFamily);
    tasks.addAll(items);
  }

  @override
  Future<void> mergePersonalTasks({
    required String ownerKey,
    required List<TaskItem> items,
  }) async {
    for (final item in items) {
      await upsertTask(item);
    }
  }

  @override
  Future<void> mergeFamilyTasks(List<TaskItem> items) async {
    for (final item in items) {
      await upsertTask(item);
    }
  }

  @override
  Future<void> reconcileFamilyTasks(List<TaskItem> items) async {
    tasks.removeWhere((t) => t.isFamily);
    tasks.addAll(items);
  }

  @override
  Future<void> putPending(PendingEvent event) async {
    pending.add(event);
  }

  @override
  Future<List<PendingEvent>> readPending({int limit = 200}) async {
    return pending.toList();
  }

  @override
  Future<void> removePending(List<String> eventIds) async {
    pending.removeWhere((e) => eventIds.contains(e.eventId));
  }

  @override
  Future<String> readSince() async => since;

  @override
  Future<void> writeSince(String cursor) async {
    since = cursor;
  }
}

/// Fake implementation of SyncApi for testing SyncService.
class _FakeSyncApi implements SyncApi {
  final List<Map<String, dynamic>> pushedEvents = [];
  PullSnapshot? pullResult;
  String? actorProfileForPull;

  @override
  Future<void> push({
    required String actorProfile,
    required List<PendingEvent> events,
    String source = 'mobile',
  }) async {
    pushedEvents.add({
      'actorProfile': actorProfile,
      'source': source,
      'events': events.map((e) => e.eventId).toList(),
    });
  }

  @override
  Future<PullSnapshot> pull({
    required String since,
    bool changesMode = false,
    String? cursor,
  }) async {
    return pullResult ??
        PullSnapshot(
          tasks: const [],
          familyTasks: const [],
          serverTime: '2026-01-01T00:00:00',
          nextCursor: '2026-01-01T00:00:01',
          isDelta: changesMode,
          projects: const [],
          familyGroups: const [],
          projectGroupMap: const {},
        );
  }

  @override
  void setActorProfileForPull(String actorProfile) {
    actorProfileForPull = actorProfile;
  }

  @override
  Future<DeviceTokenRegistration> registerDeviceToken({
    required String actorProfile,
    required String token,
    required String platform,
    required String appVersion,
    String? deviceId,
    String playServices = 'unknown',
    String tokenStatus = 'active',
    String lastError = '',
  }) async {
    return const DeviceTokenRegistration(
      shouldResetToken: false,
      previousTokenStatus: '',
    );
  }

  @override
  Future<void> reportDeviceStatus({
    required String actorProfile,
    required String platform,
    required String appVersion,
    required String tokenStatus,
    required String playServices,
    String? token,
    String? deviceId,
    String? lastError,
  }) async {}

  @override
  Future<PushDeviceStatus> pushDeviceStatus({
    required String actorProfile,
  }) async {
    return PushDeviceStatus(
      actorProfile: actorProfile,
      effectiveTokenStatus: 'active',
      activeTokenCount: 1,
      status: const {},
      tokens: const [],
    );
  }

  @override
  Future<void> unregisterDeviceToken({
    required String actorProfile,
    required String token,
  }) async {}
}

TaskItem _makeTask(
  String id, {
  String ownerKey = 'nik',
  bool isFamily = false,
  WorkflowStatus workflowStatus = WorkflowStatus.todo,
  TaskCollaboration collaboration = const TaskCollaboration(),
}) {
  return TaskItem(
    id: id,
    ownerKey: ownerKey,
    isFamily: isFamily,
    title: 'Test $id',
    details: '',
    dueDate: '2026-01-01',
    time: '12:00',
    workflowStatus: workflowStatus,
    priority: Priority.medium,
    tags: const [],
    assignees: const [],
    reminderOffsetsMinutes: const [],
    collaboration: collaboration,
    durationMinutes: 0,
    updatedAt: '2026-01-01T00:00:00',
    version: 1,
  );
}

void main() {
  group('SyncService', () {
    late _FakeDataSource db;
    late _FakeSyncApi api;
    late SyncService service;

    setUp(() {
      db = _FakeDataSource();
      api = _FakeSyncApi();
      service = SyncService(db: db, api: api, actorProfile: 'nik');
    });

    test('constructor sets actor profile for pull', () {
      expect(api.actorProfileForPull, 'nik');
    });

    test('sync calls syncFull', () async {
      await service.sync();
      // Should not throw
    });

    group('enqueueUpsert', () {
      test('stores task and creates pending event', () async {
        final task = _makeTask('task-1');
        await service.enqueueUpsert(task);

        final tasks = await db.readTasks();
        expect(tasks.length, 1);
        expect(tasks.first.id, 'task-1');

        final pending = await db.readPending();
        expect(pending.length, 1);
        expect(pending.first.action, 'upsert');
        expect(pending.first.entity, 'task');
      });

      test('family task uses family entity type', () async {
        final task = _makeTask('task-2', isFamily: true, ownerKey: 'family');
        await service.enqueueUpsert(task);

        final pending = await db.readPending();
        expect(pending.first.entity, 'family_task');
      });

      test('family task payload includes collaboration context', () async {
        const collaboration = TaskCollaboration(
          comments: [
            TaskComment(
              id: 'comment-1',
              authorProfile: 'nik',
              text: 'Готово к проверке',
              createdAt: '2026-06-01T10:00:00',
            ),
          ],
        );
        final task = _makeTask(
          'task-collab',
          isFamily: true,
          ownerKey: 'family',
          collaboration: collaboration,
        );

        await service.enqueueUpsert(task);

        final pending = await db.readPending();
        final payload =
            jsonDecode(pending.first.payloadJson) as Map<String, dynamic>;
        final rawCollaboration =
            payload['collaboration'] as Map<String, dynamic>;
        expect(rawCollaboration['comments'], isA<List>());
        expect(
          (rawCollaboration['comments'] as List).first['text'],
          'Готово к проверке',
        );
      });
    });

    group('enqueueDelete', () {
      test('deletes task and creates pending event', () async {
        final task = _makeTask('task-3');
        await db.upsertTask(task);

        await service.enqueueDelete(
          'task-3',
          ownerKey: 'nik',
          isFamily: false,
        );

        final tasks = await db.readTasks();
        expect(tasks.length, 0);

        final pending = await db.readPending();
        expect(pending.length, 1);
        expect(pending.first.action, 'delete');
      });

      test('family task delete uses family entity type', () async {
        await service.enqueueDelete(
          'task-4',
          ownerKey: 'family',
          isFamily: true,
        );

        final pending = await db.readPending();
        expect(pending.first.entity, 'family_task');
      });
    });

    group('syncDelta', () {
      test('pushes pending events then pulls changes', () async {
        final task = _makeTask('task-5');
        await service.enqueueUpsert(task);

        await service.syncDelta();

        expect(api.pushedEvents.length, 1);
        expect(db.since, '2026-01-01T00:00:01');
      });

      test('skips push when no pending events', () async {
        await service.syncDelta();

        expect(api.pushedEvents.length, 0);
      });

      test('keeps local collaboration when pull echoes stale family task',
          () async {
        const collaboration = TaskCollaboration(
          comments: [
            TaskComment(
              id: 'comment-1',
              authorProfile: 'nik',
              text: 'Сразу сохранить',
              createdAt: '2026-06-01T10:00:00',
            ),
          ],
          checklists: [
            TaskChecklist(
              id: 'checklist-1',
              title: 'Проверка',
              createdBy: 'nik',
              createdAt: '2026-06-01T10:01:00',
            ),
          ],
        );
        final localTask = _makeTask(
          'task-local-collab',
          isFamily: true,
          ownerKey: 'family',
          collaboration: collaboration,
        );
        await service.enqueueUpsert(localTask);
        api.pullResult = PullSnapshot(
          tasks: const [],
          familyTasks: [
            localTask.copyWith(collaboration: const TaskCollaboration()),
          ],
          serverTime: '2026-06-01T10:02:00',
          nextCursor: '2026-06-01T10:02:00',
          isDelta: true,
          projects: const [],
          familyGroups: const [],
          projectGroupMap: const {},
        );

        await service.syncDelta();

        final tasks = await db.readTasks();
        final stored = tasks.singleWhere((task) => task.id == localTask.id);
        expect(stored.collaboration.comments.single.text, 'Сразу сохранить');
        expect(stored.collaboration.checklists.single.title, 'Проверка');
      });
    });

    group('syncFull', () {
      test('pushes pending, pulls full snapshot, keeps optimistic upsert',
          () async {
        await db.upsertTask(_makeTask('stale-local'));
        final task = _makeTask('task-6');
        await service.enqueueUpsert(task);

        api.pullResult = PullSnapshot(
          tasks: [_makeTask('server-1')],
          familyTasks: const [],
          serverTime: '2026-01-01T00:00:00',
          nextCursor: '2026-01-01T00:00:02',
          isDelta: false,
          projects: const [],
          familyGroups: const [],
          projectGroupMap: const {},
        );

        final snapshot = await service.syncFull();

        expect(api.pushedEvents.length, 1);
        expect(snapshot.tasks.length, 1);
        expect(db.since, '2026-01-01T00:00:02');

        final tasks = await db.readTasks();
        final ids = tasks.map((task) => task.id).toSet();
        expect(ids, containsAll(['server-1', 'task-6']));
        expect(ids, isNot(contains('stale-local')));
      });

      test('keeps local collaboration when full pull echoes stale family task',
          () async {
        const collaboration = TaskCollaboration(
          comments: [
            TaskComment(
              id: 'comment-2',
              authorProfile: 'nik',
              text: 'Не терять после входа',
              createdAt: '2026-06-01T11:00:00',
            ),
          ],
        );
        final localTask = _makeTask(
          'task-full-collab',
          isFamily: true,
          ownerKey: 'family',
          collaboration: collaboration,
        );
        await service.enqueueUpsert(localTask);
        api.pullResult = PullSnapshot(
          tasks: const [],
          familyTasks: [
            localTask.copyWith(collaboration: const TaskCollaboration()),
          ],
          serverTime: '2026-06-01T11:02:00',
          nextCursor: '2026-06-01T11:02:00',
          isDelta: false,
          projects: const [],
          familyGroups: const [],
          projectGroupMap: const {},
        );

        await service.syncFull();

        final tasks = await db.readTasks();
        final stored = tasks.singleWhere((task) => task.id == localTask.id);
        expect(
          stored.collaboration.comments.single.text,
          'Не терять после входа',
        );
      });
    });
  });
}
