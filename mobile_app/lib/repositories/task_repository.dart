import '../models/task_item.dart';
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
  }

  Future<void> syncFull() async {
    await _ensureReady();
    await _syncService!.syncFull();
  }

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
