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
  WorkflowStatus.todo: 'К выполнению',
  WorkflowStatus.in_progress: 'В работе',
  WorkflowStatus.in_review: 'На проверке',
  WorkflowStatus.done: 'Выполнено',
};

const kPriorityLabels = {
  Priority.low: 'Низкий',
  Priority.medium: 'Средний',
  Priority.high: 'Высокий',
};

String profileLabel(String key) => kProfileLabels[key] ?? key;
String workflowLabel(WorkflowStatus key) => kWorkflowLabels[key] ?? key.name;
String priorityLabel(Priority key) => kPriorityLabels[key] ?? key.name;
