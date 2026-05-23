import 'package:flutter_test/flutter_test.dart';
import 'package:family_todo_mobile/models/task_item.dart';

void main() {
  group('TaskItem serialization', () {
    test('fromJson reads assignees field', () {
      final json = {
        'id': 'task-1',
        'owner_key': 'nik',
        'is_family': true,
        'title': 'Test task',
        'details': '',
        'due_date': '2025-01-01',
        'time': '12:00',
        'workflow_status': 'todo',
        'priority': 'medium',
        'tags': [],
        'assignees': ['nik', 'misha'],
        'reminder_offsets_minutes': [30],
        'duration_minutes': 60,
        'updated_at': '2025-01-01T00:00:00',
        'version': 1,
      };
      final task = TaskItem.fromJson(json);
      expect(task.assignees, ['nik', 'misha']);
      expect(task.participants, ['nik', 'misha']);
    });

    test('fromJson falls back to participants field', () {
      final json = {
        'id': 'task-2',
        'owner_key': 'nik',
        'is_family': true,
        'title': 'Test task',
        'details': '',
        'due_date': '2025-01-01',
        'time': '12:00',
        'workflow_status': 'todo',
        'priority': 'medium',
        'tags': [],
        'participants': ['nik', 'nastya'],
        'reminder_offsets_minutes': [30],
        'duration_minutes': 60,
        'updated_at': '2025-01-01T00:00:00',
        'version': 1,
      };
      final task = TaskItem.fromJson(json);
      expect(task.assignees, ['nik', 'nastya']);
    });

    test('toJson includes both assignees and participants', () {
      final task = TaskItem(
        id: 'task-3',
        ownerKey: 'nik',
        isFamily: true,
        title: 'Test',
        details: '',
        dueDate: '2025-01-01',
        time: '12:00',
        workflowStatus: 'todo',
        priority: 'medium',
        tags: [],
        assignees: ['nik'],
        reminderOffsetsMinutes: [30],
        durationMinutes: 60,
        updatedAt: '2025-01-01T00:00:00',
        version: 1,
      );
      final json = task.toJson();
      expect(json['assignees'], ['nik']);
      expect(json['participants'], ['nik']);
    });

    test('copyWith preserves assignees', () {
      final task = TaskItem(
        id: 'task-4',
        ownerKey: 'nik',
        isFamily: false,
        title: 'Test',
        details: '',
        dueDate: '2025-01-01',
        time: '12:00',
        workflowStatus: 'todo',
        priority: 'medium',
        tags: [],
        assignees: ['nik'],
        reminderOffsetsMinutes: [30],
        durationMinutes: 60,
        updatedAt: '2025-01-01T00:00:00',
        version: 1,
      );
      final copy = task.copyWith(title: 'Updated');
      expect(copy.title, 'Updated');
      expect(copy.assignees, ['nik']);
      expect(copy.id, 'task-4');
    });
  });

  group('TaskItem family detection', () {
    test('isFamily is true when ownerKey is family', () {
      final task = TaskItem(
        id: 'f-1',
        ownerKey: 'family',
        isFamily: true,
        title: 'Family task',
        details: '',
        dueDate: '2025-01-01',
        time: '12:00',
        workflowStatus: 'todo',
        priority: 'medium',
        tags: [],
        assignees: ['nik', 'misha'],
        reminderOffsetsMinutes: [],
        durationMinutes: 30,
        updatedAt: '2025-01-01T00:00:00',
        version: 1,
      );
      expect(task.isFamily, isTrue);
      expect(task.ownerKey, 'family');
    });
  });
}
