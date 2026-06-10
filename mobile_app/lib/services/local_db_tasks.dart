part of 'local_db.dart';

mixin LocalDbTaskOperations implements TaskDataSource {
  Database get _db;

  @override
  Future<void> upsertTask(TaskItem item) async {
    await _db.insert(
      'tasks',
      item.toDbRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> deleteTask(String id) async {
    await _db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> replaceTasks(List<TaskItem> items) async {
    await _db.transaction((txn) async {
      await txn.delete('tasks');
      for (final item in items) {
        await txn.insert(
          'tasks',
          item.toDbRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<void> replacePersonalTasks({
    required String ownerKey,
    required List<TaskItem> items,
  }) async {
    await _db.transaction((txn) async {
      await txn.delete(
        'tasks',
        where: 'is_family = 0 AND owner_key = ?',
        whereArgs: [ownerKey],
      );
      for (final item in items.where((t) => !t.isFamily)) {
        await txn.insert(
          'tasks',
          item.toDbRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<void> mergePersonalTasks({
    required String ownerKey,
    required List<TaskItem> items,
  }) async {
    final personal =
        items.where((t) => !t.isFamily && t.ownerKey == ownerKey).toList();
    if (personal.isEmpty) return;
    await _db.transaction((txn) async {
      for (final item in personal) {
        await txn.insert(
          'tasks',
          item.toDbRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<void> reconcileFamilyTasks(List<TaskItem> items) async {
    final familyItems = items.where((t) => t.isFamily).toList();
    await _db.transaction((txn) async {
      for (final item in familyItems) {
        await txn.insert(
          'tasks',
          item.toDbRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      final rows = await txn.query(
        'tasks',
        columns: const ['id'],
        where: 'is_family = 1',
      );
      final remoteIds = familyItems.map((item) => item.id).toSet();
      for (final row in rows) {
        final id = (row['id'] ?? '').toString();
        if (id.isNotEmpty && !remoteIds.contains(id)) {
          await txn.delete(
            'tasks',
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    });
  }

  @override
  Future<void> mergeFamilyTasks(List<TaskItem> items) async {
    final familyItems = items.where((t) => t.isFamily).toList();
    if (familyItems.isEmpty) return;
    await _db.transaction((txn) async {
      for (final item in familyItems) {
        await txn.insert(
          'tasks',
          item.toDbRow(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  @override
  Future<List<TaskItem>> readTasks({
    String? ownerKey,
    bool includeAll = false,
  }) async {
    final rows = await _db.query(
      'tasks',
      where: includeAll || ownerKey == null
          ? null
          : '(owner_key = ? OR is_family = 1)',
      whereArgs: includeAll || ownerKey == null ? null : [ownerKey],
      orderBy: 'updated_at DESC',
    );
    return rows.map(TaskItem.fromDbRow).toList();
  }

  @override
  Future<void> putPending(PendingEvent event) async {
    await _db.insert(
      'pending_events',
      event.toDbRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<PendingEvent>> readPending({
    int limit = 200,
  }) async {
    final rows = await _db.query(
      'pending_events',
      orderBy: 'happened_at ASC',
      limit: limit,
    );
    return rows.map(PendingEvent.fromDbRow).toList();
  }

  @override
  Future<void> removePending(List<String> eventIds) async {
    if (eventIds.isEmpty) return;
    final placeholders = List.filled(eventIds.length, '?').join(',');
    await _db.delete(
      'pending_events',
      where: 'event_id IN ($placeholders)',
      whereArgs: eventIds,
    );
  }

  @override
  Future<String> readSince() async {
    final rows = await _db.query(
      'meta',
      where: 'k = ?',
      whereArgs: ['since'],
      limit: 1,
    );
    if (rows.isEmpty) return '1970-01-01T00:00:00';
    return (rows.first['v'] ?? '1970-01-01T00:00:00').toString();
  }

  @override
  Future<void> writeSince(String value) async {
    await _db.insert(
      'meta',
      {
        'k': 'since',
        'v': value,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
