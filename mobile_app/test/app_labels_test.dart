import 'package:family_todo_mobile/app/app_labels.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workflow and priority fallbacks use English labels', () {
    expect(workflowLabel(WorkflowStatus.todo), 'To do');
    expect(workflowLabel(WorkflowStatus.in_progress), 'In progress');
    expect(workflowLabel(WorkflowStatus.in_review), 'In review');
    expect(workflowLabel(WorkflowStatus.done), 'Done');
    expect(workflowLabel(WorkflowStatus.archive), 'Archive');
    expect(priorityLabel(Priority.low), 'Low');
    expect(priorityLabel(Priority.medium), 'Medium');
    expect(priorityLabel(Priority.high), 'High');
  });
}
