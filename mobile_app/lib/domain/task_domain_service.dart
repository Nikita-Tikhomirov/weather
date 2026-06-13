import '../models/task_item.dart';
import 'task_draft.dart';

class TaskValidationError {
  const TaskValidationError._();

  static const titleRequired = 'title_required';
  static const projectRequired = 'project_required';
  static const invalidStatus = 'invalid_status';
  static const invalidPriority = 'invalid_priority';
  static const invalidReminders = 'invalid_reminders';
  static const projectGroupRequired = 'project_group_required';
  static const projectGroupNotFound = 'project_group_not_found';
  static const projectGroupForbidden = 'project_group_forbidden';
  static const assigneesOutsideGroup = 'assignees_outside_group';
  static const genericFailure = 'generic_failure';

  static const autosaveRecoverableProjectErrors = {
    projectRequired,
    projectGroupRequired,
    projectGroupNotFound,
    projectGroupForbidden,
    assigneesOutsideGroup,
  };
}

class TaskDomainService {
  static final Set<WorkflowStatus> allowedStatuses =
      WorkflowStatus.values.toSet();
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
      return TaskValidationError.titleRequired;
    }
    if (draft.projectId.isEmpty) {
      return TaskValidationError.projectRequired;
    }
    if (!allowedStatuses.contains(draft.workflowStatus)) {
      return TaskValidationError.invalidStatus;
    }
    if (!allowedPriority.contains(draft.priority)) {
      return TaskValidationError.invalidPriority;
    }

    final invalidOffsets = draft.reminderOffsetsMinutes
        .where((offset) => !allowedReminderOffsets.contains(offset))
        .toList();
    if (invalidOffsets.isNotEmpty) {
      return TaskValidationError.invalidReminders;
    }
    if (draft.projectId.isNotEmpty) {
      if (draft.groupId.isEmpty) {
        return TaskValidationError.projectGroupRequired;
      }
      final groupMembers = projectGroupMembers[draft.groupId] ?? const [];
      if (groupMembers.isEmpty) {
        return TaskValidationError.projectGroupNotFound;
      }
      final isProjectOwner =
          projectOwnerKey.isNotEmpty && projectOwnerKey == actorProfile;
      final isGroupMember = groupMembers.contains(actorProfile);
      if (!isProjectOwner && !isGroupMember) {
        return TaskValidationError.projectGroupForbidden;
      }
      final invalidAssignees =
          draft.assignees.where((assignee) => !groupMembers.contains(assignee));
      if (invalidAssignees.isNotEmpty) {
        return TaskValidationError.assigneesOutsideGroup;
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
              collaboration: draft.collaboration,
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
      collaboration: draft.collaboration,
      durationMinutes: draft.durationMinutes,
      updatedAt: nowIso,
      version: (existing?.version ?? 0) + 1,
    );
  }
}
