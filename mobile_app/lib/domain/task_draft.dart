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
  });

  final String title;
  final String details;
  final String dueDate;
  final String time;
  final String priority;
  final String workflowStatus;
  final bool isFamily;
  final List<String> assignees;
  final int durationMinutes;
}
