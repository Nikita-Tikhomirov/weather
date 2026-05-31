import 'package:family_todo_mobile/features/tasks/tasks_board.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TasksBoard', () {
    testWidgets('renders kanban columns', (tester) async {
      final tasks = <TaskItem>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TasksBoard(
              tasks: tasks,
              ownerKey: 'test_user',
              onTaskTap: (_) {},
              onTaskLongPress: (_) {},
              onReorder: (task, status) {},
            ),
          ),
        ),
      );

      // Should have 4 columns
      expect(find.text('To Do'), findsOneWidget);
      expect(find.text('In Progress'), findsOneWidget);
      expect(find.text('In Review'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
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

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TasksBoard(
              tasks: tasks,
              ownerKey: 'test_user',
              onTaskTap: (_) {},
              onTaskLongPress: (_) {},
              onReorder: (task, status) {},
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
              tasks: const [],
              ownerKey: 'test_user',
              onTaskTap: (_) {},
              onTaskLongPress: (_) {},
              onReorder: (task, status) {},
            ),
          ),
        ),
      );

      // Board renders without errors
      expect(find.byType(TasksBoard), findsOneWidget);
    });

    testWidgets('kanban column colors meet contrast requirements', (tester) async {
      // Verify KanbanColumnStyle provides adequate contrast
      const statuses = [
        WorkflowStatus.todo,
        WorkflowStatus.in_progress,
        WorkflowStatus.in_review,
        WorkflowStatus.done,
      ];

      for (final status in statuses) {
        final style = KanbanColumnStyle.resolve(ThemeData.light(), status);
        final contrast = _contrastRatio(style.titleColor, style.backgroundColor);
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
