import '../models/pending_event.dart';
import '../models/task_item.dart';

/// Abstract data source for task persistence and sync.
///
/// Implementations can be SQLite (mobile), in-memory (tests), or a
/// remote-only adapter.  This contract lets [TaskStore] and [TaskRepository]
/// be unit-tested without a real database.
abstract class TaskDataSource {
  /// Persist or replace a single task in the local store.
  Future<void> upsertTask(TaskItem task);

  /// Remove a task by its id.
  Future<void> deleteTask(String id);

  /// Atomically replace the full set of personal tasks for [ownerKey].
  Future<void> replacePersonalTasks({
    required String ownerKey,
    required List<TaskItem> items,
  });

  /// Merge incoming personal tasks (upsert-by-id) for [ownerKey].
  Future<void> mergePersonalTasks({
    required String ownerKey,
    required List<TaskItem> items,
  });

  /// Reconcile family-tasks: upsert incoming, delete stale remote ids.
  Future<void> reconcileFamilyTasks(List<TaskItem> items);

  /// Merge family tasks (upsert only — no deletion).
  Future<void> mergeFamilyTasks(List<TaskItem> items);

  /// Read tasks visible to [ownerKey] (their own tasks + family tasks).
  Future<List<TaskItem>> readTasks({
    String? ownerKey,
    bool includeAll = false,
  });

  /// ── Pending-event queue (offline outbox) ──

  Future<void> putPending(PendingEvent event);

  Future<List<PendingEvent>> readPending({int limit = 200});

  Future<void> removePending(List<String> eventIds);

  /// ── Sync cursor ──

  Future<String> readSince();

  Future<void> writeSince(String cursor);
}
