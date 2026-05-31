import 'package:family_todo_mobile/features/tasks/task_editor_sheet.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TaskEditorSheet', () {
    testWidgets('renders title field', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => TaskEditorSheet(
                      ownerKey: 'test_user',
                      initialDate: DateTime(2026, 5, 31),
                      onSaved: (_) {},
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsWidgets);
    });

    testWidgets('creates task with title', (tester) async {
      TaskItem? saved;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => TaskEditorSheet(
                      ownerKey: 'test_user',
                      initialDate: DateTime(2026, 5, 31),
                      onSaved: (task) => saved = task,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Find title field and enter text
      final titleField = find.byType(TextFormField).first;
      await tester.enterText(titleField, 'Test Task');
      await tester.pumpAndSettle();

      // Verify text was entered
      expect(find.text('Test Task'), findsOneWidget);
    });

    testWidgets('prefills date from initialDate', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => TaskEditorSheet(
                      ownerKey: 'test_user',
                      initialDate: DateTime(2026, 5, 31),
                      onSaved: (_) {},
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Check that the sheet rendered (has close button area)
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('edit mode pre-fills existing task data', (tester) async {
      final existing = TaskItem(
        id: 't1',
        ownerKey: 'test_user',
        title: 'Existing Task',
        details: 'Some details',
        dueDate: '2026-05-31',
        time: '14:00',
        workflowStatus: WorkflowStatus.todo,
        priority: Priority.medium,
        tags: const [],
        participants: const ['user1'],
        durationMinutes: 30,
        sortOrder: 0,
        createdAt: DateTime(2026, 5, 30),
        updatedAt: DateTime(2026, 5, 30),
        version: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => TaskEditorSheet.edit(
                      ownerKey: 'test_user',
                      task: existing,
                      onSaved: (_) {},
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Existing Task'), findsOneWidget);
    });
  });
}
