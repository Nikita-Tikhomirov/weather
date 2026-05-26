import '../models/task_item.dart';
import '../models/task_project.dart';
import '../models/family_group.dart';
import '../services/api_client.dart';
import '../services/local_db.dart';
import '../services/sync_service.dart';

class TaskRepository {
  TaskRepository({required this.db, required this.api});

  final LocalDb db;
  final ApiClient api;
  SyncService? _syncService;
  String _actorProfile = 'nik';

  String get actorProfile => _actorProfile;

  Future<void> bindActor(String actorProfile) async {
    _actorProfile = actorProfile;
    _syncService = SyncService(db: db, api: api, actorProfile: _actorProfile);
  }

  Future<List<TaskItem>> readVisibleTasks() {
    return db.readTasks(ownerKey: _actorProfile, includeAll: false);
  }

  Future<void> syncDelta() async {
    await _ensureReady();
    await _syncService!.syncDelta();
    await _syncProjectsAndGroups();
  }

  Future<void> syncFull() async {
    await _ensureReady();
    final snapshot = await _syncService!.syncFull();
    await _applyProjectsAndGroups(snapshot.projects, snapshot.familyGroups,
        snapshot.projectGroupMap);
  }

  Future<void> _syncProjectsAndGroups() async {
    try {
      final snapshot = await api.pull(since: '1970-01-01T00:00:00');
      await _applyProjectsAndGroups(
          snapshot.projects, snapshot.familyGroups, snapshot.projectGroupMap);
    } catch (_) {}
  }

  Future<void> _applyProjectsAndGroups(List<TaskProject> projects,
      List<FamilyGroup> groups, Map<String, List<String>> pgMap) async {
    if (projects.isNotEmpty) {
      await db.replaceProjects(projects);
    }
    if (groups.isNotEmpty) {
      await db.replaceFamilyGroups(groups);
    }
    if (pgMap.isNotEmpty) {
      await db.replaceProjectGroupMap(pgMap);
    }
  }

  Future<List<TaskProject>> readProjects() => db.readProjects();

  Future<List<FamilyGroup>> readFamilyGroups() => db.readFamilyGroups();

  Future<Map<String, List<String>>> readProjectGroupMap() =>
      db.readProjectGroupMap();

  Future<void> upsert(TaskItem task) async {
    await _ensureReady();
    await _syncService!.enqueueUpsert(task);
  }

  Future<void> delete(TaskItem task) async {
    await _ensureReady();
    await _syncService!.enqueueDelete(
      task.id,
      ownerKey: task.ownerKey,
      isFamily: task.isFamily,
    );
  }

  Future<void> _ensureReady() async {
    if (_syncService != null) {
      return;
    }
    await bindActor(_actorProfile);
  }
}
