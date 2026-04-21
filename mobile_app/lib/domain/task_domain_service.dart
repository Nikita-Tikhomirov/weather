import '../models/task_item.dart';
import 'task_draft.dart';

class TaskDomainService {
  static const Set<String> adults = {'nik', 'nastya'};
  static const Set<String> allowedStatuses = {
    'todo',
    'in_progress',
    'in_review',
    'done',
  };
  static const Set<String> allowedPriority = {'low', 'medium', 'high'};

  String? validateDraft({
    required TaskDraft draft,
    required String actorProfile,
  }) {
    if (draft.title.trim().isEmpty) {
      return 'Укажите название задачи.';
    }
    if (draft.isFamily && !adults.contains(actorProfile)) {
      return 'Семейные задачи можно создавать только из профиля Ник/Настя.';
    }
    if (draft.isFamily && draft.assignees.isEmpty) {
      return 'Выберите хотя бы одного ответственного.';
    }
    if (!allowedStatuses.contains(draft.workflowStatus)) {
      return 'Некорректный статус задачи.';
    }
    if (!allowedPriority.contains(draft.priority)) {
      return 'Некорректный приоритет задачи.';
    }
    return null;
  }

  TaskItem materializeTask({
    required TaskDraft draft,
    required String actorProfile,
    required DateTime now,
    TaskItem? existing,
  }) {
    final nowIso = now.toIso8601String();
    final assignees = draft.assignees.toList()..sort();
    return (existing ??
            TaskItem(
              id: 'm-${now.microsecondsSinceEpoch}',
              ownerKey: draft.isFamily ? 'family' : actorProfile,
              isFamily: draft.isFamily,
              title: draft.title.trim(),
              details: draft.details.trim(),
              dueDate: draft.dueDate,
              time: draft.time,
              workflowStatus: draft.workflowStatus,
              priority: draft.priority,
              tags: const [],
              assignees: assignees,
              durationMinutes: draft.durationMinutes,
              updatedAt: nowIso,
              version: 1,
            ))
        .copyWith(
          ownerKey: draft.isFamily ? 'family' : actorProfile,
          isFamily: draft.isFamily,
          title: draft.title.trim(),
          details: draft.details.trim(),
          dueDate: draft.dueDate,
          time: draft.time,
          workflowStatus: draft.workflowStatus,
          priority: draft.priority,
          assignees: assignees,
          durationMinutes: draft.durationMinutes,
          updatedAt: nowIso,
          version: (existing?.version ?? 0) + 1,
        );
  }
}
