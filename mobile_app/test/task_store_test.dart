import 'dart:io';

import 'package:family_todo_mobile/domain/task_domain_service.dart';
import 'package:family_todo_mobile/contracts/task_data_source.dart';
import 'package:family_todo_mobile/models/family_group.dart';
import 'package:family_todo_mobile/models/pending_event.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:family_todo_mobile/models/task_project.dart';
import 'package:family_todo_mobile/repositories/task_repository.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:family_todo_mobile/services/local_db.dart';
import 'package:family_todo_mobile/services/project_selection_storage.dart';
import 'package:family_todo_mobile/state/task_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// In-memory fake TaskDataSource for testing TaskStore.
class _FakeDataSource implements TaskDataSource {
  final List<TaskItem> _tasks = [];
  final List<PendingEvent> _pending = [];
  String _since = '1970-01-01T00:00:00';

  @override
  Future<void> upsertTask(TaskItem task) async {
    _tasks.removeWhere((t) => t.id == task.id);
    _tasks.add(task);
  }

  @override
  Future<void> deleteTask(String id) async {
    _tasks.removeWhere((t) => t.id == id);
  }

  @override
  Future<List<TaskItem>> readTasks({
    String? ownerKey,
    bool includeAll = false,
  }) async {
    if (includeAll) return _tasks.toList();
    return _tasks.where((t) => t.ownerKey == ownerKey || t.isFamily).toList();
  }

  @override
  Future<void> replacePersonalTasks({
    required String ownerKey,
    required List<TaskItem> items,
  }) async {
    _tasks.removeWhere((t) => t.ownerKey == ownerKey && !t.isFamily);
    _tasks.addAll(items);
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
    _tasks.removeWhere((t) => t.isFamily);
    _tasks.addAll(items);
  }

  @override
  Future<void> putPending(PendingEvent event) async {
    _pending.add(event);
  }

  @override
  Future<List<PendingEvent>> readPending({int limit = 200}) async {
    return _pending.toList();
  }

  @override
  Future<void> removePending(List<String> eventIds) async {
    _pending.removeWhere((e) => eventIds.contains(e.eventId));
  }

  @override
  Future<String> readSince() async => _since;

  @override
  Future<void> writeSince(String cursor) async {
    _since = cursor;
  }

  Future<void> replaceTasks(List<TaskItem> items) async {
    _tasks.clear();
    _tasks.addAll(items);
  }
}

class _FakeRepository extends TaskRepository {
  _FakeRepository({required this.dataSource, required super.db})
      : super(
          api: ApiClient(baseUrl: 'http://localhost', apiKey: 'test-key'),
        );

  final _FakeDataSource dataSource;
  String _actorProfile = 'nik';
  List<TaskProject> fakeProjects = const <TaskProject>[];
  List<FamilyGroup> fakeGroups = const <FamilyGroup>[];
  Map<String, List<String>> fakeProjectGroupMap =
      const <String, List<String>>{};

  @override
  Future<void> bindActor(String actorProfile) async {
    _actorProfile = actorProfile;
  }

  @override
  Future<List<TaskItem>> readVisibleTasks() {
    return dataSource.readTasks(ownerKey: _actorProfile);
  }

  @override
  Future<List<TaskProject>> readProjects() async {
    return fakeProjects;
  }

  @override
  Future<List<FamilyGroup>> readFamilyGroups() async {
    return fakeGroups;
  }

  @override
  Future<Map<String, List<String>>> readProjectGroupMap() async {
    return fakeProjectGroupMap;
  }

  @override
  Future<void> upsert(TaskItem task) {
    return dataSource.upsertTask(task);
  }

  @override
  Future<void> delete(TaskItem task) {
    return dataSource.deleteTask(task.id);
  }
}

class _MemoryProjectSelectionStorage implements ProjectSelectionStorage {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String> readLastProjectId(String ownerKey) async {
    return values[ownerKey] ?? '';
  }

  @override
  Future<void> saveLastProjectId(String ownerKey, String projectId) async {
    values[ownerKey] = projectId;
  }

  @override
  Future<void> clearLastProjectId(String ownerKey) async {
    values.remove(ownerKey);
  }
}

