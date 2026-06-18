import 'package:family_todo_mobile/app/app_labels.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile fallbacks use English labels', () {
    expect(profileLabel('nik'), 'Nik');
    expect(profileLabel('nastya'), 'Nastya');
    expect(profileLabel('misha'), 'Misha');
    expect(profileLabel('arisha'), 'Arisha');
    expect(profileLabel('family'), 'Family');
    expect(profileLabel('tudushker'), 'Tudushker');
    expect(profileLabel('unknown'), 'unknown');

    for (final key in ['nik', 'nastya', 'misha', 'arisha', 'family']) {
      expect(profileLabel(key), isNot(contains(RegExp(r'[А-Яа-яЁё]'))));
    }
  });

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
