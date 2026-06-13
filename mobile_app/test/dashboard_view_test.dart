import 'package:family_todo_mobile/features/tasks/dashboard_view.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:family_todo_mobile/state/task_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardView', () {
    testWidgets('renders with empty tasks', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardView(
              vm: const DashboardVm(
                todayKey: '2026-05-31',
                todayTotal: 0,
                doneToday: 0,
                familyToday: 0,
                overdue: 0,
                upcoming: [],
              ),
              labelFor: (_) => 'User',
              onOpenCalendar: () async {},
            ),
          ),
        ),
      );

      // Dashboard renders
      expect(find.byType(DashboardView), findsOneWidget);
    });

    testWidgets('displays task metrics', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardView(
              vm: const DashboardVm(
                todayKey: '2026-05-31',
                todayTotal: 5,
                doneToday: 3,
                familyToday: 2,
                overdue: 1,
                upcoming: [],
              ),
              labelFor: (_) => 'User',
              onOpenCalendar: () async {},
            ),
          ),
        ),
      );

      // Metrics are displayed
      expect(find.text('5'), findsWidgets);
      expect(find.text('3'), findsWidgets);
    });

    testWidgets('shows overdue count', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardView(
              vm: const DashboardVm(
                todayKey: '2026-05-31',
                todayTotal: 0,
                doneToday: 0,
                familyToday: 0,
                overdue: 7,
                upcoming: [],
              ),
              labelFor: (_) => 'User',
              onOpenCalendar: () async {},
            ),
          ),
        ),
      );

      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('shows upcoming tasks', (tester) async {
      final upcoming = [
        const TaskItem(
          id: '1',
          ownerKey: 'test_user',
          isFamily: false,
          title: 'Buy groceries',
          details: '',
          dueDate: '2026-06-01',
          time: '18:00',
          workflowStatus: WorkflowStatus.todo,
          priority: Priority.high,
          tags: [],
          assignees: [],
          reminderOffsetsMinutes: [],
          durationMinutes: 60,
          updatedAt: '2026-05-31T12:00:00',
          version: 1,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardView(
              vm: DashboardVm(
                todayKey: '2026-05-31',
                todayTotal: 0,
                doneToday: 0,
                familyToday: 0,
                overdue: 0,
                upcoming: upcoming,
              ),
              labelFor: (_) => 'User',
              onOpenCalendar: () async {},
            ),
          ),
        ),
      );

      expect(find.text('Buy groceries'), findsOneWidget);
    });

    testWidgets('uses English fallback labels without delegates',
        (tester) async {
      final upcoming = [
        const TaskItem(
          id: '1',
          ownerKey: 'test_user',
          isFamily: false,
          title: 'Buy groceries',
          details: '',
          dueDate: '2026-06-01',
          time: '18:00',
          workflowStatus: WorkflowStatus.todo,
          priority: Priority.high,
          tags: [],
          assignees: [],
          reminderOffsetsMinutes: [],
          durationMinutes: 60,
          updatedAt: '2026-05-31T12:00:00',
          version: 1,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardView(
              vm: DashboardVm(
                todayKey: '2026-05-31',
                todayTotal: 5,
                doneToday: 3,
                familyToday: 2,
                overdue: 1,
                upcoming: upcoming,
              ),
              labelFor: (_) => 'User',
              onOpenCalendar: () async {},
            ),
          ),
        ),
      );

      expect(find.text('On date'), findsOneWidget);
      expect(find.text('Done'), findsAtLeastNWidgets(1));
      expect(find.text('Family'), findsAtLeastNWidgets(1));
      expect(find.text('Overdue'), findsAtLeastNWidgets(1));
      expect(find.text('Select date'), findsOneWidget);
      expect(find.text('Upcoming tasks'), findsOneWidget);
      expect(find.textContaining('To do'), findsOneWidget);
    });

    testWidgets('uses localized labels when delegates are available',
        (tester) async {
      final upcoming = [
        const TaskItem(
          id: '1',
          ownerKey: 'test_user',
          isFamily: false,
          title: 'Buy groceries',
          details: '',
          dueDate: '2026-06-01',
          time: '18:00',
          workflowStatus: WorkflowStatus.todo,
          priority: Priority.high,
          tags: [],
          assignees: [],
          reminderOffsetsMinutes: [],
          durationMinutes: 60,
          updatedAt: '2026-05-31T12:00:00',
          version: 1,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DashboardView(
              vm: DashboardVm(
                todayKey: '2026-05-31',
                todayTotal: 5,
                doneToday: 3,
                familyToday: 2,
                overdue: 1,
                upcoming: upcoming,
              ),
              labelFor: (_) => 'User',
              onOpenCalendar: () async {},
            ),
          ),
        ),
      );

      expect(find.text('On date'), findsOneWidget);
      expect(find.text('Done'), findsAtLeastNWidgets(1));
      expect(find.text('Family'), findsAtLeastNWidgets(1));
      expect(find.text('Overdue'), findsAtLeastNWidgets(1));
      expect(find.text('Select date'), findsOneWidget);
      expect(find.text('Upcoming tasks'), findsOneWidget);
      expect(find.textContaining('To do'), findsOneWidget);
    });
  });
}
