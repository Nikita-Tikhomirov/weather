import '../models/task_item.dart';

class TaskDraft {
  const TaskDraft({
    required this.title,
    required this.details,
    required this.dueDate,
    required this.time,
    required this.priority,
    required this.workflowStatus,
    required this.isFamily,
    required this.assignees,
    required this.durationMinutes,
    required this.reminderOffsetsMinutes,
    this.projectId = '',
    this.groupId = '',
  });

  final String title;
  final String details;
  final String dueDate;
  final String time;
  final Priority priority;
  final WorkflowStatus workflowStatus;
  final bool isFamily;
  final List<String> assignees;
  final int durationMinutes;
  final List<int> reminderOffsetsMinutes;
  final String projectId;
  final String groupId;

  TaskDraft copyWith({
    String? title,
    String? details,
    String? dueDate,
    String? time,
    Priority? priority,
    WorkflowStatus? workflowStatus,
    bool? isFamily,
    List<String>? assignees,
    int? durationMinutes,
    List<int>? reminderOffsetsMinutes,
    String? projectId,
    String? groupId,
  }) {
    return TaskDraft(
      title: title ?? this.title,
      details: details ?? this.details,
      dueDate: dueDate ?? this.dueDate,
      time: time ?? this.time,
      priority: priority ?? this.priority,
      workflowStatus: workflowStatus ?? this.workflowStatus,
      isFamily: isFamily ?? this.isFamily,
      assignees: assignees ?? this.assignees,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      reminderOffsetsMinutes:
          reminderOffsetsMinutes ?? this.reminderOffsetsMinutes,
      projectId: projectId ?? this.projectId,
      groupId: groupId ?? this.groupId,
    );
  }
}
