import 'task_item.dart';
import 'task_project.dart';
import 'family_group.dart';

class PullSnapshot {
  PullSnapshot({
    required this.tasks,
    required this.familyTasks,
    required this.serverTime,
    required this.nextCursor,
    required this.isDelta,
    this.projects = const [],
    this.familyGroups = const [],
    this.projectGroupMap = const {},
  });

  final List<TaskItem> tasks;
  final List<TaskItem> familyTasks;
  final String serverTime;
  final String nextCursor;
  final bool isDelta;
  final List<TaskProject> projects;
  final List<FamilyGroup> familyGroups;
  final Map<String, List<String>> projectGroupMap;
}
