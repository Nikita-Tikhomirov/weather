part of 'local_db.dart';

// ── Projects CRUD ──────────────────────────────────────────

Future<void> replaceProjects(List<TaskProject> projects) async {
  await _db.transaction((txn) async {
    await txn.delete('task_projects');
    for (final item in projects) {
      await txn.insert(
        'task_projects',
        item.toDbRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  });
}

Future<List<TaskProject>> readProjects() async {
  final rows = await _db.query('task_projects', orderBy: 'name ASC, id ASC');
  return rows.map(TaskProject.fromDbRow).toList();
}

Future<void> upsertProjectLocal(TaskProject project) async {
  await _db.insert(
    'task_projects',
    project.toDbRow(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> deleteProjectLocal(String id) async {
  await _db.delete('task_projects', where: 'id = ?', whereArgs: [id]);
  await _db.delete('project_family_groups_local',
      where: 'project_id = ?', whereArgs: [id]);
}

// ── Family Groups CRUD ─────────────────────────────────────

Future<void> replaceFamilyGroups(List<FamilyGroup> groups) async {
  await _db.transaction((txn) async {
    await txn.delete('family_groups_local');
    for (final item in groups) {
      await txn.insert(
        'family_groups_local',
        item.toDbRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  });
}

Future<List<FamilyGroup>> readFamilyGroups() async {
  final rows =
      await _db.query('family_groups_local', orderBy: 'name ASC, id ASC');
  return rows.map(FamilyGroup.fromDbRow).toList();
}

Future<void> upsertFamilyGroupLocal(FamilyGroup group) async {
  await _db.insert(
    'family_groups_local',
    group.toDbRow(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

Future<void> deleteFamilyGroupLocal(String id) async {
  await _db.delete('family_groups_local', where: 'id = ?', whereArgs: [id]);
  await _db.delete('project_family_groups_local',
      where: 'group_id = ?', whereArgs: [id]);
}

// ── Project ↔ Group mapping ────────────────────────────────

Future<Map<String, List<String>>> readProjectGroupMap() async {
  final rows = await _db.query('project_family_groups_local');
  final map = <String, List<String>>{};
  for (final row in rows) {
    final pid = (row['project_id'] ?? '').toString();
    final gid = (row['group_id'] ?? '').toString();
    map.putIfAbsent(pid, () => []);
    map[pid]!.add(gid);
  }
  return map;
}

Future<void> replaceProjectGroupMap(Map<String, List<String>> map) async {
  await _db.transaction((txn) async {
    await txn.delete('project_family_groups_local');
    for (final entry in map.entries) {
      for (final gid in entry.value) {
        await txn.insert(
            'project_family_groups_local',
            {
              'project_id': entry.key,
              'group_id': gid,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  });
}

Future<void> setProjectGroupsLocal(
    String projectId, List<String> groupIds) async {
  await _db.transaction((txn) async {
    await txn.delete('project_family_groups_local',
        where: 'project_id = ?', whereArgs: [projectId]);
    for (final gid in groupIds) {
      await txn.insert(
          'project_family_groups_local',
          {
            'project_id': projectId,
            'group_id': gid,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  });
}
