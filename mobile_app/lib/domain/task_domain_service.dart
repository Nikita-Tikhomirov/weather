import '../models/task_item.dart';
import 'task_draft.dart';

class TaskDomainService {
  static final Set<WorkflowStatus> allowedStatuses = WorkflowStatus.values.toSet();
  static final Set<Priority> allowedPriority = Priority.values.toSet();
  static const Set<int> allowedReminderOffsets = {
    1440,
    720,
    180,
    120,
    60,
    30,
    15,
    5,
  };

  String? validateDraft({
    required TaskDraft draft,
    required String actorProfile,
    String projectOwnerKey = '',
    Map<String, List<String>> projectGroupMembers = const {},
  }) {
    if (draft.title.trim().isEmpty) {
      return 'Укажите название задачи.';
    }
    if (draft.projectId.isEmpty) {
      return 'Выберите проект.';
    }
    if (!allowedStatuses.contains(draft.workflowStatus)) {
      return 'Некорректный статус задачи.';
    }
    if (!allowedPriority.contains(draft.priority)) {
      return 'Некорректный приоритет задачи.';
    }

    final invalidOffsets = draft.reminderOffsetsMinutes
        .where((offset) => !allowedReminderOffsets.contains(offset))
        .toList();
    if (invalidOffsets.isNotEmpty) {
      return 'Некорректные интервалы напоминаний.';
    }
    if (draft.projectId.isNotEmpty) {
      if (draft.groupId.isEmpty) {
        return 'Выберите группу проекта.';
      }
      final groupMembers = projectGroupMembers[draft.groupId] ?? const [];
      if (groupMembers.isEmpty) {
        return 'Выбранная группа не входит в проект.';
      }
      final isProjectOwner =
          projectOwnerKey.isNotEmpty && projectOwnerKey == actorProfile;
      final isGroupMember = groupMembers.contains(actorProfile);
      if (!isProjectOwner && !isGroupMember) {
        return 'Нет прав на создание задачи в этой группе.';
      }
      final invalidAssignees =
          draft.assignees.where((assignee) => !groupMembers.contains(assignee));
      if (invalidAssignees.isNotEmpty) {
        return 'Ответственные должны входить в выбранную группу.';
      }
    }

    return null;
  }

  /// Returns true if the task should be visible to the actor.
  ///
  /// Rules (project-scoped, no shared tasks):
  /// 1. If a project filter is active, only tasks of that project are shown.
  /// 2. Tasks without a project are visible only to the owner/assignee.
  /// 3. Tasks with a project are visible if actor is assignee OR belongs to the
  ///    task's group.
  bool isVisibleToActor({
    required TaskItem task,
    required String actorProfile,
    required Set<String> actorGroupIds,
    String currentProjectId = '',
  }) {
    if (currentProjectId.isNotEmpty) {
      if (task.projectId != currentProjectId) return false;
      if (task.assignees.contains(actorProfile)) return true;
      if (task.groupId.isNotEmpty && actorGroupIds.contains(task.groupId)) {
        return true;
      }
      return false;
    }

    if (task.assignees.contains(actorProfile)) return true;

    if (task.groupId.isNotEmpty && actorGroupIds.contains(task.groupId)) {
      return true;
    }

    return false;
  }

  TaskItem materializeTask({
    required TaskDraft draft,
    required String actorProfile,
    required DateTime now,
    TaskItem? existing,
  }) {
    final nowIso = now.toIso8601String();
    final assignees = draft.assignees.toList()..sort();
    final reminders = draft.reminderOffsetsMinutes.toSet().toList()
      ..sort((a, b) => b.compareTo(a));

    return (existing ??
            TaskItem(
              id: 'm-${now.microsecondsSinceEpoch}',
              ownerKey: draft.isFamily ? 'family' : actorProfile,
              isFamily: draft.isFamily,
              projectId: draft.projectId,
              groupId: draft.groupId,
              title: draft.title.trim(),
              details: draft.details.trim(),
              dueDate: draft.dueDate,
              time: draft.time,
              workflowStatus: draft.workflowStatus,
              priority: draft.priority,
              tags: const [],
              assignees: assignees,
              reminderOffsetsMinutes: reminders,
              durationMinutes: draft.durationMinutes,
              updatedAt: nowIso,
              version: 1,
            ))
        .copyWith(
      ownerKey: draft.isFamily ? 'family' : actorProfile,
      isFamily: draft.isFamily,
      projectId: draft.projectId,
      groupId: draft.groupId,
      title: draft.title.trim(),
      details: draft.details.trim(),
      dueDate: draft.dueDate,
      time: draft.time,
      workflowStatus: draft.workflowStatus,
      priority: draft.priority,
      assignees: assignees,
      reminderOffsetsMinutes: reminders,
      durationMinutes: draft.durationMinutes,
      updatedAt: nowIso,
      version: (existing?.version ?? 0) + 1,
    );
  }
}
