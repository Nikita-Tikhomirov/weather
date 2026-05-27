import 'package:family_todo_mobile/services/local_db.dart';
import 'package:family_todo_mobile/models/pending_event.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:flutter_test/flutter_test.dart';

TaskItem _task(String id, {String ownerKey = 'test-nik', bool isFamily = false}) {
  return TaskItem(
    id: id,
    ownerKey: ownerKey,
    isFamily: isFamily,
    title: 'Test $id',
    details: '',
    dueDate: '2026-01-01',
    time: '12:00',
    workflowStatus: 'todo',
    priority: 'medium',
    tags: [],
    assignees: [],
    reminderOffsetsMinutes: [],
    durationMinutes: 0,
    updatedAt: '2026-01-01T00:00:00',
    version: 1,
  );
}

void main() {
  group('LocalDb', () {
    late LocalDb db;

    setUp(() async {
      db = await LocalDb.open();
    });

    test('open creates DB and returns instance', () {
      expect(db, isNotNull);
    });

    test('upsertTask and readTasks roundtrip', () async {
      final task = _task('crud-aa');
      await db.upsertTask(task);

      final tasks = await db.readTasks(ownerKey: 'test-nik');
      final found = tasks.where((t) => t.id == 'crud-aa').toList();
      expect(found.length, 1);
      expect(found.first.title, 'Test crud-aa');
    });

    test('upsertTask overwrites existing task by id', () async {
      final v1 = _task('crud-bb');
      await db.upsertTask(v1);

      final v2 = v1.copyWith(title: 'Updated');
      await db.upsertTask(v2);

      final tasks = await db.readTasks(ownerKey: 'test-nik');
      final found = tasks.where((t) => t.id == 'crud-bb').toList();
      expect(found.length, 1);
      expect(found.first.title, 'Updated');
    });

    test('deleteTask removes task', () async {
      final task = _task('crud-cc');
      await db.upsertTask(task);
      await db.deleteTask('crud-cc');

      final tasks = await db.readTasks(ownerKey: 'test-nik');
      final found = tasks.where((t) => t.id == 'crud-cc').toList();
      expect(found.length, 0);
    });

    test('upsert and read family task', () async {
      final task = _task('fam-aa', ownerKey: 'family', isFamily: true);
      await db.upsertTask(task);

      final tasks = await db.readTasks(ownerKey: 'test-nik');
      final found = tasks.where((t) => t.id == 'fam-aa').toList();
      expect(found.length, 1);
      expect(found.first.isFamily, isTrue);
    });

    test('putPending, readPending, removePending lifecycle', () async {
      final eventId = 'ev-zz-${DateTime.now().microsecondsSinceEpoch}';
      final event = PendingEvent(
        eventId: eventId,
        entity: 'task',
        action: 'upsert',
        payloadJson: '{"id":"test"}',
        happenedAt: '2026-01-01T00:00:00',
      );
      await db.putPending(event);

      final pending = await db.readPending();
      final found = pending.where((e) => e.eventId == eventId).toList();
      expect(found.length, 1);

      await db.removePending([eventId]);
      final remaining = await db.readPending();
      final stillThere = remaining.where((e) => e.eventId == eventId).toList();
      expect(stillThere.length, 0);
    });

    test('writeSince and readSince roundtrip', () async {
      final cursor = '2026-zz-${DateTime.now().microsecondsSinceEpoch}';
      await db.writeSince(cursor);
      final since = await db.readSince();
      expect(since, cursor);
    });
  });
}
