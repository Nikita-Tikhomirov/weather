import 'package:family_todo_mobile/features/tasks/calendar_view.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CalendarView', () {
    testWidgets('renders month header and today button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalendarView(
              monthDate: DateTime(2026, 5),
              allTasks: const [],
              selectedDate: DateTime(2026, 5, 31),
              labelFor: (String p) => p,
              onMonthPrev: () {},
              onMonthNext: () {},
              onGoToday: () {},
              onDayTap: (DateTime date, List<TaskItem> tasks) {},
              onEdit: (TaskItem t) async {},
              onDelete: (TaskItem t) async {},
              onAddForDate: (DateTime d) async {},
            ),
          ),
        ),
      );

      // Month header contains year
      expect(find.textContaining('2026'), findsOneWidget);
      // Today button
      expect(find.text('Сегодня'), findsOneWidget);
    });

    testWidgets('shows tasks on their dates', (tester) async {
      final tasks = [
        TaskItem(
          id: '1',
          ownerKey: 'test_user',
          isFamily: false,
          title: 'Task on 15th',
          details: '',
          dueDate: '2026-05-15',
          time: '10:00',
          workflowStatus: WorkflowStatus.todo,
          priority: Priority.high,
          tags: const [],
          assignees: const [],
          reminderOffsetsMinutes: const [],
          durationMinutes: 0,
          updatedAt: '2026-05-01T00:00:00',
          version: 1,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalendarView(
              monthDate: DateTime(2026, 5),
              allTasks: tasks,
              selectedDate: DateTime(2026, 5, 15),
              labelFor: (String p) => p,
              onMonthPrev: () {},
              onMonthNext: () {},
              onGoToday: () {},
              onDayTap: (DateTime date, List<TaskItem> tasks) {},
              onEdit: (TaskItem t) async {},
              onDelete: (TaskItem t) async {},
              onAddForDate: (DateTime d) async {},
            ),
          ),
        ),
      );

      expect(find.text('Task on 15th'), findsOneWidget);
    });

    testWidgets('navigation buttons call callbacks', (tester) async {
      var prevCalled = false;
      var nextCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalendarView(
              monthDate: DateTime(2026, 5),
              allTasks: const [],
              selectedDate: DateTime(2026, 5, 31),
              labelFor: (String p) => p,
              onMonthPrev: () => prevCalled = true,
              onMonthNext: () => nextCalled = true,
              onGoToday: () {},
              onDayTap: (DateTime date, List<TaskItem> tasks) {},
              onEdit: (TaskItem t) async {},
              onDelete: (TaskItem t) async {},
              onAddForDate: (DateTime d) async {},
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.chevron_left));
      expect(prevCalled, isTrue);

      await tester.tap(find.byIcon(Icons.chevron_right));
      expect(nextCalled, isTrue);
    });

    testWidgets('highlights selected date', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalendarView(
              monthDate: DateTime(2026, 5),
              allTasks: const [],
              selectedDate: DateTime(2026, 5, 15),
              labelFor: (String p) => p,
              onMonthPrev: () {},
              onMonthNext: () {},
              onGoToday: () {},
              onDayTap: (DateTime date, List<TaskItem> tasks) {},
              onEdit: (TaskItem t) async {},
              onDelete: (TaskItem t) async {},
              onAddForDate: (DateTime d) async {},
            ),
          ),
        ),
      );

      // The selected date '15' should be visible
      expect(find.text('15'), findsOneWidget);
    });
  });
}
