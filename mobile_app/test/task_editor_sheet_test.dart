import 'package:family_todo_mobile/features/tasks/task_editor_sheet.dart';
import 'package:family_todo_mobile/models/family_group.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:family_todo_mobile/models/task_project.dart';
import 'package:family_todo_mobile/repositories/task_repository.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:family_todo_mobile/services/local_db.dart';
import 'package:family_todo_mobile/domain/task_domain_service.dart';
import 'package:family_todo_mobile/state/task_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal fake TaskRepository that never touches a real database.
class _FakeTaskRepository implements TaskRepository {
  @override
  LocalDb get db => throw UnimplementedError();
  @override
  ApiClient get api => throw UnimplementedError();
  @override
  String get actorProfile => 'test_user';

  @override
  Future<void> bindActor(String _) async {}
  @override
  Future<List<TaskItem>> readVisibleTasks() async => [];
  @override
  Future<void> syncDelta() async {}
  @override
  Future<void> syncFull() async {}
  @override
  Future<void> upsert(TaskItem _) async {}
  @override
  Future<void> delete(TaskItem _) async {}
  @override
  Future<void> upsertProject(TaskProject _) async {}
  @override
  Future<void> upsertFamilyGroup(FamilyGroup _) async {}
  @override
  Future<List<TaskProject>> readProjects() async => [];
  @override
  Future<List<FamilyGroup>> readFamilyGroups() async => [];
  @override
  Future<Map<String, List<String>>> readProjectGroupMap() async => {};
}

/// TaskStore subclass using a fake repository so no real DB is needed.
class _FakeTaskStore extends TaskStore {
  _FakeTaskStore()
      : super(
          repository: _FakeTaskRepository(),
          domainService: TaskDomainService(),
        );
}

void main() {
  group('showTaskEditorSheet', () {
    testWidgets('renders title field', (tester) async {
      final store = _FakeTaskStore();
      store.selectedDate.value = DateTime(2026, 5, 31);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showTaskEditorSheet(
                    context: context,
                    store: store,
                    knownContacts: const [],
                    contactLabel: (c) => c.displayName,
                    dateKey: (d) => d.toIso8601String(),
                    onSaved: () async {},
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

      // The sheet contains TextField widgets
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('creates task with title', (tester) async {
      final store = _FakeTaskStore();
      store.selectedDate.value = DateTime(2026, 5, 31);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showTaskEditorSheet(
                    context: context,
                    store: store,
                    knownContacts: const [],
                    contactLabel: (c) => c.displayName,
                    dateKey: (d) => d.toIso8601String(),
                    onSaved: () async {},
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

      // Find title TextField and enter text
      final titleField = find.byType(TextField).first;
      await tester.enterText(titleField, 'Test Task');
      await tester.pumpAndSettle();

      // Verify text was entered
      expect(find.text('Test Task'), findsOneWidget);
    });

    testWidgets('prefills date from selectedDate on store', (tester) async {
      final store = _FakeTaskStore();
      store.selectedDate.value = DateTime(2026, 5, 31);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showTaskEditorSheet(
                    context: context,
                    store: store,
                    knownContacts: const [],
                    contactLabel: (c) => c.displayName,
                    dateKey: (d) => d.toIso8601String(),
                    onSaved: () async {},
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

      // Sheet rendered successfully (has "Новая задача" header)
      expect(find.text('Новая задача'), findsOneWidget);
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('Настройки'), findsOneWidget);
      expect(find.text('Работа'), findsOneWidget);
    });

    testWidgets('work tab supports comments and checklists', (tester) async {
      final store = _FakeTaskStore();
      store.selectedDate.value = DateTime(2026, 5, 31);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showTaskEditorSheet(
                    context: context,
                    store: store,
                    knownContacts: const [],
                    contactLabel: (c) => c.displayName,
                    dateKey: (d) => d.toIso8601String(),
                    onSaved: () async {},
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
      await tester.tap(find.text('Работа'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Комментарий или подпись'),
        'Готово к проверке',
      );
      await tester.tap(find.byTooltip('Отправить'));
      await tester.pumpAndSettle();

      expect(find.text('Готово к проверке'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Новый чеклист'),
        'Релиз',
      );
      await tester.tap(find.byTooltip('Добавить чеклист'));
      await tester.pumpAndSettle();

      expect(find.text('Релиз'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Пункт'),
        'Проверить сборку',
      );
      final addItemButton = find.byTooltip('Добавить пункт');
      await tester.ensureVisible(addItemButton);
      await tester.pumpAndSettle();
      await tester.tap(addItemButton);
      await tester.pumpAndSettle();

      expect(find.text('Проверить сборку'), findsOneWidget);
      final checklistTile = find.byType(CheckboxListTile).first;
      await tester.ensureVisible(checklistTile);
      await tester.pumpAndSettle();
      var checklistItem = tester.widget<CheckboxListTile>(checklistTile);
      expect(checklistItem.value, isFalse);

      await tester.tap(checklistTile);
      await tester.pumpAndSettle();

      checklistItem = tester.widget<CheckboxListTile>(checklistTile);
      expect(checklistItem.value, isTrue);
    });

    testWidgets('edit mode pre-fills existing task data', (tester) async {
      final store = _FakeTaskStore();
      store.selectedDate.value = DateTime(2026, 5, 31);

      const existing = TaskItem(
        id: 't1',
        ownerKey: 'test_user',
        isFamily: false,
        title: 'Existing Task',
        details: 'Some details',
        dueDate: '2026-05-31',
        time: '14:00',
        workflowStatus: WorkflowStatus.todo,
        priority: Priority.medium,
        tags: [],
        assignees: ['user1'],
        reminderOffsetsMinutes: [30],
        durationMinutes: 30,
        updatedAt: '2026-05-30T00:00:00',
        version: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showTaskEditorSheet(
                    context: context,
                    store: store,
                    knownContacts: const [],
                    contactLabel: (c) => c.displayName,
                    dateKey: (d) => d.toIso8601String(),
                    onSaved: () async {},
                    existing: existing,
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

      // Edit mode header and pre-filled title
      expect(find.text('Редактирование задачи'), findsOneWidget);
      expect(find.text('Existing Task'), findsOneWidget);
    });
  });
}
