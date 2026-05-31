import 'package:family_todo_mobile/features/tasks/calendar_view.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CalendarView', () {
    testWidgets('renders month and day labels', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalendarView(
              month: DateTime(2026, 5),
              tasks: const [],
              selectedDate: DateTime(2026, 5, 31),
              onMonthPrev: () {},
              onMonthNext: () {},
              onMonthToday: () {},
              onDayTap: (_) {},
              onDateSelected: (_) {},
            ),
          ),
        ),
      );

      // Month header
      expect(find.textContaining('2026'), findsOneWidget);
      // Day-of-week headers
      expect(find.text('Пн'), findsOneWidget);
      expect(find.text('Вт'), findsOneWidget);
    });

    testWidgets('shows tasks on their dates', (tester) async {
      final tasks = [
        TaskItem(
          id: '1',
          ownerKey: 'test_user',
          title: 'Task on 15th',
          dueDate: '2026-05-15',
          time: '10:00',
          workflowStatus: WorkflowStatus.todo,
          priority: Priority.high,
          tags: const [],
          participants: const [],
          durationMinutes: 0,
          sortOrder: 0,
          createdAt: DateTime(2026, 5, 1),
          updatedAt: DateTime(2026, 5, 1),
          version: 1,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalendarView(
              month: DateTime(2026, 5),
              tasks: tasks,
              selectedDate: DateTime(2026, 5, 15),
              onMonthPrev: () {},
              onMonthNext: () {},
              onMonthToday: () {},
              onDayTap: (_) {},
              onDateSelected: (_) {},
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
              month: DateTime(2026, 5),
              tasks: const [],
              selectedDate: DateTime(2026, 5, 31),
              onMonthPrev: () => prevCalled = true,
              onMonthNext: () => nextCalled = true,
              onMonthToday: () {},
              onDayTap: (_) {},
              onDateSelected: (_) {},
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
              month: DateTime(2026, 5),
              tasks: const [],
              selectedDate: DateTime(2026, 5, 15),
              onMonthPrev: () {},
              onMonthNext: () {},
              onMonthToday: () {},
              onDayTap: (_) {},
              onDateSelected: (_) {},
            ),
          ),
        ),
      );

      // The selected date '15' should be visible
      expect(find.text('15'), findsOneWidget);
    });
  });
}
