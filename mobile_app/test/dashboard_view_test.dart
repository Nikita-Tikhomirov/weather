import 'package:family_todo_mobile/features/tasks/dashboard_view.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardView', () {
    testWidgets('renders with empty tasks', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardView(
              tasks: const [],
              ownerKey: 'test_user',
              onTaskTap: (_) {},
              onTaskLongPress: (_) {},
            ),
          ),
        ),
      );

      // Dashboard renders
      expect(find.byType(DashboardView), findsOneWidget);
    });

    testWidgets('displays task list', (tester) async {
      final tasks = [
        TaskItem(
          id: '1',
          ownerKey: 'test_user',
          title: 'Buy groceries',
          dueDate: '2026-05-31',
          time: '18:00',
          workflowStatus: WorkflowStatus.todo,
          priority: Priority.high,
          tags: const [],
          participants: const [],
          durationMinutes: 60,
          sortOrder: 0,
          createdAt: DateTime(2026, 5, 30),
          updatedAt: DateTime(2026, 5, 30),
          version: 1,
        ),
        TaskItem(
          id: '2',
          ownerKey: 'test_user',
          title: 'Read book',
          dueDate: '2026-06-01',
          time: '',
          workflowStatus: WorkflowStatus.todo,
          priority: Priority.low,
          tags: const [],
          participants: const [],
          durationMinutes: 120,
          sortOrder: 1,
          createdAt: DateTime(2026, 5, 30),
          updatedAt: DateTime(2026, 5, 30),
          version: 1,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardView(
              tasks: tasks,
              ownerKey: 'test_user',
              onTaskTap: (_) {},
              onTaskLongPress: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Buy groceries'), findsOneWidget);
      expect(find.text('Read book'), findsOneWidget);
    });

    testWidgets('task tap callback fires', (tester) async {
      TaskItem? tapped;

      final tasks = [
        TaskItem(
          id: '1',
          ownerKey: 'test_user',
          title: 'Test task',
          dueDate: '2026-05-31',
          time: '',
          workflowStatus: WorkflowStatus.todo,
          priority: Priority.medium,
          tags: const [],
          participants: const [],
          durationMinutes: 30,
          sortOrder: 0,
          createdAt: DateTime(2026, 5, 30),
          updatedAt: DateTime(2026, 5, 30),
          version: 1,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardView(
              tasks: tasks,
              ownerKey: 'test_user',
              onTaskTap: (task) => tapped = task,
              onTaskLongPress: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('Test task'));
      await tester.pumpAndSettle();

      expect(tapped, isNotNull);
      expect(tapped!.title, 'Test task');
    });

    testWidgets('shows priority indicators', (tester) async {
      final tasks = [
        TaskItem(
          id: '1',
          ownerKey: 'test_user',
          title: 'Urgent',
          dueDate: '2026-05-31',
          time: '',
          workflowStatus: WorkflowStatus.todo,
          priority: Priority.high,
          tags: const [],
          participants: const [],
          durationMinutes: 30,
          sortOrder: 0,
          createdAt: DateTime(2026, 5, 30),
          updatedAt: DateTime(2026, 5, 30),
          version: 1,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardView(
              tasks: tasks,
              ownerKey: 'test_user',
              onTaskTap: (_) {},
              onTaskLongPress: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Urgent'), findsOneWidget);
    });
  });
}
