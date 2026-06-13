import 'package:family_todo_mobile/features/tasks/tasks_board.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:family_todo_mobile/models/task_collaboration.dart';
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

      // Should have 4 columns with English fallback labels.
      expect(find.text('To do'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('In review'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('uses localized workflow labels when delegates are available',
        (tester) async {
      const task = TaskItem(
        id: 'done-1',
        ownerKey: 'test_user',
        isFamily: false,
        title: 'Localized Done Task',
        details: '',
        dueDate: '2026-05-31',
        time: '',
        workflowStatus: WorkflowStatus.done,
        priority: Priority.high,
        tags: [],
        assignees: [],
        reminderOffsetsMinutes: [],
        durationMinutes: 0,
        updatedAt: '2026-05-30T00:00:00',
        version: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TasksBoard(
              byStatus: const <String, List<TaskItem>>{
                'done': [task],
              },
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

      expect(find.text('To do'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('In review'), findsOneWidget);
      expect(find.text('Done'), findsAtLeastNWidgets(1));
    });

    testWidgets('displays tasks in correct columns', (tester) async {
      final tasks = [
        const TaskItem(
          id: '1',
          ownerKey: 'test_user',
          isFamily: false,
          title: 'Todo Task',
          details: '',
          dueDate: '2026-05-31',
          time: '',
          workflowStatus: WorkflowStatus.todo,
          priority: Priority.medium,
          tags: [],
          assignees: [],
          reminderOffsetsMinutes: [],
          durationMinutes: 0,
          updatedAt: '2026-05-30T00:00:00',
          version: 1,
        ),
        const TaskItem(
          id: '2',
          ownerKey: 'test_user',
          isFamily: false,
          title: 'Done Task',
          details: '',
          dueDate: '2026-05-31',
          time: '',
          workflowStatus: WorkflowStatus.done,
          priority: Priority.high,
          tags: [],
          assignees: [],
          reminderOffsetsMinutes: [],
          durationMinutes: 0,
          updatedAt: '2026-05-30T00:00:00',
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
      expect(find.byTooltip('Done/Undo'), findsWidgets);
      expect(find.byTooltip('Delete'), findsWidgets);
    });

    testWidgets('shows collaboration indicators on task cards', (tester) async {
      const task = TaskItem(
        id: 'collab-1',
        ownerKey: 'test_user',
        isFamily: true,
        title: 'Collaborative Task',
        details: '',
        dueDate: '2026-05-31',
        time: '',
        workflowStatus: WorkflowStatus.todo,
        priority: Priority.medium,
        tags: [],
        assignees: [],
        reminderOffsetsMinutes: [],
        collaboration: TaskCollaboration(
          comments: [
            TaskComment(
              id: 'comment-1',
              authorProfile: 'test_user',
              text: 'First',
              createdAt: '2026-06-01T10:00:00',
            ),
            TaskComment(
              id: 'comment-2',
              authorProfile: 'test_user',
              text: 'Second',
              createdAt: '2026-06-01T10:05:00',
            ),
          ],
          attachments: [
            TaskAttachment(
              id: 'att-1',
              kind: 'file',
              filename: 'brief.pdf',
              createdAt: '2026-06-01T10:06:00',
            ),
          ],
          checklists: [
            TaskChecklist(
              id: 'checklist-1',
              title: 'Release',
              createdAt: '2026-06-01T10:07:00',
              items: [
                TaskChecklistItem(
                  id: 'item-1',
                  text: 'Smoke',
                  done: true,
                  createdAt: '2026-06-01T10:08:00',
                ),
                TaskChecklistItem(
                  id: 'item-2',
                  text: 'Deploy',
                  createdAt: '2026-06-01T10:09:00',
                ),
              ],
            ),
          ],
        ),
        durationMinutes: 0,
        updatedAt: '2026-05-30T00:00:00',
        version: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TasksBoard(
              byStatus: const <String, List<TaskItem>>{
                'todo': [task],
              },
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

      expect(find.text('Collaborative Task'), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      expect(find.byIcon(Icons.attachment), findsOneWidget);
      expect(find.byIcon(Icons.checklist), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
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

      expect(find.byType(TasksBoard), findsOneWidget);
      expect(find.text('No tasks'), findsWidgets);
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
        final style = KanbanColumnStyle.resolve(ThemeData.light(), status);
        final contrast =
            _contrastRatio(style.titleColor, style.backgroundColor);
        expect(
          contrast,
          greaterThanOrEqualTo(4.5),
          reason: 'Low contrast for $status',
        );
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
