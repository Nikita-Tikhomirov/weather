import 'task_item.dart';

class PullSnapshot {
  PullSnapshot({
    required this.tasks,
    required this.familyTasks,
    required this.serverTime,
    required this.nextCursor,
    required this.isDelta,
  });

  final List<TaskItem> tasks;
  final List<TaskItem> familyTasks;
  final String serverTime;
  final String nextCursor;
  final bool isDelta;
}
