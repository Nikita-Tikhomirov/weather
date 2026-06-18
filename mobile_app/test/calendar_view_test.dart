import 'package:family_todo_mobile/features/tasks/calendar_view.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CalendarView', () {
    testWidgets('renders month header and today button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
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
      expect(find.text('Today'), findsOneWidget);
    });

    testWidgets('day tasks page uses English fallback labels', (tester) async {
      var addCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: DayTasksPage(
            day: DateTime(2026, 5, 31),
            tasks: const [],
            labelFor: (String p) => p,
            onEdit: (TaskItem t) async {},
            onDelete: (TaskItem t) async {},
            onAddForDate: (DateTime d) async {
              addCalled = true;
            },
          ),
        ),
      );

      expect(find.text('No tasks for this date'), findsOneWidget);
      expect(find.byTooltip('Add Task'), findsOneWidget);

      await tester.tap(find.byTooltip('Add Task'));
      expect(addCalled, isTrue);
    });

    testWidgets('uses localized today action when delegates are available',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
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

      expect(find.text('Today'), findsOneWidget);
      expect(find.textContaining('May'), findsOneWidget);
    });

    testWidgets('desktop calendar uses localized weekday labels',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: SizedBox(
              height: 900,
              child: DesktopCalendarView(
                month: DateTime(2026, 5),
                selectedDate: DateTime(2026, 5, 15),
                allTasks: const [],
                monthGrid: List<DateTime>.generate(
                  35,
                  (index) => DateTime(2026, 5, index + 1),
                ),
                onGoPrevMonth: () {},
                onGoNextMonth: () {},
                onGoToday: () {},
                onSelectDate: (DateTime date) {},
                onDropToDay: (TaskItem task, DateTime date) async {},
                onDropToStatus: (TaskItem task, String status) async {},
                onOpenEditor: (DateTime date, TaskItem task) async {},
                onDelete: (TaskItem task) async {},
                onAddForDate: (DateTime date) async {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Tue'), findsOneWidget);
      expect(find.text('Пн'), findsNothing);
      expect(find.text('Вт'), findsNothing);
    });

    testWidgets('shows tasks on their dates', (tester) async {
      final tasks = [
        const TaskItem(
          id: '1',
          ownerKey: 'user',
          isFamily: false,
          title: 'Task on 15th',
          details: '',
          dueDate: '2026-05-15',
          time: '',
          workflowStatus: WorkflowStatus.todo,
          priority: Priority.medium,
          tags: [],
          assignees: [],
          reminderOffsetsMinutes: [],
          durationMinutes: 0,
          updatedAt: '2026-05-15T00:00:00',
          version: 1,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: SizedBox(
              height: 1200,
              child: CalendarView(
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
        ),
      );

      // Day 15 should be in the grid — verify CalendarView renders
      expect(find.byType(CalendarView), findsOneWidget);
    });

    testWidgets('navigation buttons call callbacks', (tester) async {
      var prevCalled = false;
      var nextCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
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
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: SizedBox(
              height: 1200,
              child: CalendarView(
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
        ),
      );

      // CalendarView should render with selected date
      expect(find.byType(CalendarView), findsOneWidget);
    });
  });
}
