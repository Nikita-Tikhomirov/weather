import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/pending_event.dart';
import '../models/task_item.dart';

class LocalDb {
  LocalDb._(this._db);

  final Database _db;

  static Future<LocalDb> open() async {
    final basePath = await getDatabasesPath();
    final dbPath = p.join(basePath, 'family_todo_mobile.db');
    final db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE tasks(
            id TEXT PRIMARY KEY,
            owner_key TEXT NOT NULL,
            is_family INTEGER NOT NULL,
            title TEXT NOT NULL,
            details TEXT NOT NULL,
            due_date TEXT NOT NULL,
            time TEXT NOT NULL,
            workflow_status TEXT NOT NULL,
            priority TEXT NOT NULL,
            tags_json TEXT NOT NULL,
            participants_json TEXT NOT NULL,
            duration_minutes INTEGER NOT NULL,
            updated_at TEXT NOT NULL,
            version INTEGER NOT NULL
          );
        ''');
        await db.execute('''
          CREATE TABLE pending_events(
            event_id TEXT PRIMARY KEY,
            entity TEXT NOT NULL,
            action TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            happened_at TEXT NOT NULL
          );
        ''');
        await db.execute('''
          CREATE TABLE meta(
            k TEXT PRIMARY KEY,
            v TEXT NOT NULL
          );
        ''');
      },
    );
    return LocalDb._(db);
  }

  Future<void> upsertTask(TaskItem item) async {
    await _db.insert('tasks', item.toDbRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteTask(String id) async {
    await _db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<TaskItem>> readTasks({String? ownerKey, bool includeAll = false}) async {
    final rows = await _db.query(
      'tasks',
      where: includeAll || ownerKey == null ? null : '(owner_key = ? OR is_family = 1)',
      whereArgs: includeAll || ownerKey == null ? null : [ownerKey],
      orderBy: 'updated_at DESC',
    );
    return rows.map(TaskItem.fromDbRow).toList();
  }

  Future<void> putPending(PendingEvent event) async {
    await _db.insert('pending_events', event.toDbRow(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<PendingEvent>> readPending({int limit = 200}) async {
    final rows = await _db.query('pending_events', orderBy: 'happened_at ASC', limit: limit);
    return rows.map(PendingEvent.fromDbRow).toList();
  }

  Future<void> removePending(List<String> eventIds) async {
    if (eventIds.isEmpty) {
      return;
    }
    final placeholders = List.filled(eventIds.length, '?').join(',');
    await _db.delete('pending_events', where: 'event_id IN ($placeholders)', whereArgs: eventIds);
  }

  Future<String> readSince() async {
    final rows = await _db.query('meta', where: 'k = ?', whereArgs: ['since'], limit: 1);
    if (rows.isEmpty) {
      return '1970-01-01T00:00:00';
    }
    return (rows.first['v'] ?? '1970-01-01T00:00:00').toString();
  }

  Future<void> writeSince(String value) async {
    await _db.insert('meta', {'k': 'since', 'v': value}, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