TaskItem _task(
  String id, {
  String ownerKey = 'nik',
  bool isFamily = false,
  WorkflowStatus workflowStatus = WorkflowStatus.todo,
  String dueDate = '2026-05-24',
  List<String>? assignees,
}) {
  return TaskItem(
    id: id,
    ownerKey: ownerKey,
    isFamily: isFamily,
    title: 'Task $id',
    details: '',
    dueDate: dueDate,
    time: '12:00',
    workflowStatus: workflowStatus,
    priority: Priority.medium,
    tags: const [],
    assignees: assignees ?? [ownerKey],
    reminderOffsetsMinutes: const [],
    durationMinutes: 0,
    updatedAt: '2026-05-24T12:00:00',
    version: 1,
  );
}

void main() {
  group('TaskStore', () {
    late _FakeDataSource ds;
    late Directory tempDir;
    late LocalDb repoDb;
    late TaskStore store;

    setUp(() async {
      ds = _FakeDataSource();
      tempDir = await Directory.systemTemp.createTemp('task_store_db_test_');
      repoDb = await LocalDb.open(
        databasePath: p.join(tempDir.path, 'family_todo_mobile.db'),
      );
      final repo = _FakeRepository(
        dataSource: ds,
        db: repoDb,
      );
      store = TaskStore(
        repository: repo,
        domainService: TaskDomainService(),
        projectSelectionStorage: _MemoryProjectSelectionStorage(),
      );
      await store.initialize(initialOwner: 'nik');
    });

    tearDown(() async {
      await repoDb.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    group('dashboard', () {
      test('counts today tasks, done, family, overdue', () async {
        final today = DateTime.now();
        final todayKey =
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        final yesterdayKey =
            '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

        await ds.upsertTask(
          _task(
            't1',
            dueDate: todayKey,
            workflowStatus: WorkflowStatus.done,
          ),
        );
        await ds.upsertTask(
          _task(
            't2',
            dueDate: todayKey,
            workflowStatus: WorkflowStatus.todo,
          ),
        );
        await ds.upsertTask(
          _task(
            't3',
            dueDate: todayKey,
            isFamily: true,
            ownerKey: 'family',
            assignees: ['nik'],
            workflowStatus: WorkflowStatus.todo,
          ),
        );
        await ds.upsertTask(
          _task(
            't4',
            dueDate: yesterdayKey,
            workflowStatus: WorkflowStatus.todo,
          ),
        );

        await store.refreshLocal();

        final dash = store.dashboard.value;
        expect(dash.todayKey, todayKey);
        expect(dash.todayTotal, 3); // t1, t2, t3
        expect(dash.doneToday, 1); // t1
        expect(dash.familyToday, 1); // t3
        expect(dash.overdue, 1); // t4 — yesterday, not done
      });
    });

    group('kanban grouping', () {
      test('groups tasks by workflow status', () async {
        await ds.upsertTask(_task('k1', workflowStatus: WorkflowStatus.todo));
        await ds.upsertTask(
          _task('k2', workflowStatus: WorkflowStatus.in_progress),
        );
        await ds.upsertTask(_task('k3', workflowStatus: WorkflowStatus.done));

        await store.refreshLocal();

        final byStatus = store.personalByStatus.value;
        expect(byStatus['todo']!.length, 1);
        expect(byStatus['in_progress']!.length, 1);
        expect(byStatus['done']!.length, 1);
        expect(byStatus['archive']!.length, 0);
      });
    });

    group('undo', () {
      test('undo restores deleted task', () async {
        final task = _task('undo-1');
        await ds.upsertTask(task);
        await store.refreshLocal();

        // Delete it
        await store.delete(task);
        var tasks = await ds.readTasks(ownerKey: 'nik');
        expect(tasks.any((t) => t.id == 'undo-1'), isFalse);

        // Undo
        final undone = await store.undoLastAction();
        expect(undone, isTrue);
        tasks = await ds.readTasks(ownerKey: 'nik');
        expect(tasks.any((t) => t.id == 'undo-1'), isTrue);
      });

      test('undo returns false when nothing to undo', () async {
        final undone = await store.undoLastAction();
        expect(undone, isFalse);
      });
    });

    group('toggle done', () {
      test('toggles todo to done and back', () async {
        final task = _task('toggle-1', workflowStatus: WorkflowStatus.todo);
        await ds.upsertTask(task);
        await store.refreshLocal();

        await store.toggleDone(task);
        var tasks = await ds.readTasks(ownerKey: 'nik');
        var updated = tasks.firstWhere((t) => t.id == 'toggle-1');
        expect(updated.workflowStatus, WorkflowStatus.done);

        await store.toggleDone(updated);
        tasks = await ds.readTasks(ownerKey: 'nik');
        updated = tasks.firstWhere((t) => t.id == 'toggle-1');
        expect(updated.workflowStatus, WorkflowStatus.todo);
      });
    });

    group('search', () {
      test('filters tasks by search query', () async {
        await ds.upsertTask(_task('s1'));
        await ds.upsertTask(_task('s2'));
        const specialTitled = TaskItem(
          id: 's3',
          ownerKey: 'nik',
          isFamily: false,
          title: 'Special task',
          details: '',
          dueDate: '2026-05-24',
          time: '12:00',
          workflowStatus: WorkflowStatus.todo,
          priority: Priority.medium,
          tags: [],
          assignees: ['nik'],
          reminderOffsetsMinutes: [],
          durationMinutes: 0,
          updatedAt: '2026-05-24T12:00:00',
          version: 1,
        );
        await ds.upsertTask(specialTitled);
        await store.refreshLocal();

        store.setSearchQuery('Special');

        final filtered = store.personalByStatus.value.values
            .expand((items) => items)
            .toList();
        expect(filtered.length, 1);
        expect(filtered.first.title, 'Special task');
      });
    });

    group('project selection persistence', () {
      TaskProject project(String id) {
        return TaskProject(
          id: id,
          name: 'Project $id',
          description: '',
          ownerKey: 'nik',
          createdAt: '2026-05-31T12:00:00',
          updatedAt: '2026-05-31T12:00:00',
        );
      }

      test('restores last valid project on initialize', () async {
        final storage = _MemoryProjectSelectionStorage();
        await storage.saveLastProjectId('nik', 'project-2');
        final repo = _FakeRepository(dataSource: ds, db: repoDb)
          ..fakeProjects = [project('project-1'), project('project-2')];
        final localStore = TaskStore(
          repository: repo,
          domainService: TaskDomainService(),
          projectSelectionStorage: storage,
        );

        await localStore.initialize(initialOwner: 'nik');

        expect(localStore.currentProjectId.value, 'project-2');
        localStore.dispose();
      });

      test('falls back to first project when saved project is stale', () async {
        final storage = _MemoryProjectSelectionStorage();
        await storage.saveLastProjectId('nik', 'missing-project');
        final repo = _FakeRepository(dataSource: ds, db: repoDb)
          ..fakeProjects = [project('project-1')];
        final localStore = TaskStore(
          repository: repo,
          domainService: TaskDomainService(),
          projectSelectionStorage: storage,
        );

        await localStore.initialize(initialOwner: 'nik');

        expect(localStore.currentProjectId.value, 'project-1');
        expect(await storage.readLastProjectId('nik'), 'project-1');
        localStore.dispose();
      });

      test('selects first project when no saved project exists', () async {
        final storage = _MemoryProjectSelectionStorage();
        final repo = _FakeRepository(dataSource: ds, db: repoDb)
          ..fakeProjects = [project('project-1'), project('project-2')];
        final localStore = TaskStore(
          repository: repo,
          domainService: TaskDomainService(),
          projectSelectionStorage: storage,
        );

        await localStore.initialize(initialOwner: 'nik');

        expect(localStore.currentProjectId.value, 'project-1');
        expect(await storage.readLastProjectId('nik'), 'project-1');
        localStore.dispose();
      });

      test('setCurrentProject saves selected project', () async {
        final storage = _MemoryProjectSelectionStorage();
        final repo = _FakeRepository(dataSource: ds, db: repoDb)
          ..fakeProjects = [project('project-1')];
        final localStore = TaskStore(
          repository: repo,
          domainService: TaskDomainService(),
          projectSelectionStorage: storage,
        );
        await localStore.initialize(initialOwner: 'nik');

        localStore.setCurrentProject('project-1');

        expect(await storage.readLastProjectId('nik'), 'project-1');
        localStore.dispose();
      });
    });
  });
}
