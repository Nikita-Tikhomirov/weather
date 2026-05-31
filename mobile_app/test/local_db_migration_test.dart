import 'dart:io';

import 'package:family_todo_mobile/services/local_db.dart';
import 'package:family_todo_mobile/models/pending_event.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

TaskItem _task(String id, {String ownerKey = 'test-nik', bool isFamily = false}) {
  return TaskItem(
    id: id,
    ownerKey: ownerKey,
    isFamily: isFamily,
    title: 'Test $id',
    details: '',
    dueDate: '2026-01-01',
    time: '12:00',
    workflowStatus: WorkflowStatus.todo,
    priority: Priority.medium,
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
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('local_db_test_');
      db = await LocalDb.open(
        databasePath: p.join(tempDir.path, 'family_todo_mobile.db'),
      );
    });

    tearDown(() async {
      await db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
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

    group('replace/merge operations', () {
      test('replacePersonalTasks atomically replaces tasks', () async {
        await db.upsertTask(_task('old-a1', ownerKey: 'test-nik'));
        await db.upsertTask(_task('old-a2', ownerKey: 'test-nik'));

        await db.replacePersonalTasks(ownerKey: 'test-nik', items: [
          _task('new-a1', ownerKey: 'test-nik'),
          _task('new-a2', ownerKey: 'test-nik'),
        ]);

        final tasks = await db.readTasks(ownerKey: 'test-nik');
        final old = tasks.where((t) => t.id.startsWith('old-a')).toList();
        final newT = tasks.where((t) => t.id.startsWith('new-a')).toList();
        expect(old.length, 0);
        expect(newT.length, 2);
      });

      test('replacePersonalTasks leaves family tasks untouched', () async {
        await db.upsertTask(_task('fam-keep', ownerKey: 'family', isFamily: true));

        await db.replacePersonalTasks(ownerKey: 'test-nik', items: [
          _task('personal-new', ownerKey: 'test-nik'),
        ]);

        final tasks = await db.readTasks(ownerKey: 'test-nik');
        final fam = tasks.where((t) => t.id == 'fam-keep').toList();
        expect(fam.length, 1);
      });

      test('mergePersonalTasks upserts without removing existing', () async {
        await db.upsertTask(_task('keep-me', ownerKey: 'test-nik'));
        await db.mergePersonalTasks(ownerKey: 'test-nik', items: [
          _task('add-me', ownerKey: 'test-nik'),
        ]);
        final tasks = await db.readTasks(ownerKey: 'test-nik');
        expect(tasks.any((t) => t.id == 'keep-me'), isTrue);
        expect(tasks.any((t) => t.id == 'add-me'), isTrue);
      });

      test('mergeFamilyTasks upserts family tasks by id', () async {
        await db.upsertTask(_task('fam-old', ownerKey: 'family', isFamily: true));
        await db.mergeFamilyTasks([
          _task('fam-new', ownerKey: 'family', isFamily: true),
        ]);
        final tasks = await db.readTasks(ownerKey: 'test-nik');
        expect(tasks.any((t) => t.id == 'fam-old'), isTrue);
        expect(tasks.any((t) => t.id == 'fam-new'), isTrue);
      });

      test('reconcileFamilyTasks replaces all family tasks', () async {
        await db.upsertTask(_task('fam-stale', ownerKey: 'family', isFamily: true));
        await db.reconcileFamilyTasks([
          _task('fam-fresh', ownerKey: 'family', isFamily: true),
        ]);
        final tasks = await db.readTasks(ownerKey: 'test-nik');
        final familyTasks = tasks.where((t) => t.isFamily).toList();
        expect(familyTasks.length, 1);
        expect(familyTasks.first.id, 'fam-fresh');
      });
    });
  });
}
