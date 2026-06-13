import '../models/task_item.dart';

/// Human-readable labels for actor profiles shown in UI.
const kProfileLabels = {
  'nik': 'Ник',
  'nastya': 'Настя',
  'misha': 'Миша',
  'arisha': 'Ариша',
  'family': 'Общие',
  'tudushker': 'Тудушкер',
};

const kWorkflowLabels = {
  WorkflowStatus.todo: 'To do',
  WorkflowStatus.in_progress: 'In progress',
  WorkflowStatus.in_review: 'In review',
  WorkflowStatus.done: 'Done',
  WorkflowStatus.archive: 'Archive',
};

const kPriorityLabels = {
  Priority.low: 'Low',
  Priority.medium: 'Medium',
  Priority.high: 'High',
};

String profileLabel(String key) => kProfileLabels[key] ?? key;
String workflowLabel(WorkflowStatus key) => kWorkflowLabels[key] ?? key.name;
String priorityLabel(Priority key) => kPriorityLabels[key] ?? key.name;
