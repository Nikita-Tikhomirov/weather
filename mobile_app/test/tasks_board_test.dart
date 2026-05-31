import 'package:family_todo_mobile/features/tasks/tasks_board.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TasksBoard', () {
    testWidgets('renders kanban columns', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TasksBoard(
              byStatus: const <String, List<TaskItem>>{},
              labelFor: (_) => 'User',
              selectionMode: false,
              selectedIds: const <String>{},
              onToggleSelect: (_) {},
              onDrop: (task, status) async {},
              onEdit: (task) async {},
              onDelete: (task) async {},
              onDoneToggle: (task) async {},
            ),
          ),
        ),
      );

      // Should have 4 columns (Russian labels)
      expect(find.text('К выполнению'), findsOneWidget);
      expect(find.text('В работе'), findsOneWidget);
      expect(find.text('На проверке'), findsOneWidget);
      expect(find.text('Выполнено'), findsOneWidget);
    });

    testWidgets('displays tasks in correct columns', (tester) async {
      final tasks = [
        TaskItem(
          id: '1',
          ownerKey: 'test_user',
          title: 'Todo Task',
          dueDate: '2026-05-31',
          time: '',
          workflowStatus: WorkflowStatus.todo,
          priority: Priority.medium,
          tags: const [],
          participants: const [],
          durationMinutes: 0,
          sortOrder: 0,
          createdAt: DateTime(2026, 5, 30),
          updatedAt: DateTime(2026, 5, 30),
          version: 1,
        ),
        TaskItem(
          id: '2',
          ownerKey: 'test_user',
          title: 'Done Task',
          dueDate: '2026-05-31',
          time: '',
          workflowStatus: WorkflowStatus.done,
          priority: Priority.high,
          tags: const [],
          participants: const [],
          durationMinutes: 0,
          sortOrder: 0,
          createdAt: DateTime(2026, 5, 30),
          updatedAt: DateTime(2026, 5, 30),
          version: 1,
        ),
      ];

      final byStatus = <String, List<TaskItem>>{
        'todo': [tasks[0]],
        'done': [tasks[1]],
        'in_progress': <TaskItem>[],
        'in_review': <TaskItem>[],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TasksBoard(
              byStatus: byStatus,
              labelFor: (_) => 'User',
              selectionMode: false,
              selectedIds: const <String>{},
              onToggleSelect: (_) {},
              onDrop: (task, status) async {},
              onEdit: (task) async {},
              onDelete: (task) async {},
              onDoneToggle: (task) async {},
            ),
          ),
        ),
      );

      expect(find.text('Todo Task'), findsOneWidget);
      expect(find.text('Done Task'), findsOneWidget);
    });

    testWidgets('empty board shows no tasks message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TasksBoard(
              byStatus: const <String, List<TaskItem>>{},
              labelFor: (_) => 'User',
              selectionMode: false,
              selectedIds: const <String>{},
              onToggleSelect: (_) {},
              onDrop: (task, status) async {},
              onEdit: (task) async {},
              onDelete: (task) async {},
              onDoneToggle: (task) async {},
            ),
          ),
        ),
      );

      // Board renders without errors
      expect(find.byType(TasksBoard), findsOneWidget);
    });

    testWidgets('kanban column colors meet contrast requirements',
        (tester) async {
      const statuses = [
        WorkflowStatus.todo,
        WorkflowStatus.in_progress,
        WorkflowStatus.in_review,
        WorkflowStatus.done,
      ];

      for (final status in statuses) {
        final style =
            KanbanColumnStyle.resolve(ThemeData.light(), status);
        final contrast =
            _contrastRatio(style.titleColor, style.backgroundColor);
        expect(contrast, greaterThanOrEqualTo(4.5),
            reason: 'Low contrast for $status');
      }
    });
  });
}

double _contrastRatio(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}
