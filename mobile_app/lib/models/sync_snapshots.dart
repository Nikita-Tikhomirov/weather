import 'package:flutter/foundation.dart';

import 'task_item.dart';
import 'task_project.dart';
import 'family_group.dart';

@immutable
class PullSnapshot {
  const PullSnapshot({
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

  Map<String, dynamic> toJson() {
    return {
      'tasks': tasks.map((t) => t.toJson()).toList(),
      'family_tasks': familyTasks.map((t) => t.toJson()).toList(),
      'server_time': serverTime,
      'next_cursor': nextCursor,
      'is_delta': isDelta,
      'projects': projects.map((p) => p.toJson()).toList(),
      'family_groups': familyGroups.map((g) => g.toJson()).toList(),
      'project_group_map': projectGroupMap,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PullSnapshot &&
          runtimeType == other.runtimeType &&
          listEquals(tasks, other.tasks) &&
          listEquals(familyTasks, other.familyTasks) &&
          serverTime == other.serverTime &&
          nextCursor == other.nextCursor &&
          isDelta == other.isDelta &&
          listEquals(projects, other.projects) &&
          listEquals(familyGroups, other.familyGroups) &&
          mapEquals(projectGroupMap, other.projectGroupMap);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(tasks),
        Object.hashAll(familyTasks),
        serverTime,
        nextCursor,
        isDelta,
        Object.hashAll(projects),
        Object.hashAll(familyGroups),
        Object.hashAll(
          projectGroupMap.entries.map(
            (e) => Object.hash(e.key, Object.hashAll(e.value)),
          ),
        ),
      );

  PullSnapshot copyWith({
    List<TaskItem>? tasks,
    List<TaskItem>? familyTasks,
    String? serverTime,
    String? nextCursor,
    bool? isDelta,
    List<TaskProject>? projects,
    List<FamilyGroup>? familyGroups,
    Map<String, List<String>>? projectGroupMap,
  }) =>
      PullSnapshot(
        tasks: tasks ?? this.tasks,
        familyTasks: familyTasks ?? this.familyTasks,
        serverTime: serverTime ?? this.serverTime,
        nextCursor: nextCursor ?? this.nextCursor,
        isDelta: isDelta ?? this.isDelta,
        projects: projects ?? this.projects,
        familyGroups: familyGroups ?? this.familyGroups,
        projectGroupMap: projectGroupMap ?? this.projectGroupMap,
      );
}
