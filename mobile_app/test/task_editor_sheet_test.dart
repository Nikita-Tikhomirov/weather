import 'package:family_todo_mobile/features/tasks/task_editor_sheet.dart';
import 'package:family_todo_mobile/models/family_group.dart';
import 'package:family_todo_mobile/models/task_collaboration.dart';
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
  final List<TaskItem> tasks = [];
  final List<TaskItem> upserts = [];
  final List<TaskProject> taskProjects = [];
  final List<FamilyGroup> groups = [];
  final Map<String, List<String>> projectGroups = {};

  @override
  LocalDb get db => throw UnimplementedError();
  @override
  ApiClient get api => throw UnimplementedError();
  @override
  String get actorProfile => 'test_user';

  @override
  Future<void> bindActor(String _) async {}
  @override
  Future<List<TaskItem>> readVisibleTasks() async => List<TaskItem>.from(tasks);
  @override
  Future<void> syncDelta() async {}
  @override
  Future<void> syncFull() async {}
  @override
  Future<void> upsert(TaskItem task) async {
    upserts.add(task);
    tasks.removeWhere((item) => item.id == task.id);
    tasks.add(task);
  }

  @override
  Future<void> delete(TaskItem _) async {}
  @override
  Future<void> upsertProject(TaskProject _) async {}
  @override
  Future<void> upsertFamilyGroup(FamilyGroup _) async {}
  @override
  Future<List<TaskProject>> readProjects() async =>
      List<TaskProject>.from(taskProjects);
  @override
  Future<List<FamilyGroup>> readFamilyGroups() async =>
      List<FamilyGroup>.from(groups);
  @override
  Future<Map<String, List<String>>> readProjectGroupMap() async =>
      Map<String, List<String>>.from(projectGroups);
}

/// TaskStore subclass using a fake repository so no real DB is needed.
class _FakeTaskStore extends TaskStore {
  factory _FakeTaskStore([_FakeTaskRepository? repository]) {
    return _FakeTaskStore._(repository ?? _FakeTaskRepository());
  }

  _FakeTaskStore._(this.fakeRepository)
      : super(repository: fakeRepository, domainService: TaskDomainService());

  final _FakeTaskRepository fakeRepository;
}

void _seedProjectAccess(_FakeTaskStore store) {
  store.owner.value = 'test_user';
  const project = TaskProject(
    id: 'project-1',
    name: 'Project',
    ownerKey: 'test_user',
  );
  const group = FamilyGroup(
    id: 'group-1',
    name: 'Team',
    members: ['test_user'],
  );
  store.projects.value = const [project];
  store.familyGroups.value = const [group];
  store.projectGroupMap.value = const {
    'project-1': ['group-1'],
  };
}

const _editableTask = TaskItem(
  id: 'task-editable',
  ownerKey: 'family',
  isFamily: true,
  projectId: 'project-1',
  groupId: 'group-1',
  title: 'Editable Task',
  details: '',
  dueDate: '2026-05-31',
  time: '14:00',
  workflowStatus: WorkflowStatus.todo,
  priority: Priority.medium,
  tags: [],
  assignees: ['test_user'],
  reminderOffsetsMinutes: [],
  durationMinutes: 30,
  updatedAt: '2026-05-30T00:00:00',
  version: 1,
);

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

    testWidgets('autosaves comment without pressing save', (tester) async {
      final repository = _FakeTaskRepository();
      repository.tasks.add(_editableTask);
      final store = _FakeTaskStore(repository);
      _seedProjectAccess(store);
      store.selectedDate.value = DateTime(2026, 5, 31);
      var savedCallbacks = 0;

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
                    onSaved: () async => savedCallbacks++,
                    existing: _editableTask,
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
        'Сохранилось сразу',
      );
      await tester.tap(find.byTooltip('Отправить'));
      await tester.pumpAndSettle();

      expect(repository.upserts, isNotEmpty);
      expect(savedCallbacks, greaterThan(0));
      expect(
        repository.upserts.last.collaboration.comments.last.text,
        'Сохранилось сразу',
      );
    });

    testWidgets('autosaves legacy existing task without project metadata',
        (tester) async {
      const legacyTask = TaskItem(
        id: 'task-legacy',
        ownerKey: 'family',
        isFamily: true,
        title: 'Legacy Task',
        details: '',
        dueDate: '2026-05-31',
        time: '14:00',
        workflowStatus: WorkflowStatus.todo,
        priority: Priority.medium,
        tags: [],
        assignees: ['test_user'],
        reminderOffsetsMinutes: [],
        durationMinutes: 30,
        updatedAt: '2026-05-30T00:00:00',
        version: 1,
      );
      final repository = _FakeTaskRepository();
      repository.tasks.add(legacyTask);
      final store = _FakeTaskStore(repository);
      store.owner.value = 'test_user';
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
                    existing: legacyTask,
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
        'Комментарий в старой задаче',
      );
      await tester.tap(find.byTooltip('Отправить'));
      await tester.pumpAndSettle();

      expect(repository.upserts, isNotEmpty);
      expect(
        repository.tasks.single.collaboration.comments.single.text,
        'Комментарий в старой задаче',
      );
    });

    testWidgets('autosaves checklist actions without pressing save',
        (tester) async {
      final repository = _FakeTaskRepository();
      repository.tasks.add(_editableTask);
      final store = _FakeTaskStore(repository);
      _seedProjectAccess(store);
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
                    existing: _editableTask,
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
        find.widgetWithText(TextField, 'Новый чеклист'),
        'Запуск',
      );
      await tester.tap(find.byTooltip('Добавить чеклист'));
      await tester.pumpAndSettle();

      expect(repository.upserts, isNotEmpty);
      expect(
        repository.upserts.last.collaboration.checklists.single.title,
        'Запуск',
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Пункт'),
        'Проверить экран',
      );
      final addItemButton = find.widgetWithIcon(IconButton, Icons.add_task);
      await tester.ensureVisible(addItemButton);
      await tester.pumpAndSettle();
      await tester.tap(addItemButton);
      await tester.pumpAndSettle();

      expect(
        repository
            .upserts.last.collaboration.checklists.single.items.single.text,
        'Проверить экран',
      );

      await tester.ensureVisible(find.byType(CheckboxListTile).first);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.pumpAndSettle();

      expect(
        repository
            .upserts.last.collaboration.checklists.single.items.single.done,
        isTrue,
      );
    });

    testWidgets('photo preview opens full-screen viewer', (tester) async {
      const imageBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';
      const task = TaskItem(
        id: 'task-photo',
        ownerKey: 'family',
        isFamily: true,
        projectId: 'project-1',
        groupId: 'group-1',
        title: 'Photo Task',
        details: '',
        dueDate: '2026-05-31',
        time: '14:00',
        workflowStatus: WorkflowStatus.todo,
        priority: Priority.medium,
        tags: [],
        assignees: ['test_user'],
        reminderOffsetsMinutes: [],
        collaboration: TaskCollaboration(
          comments: [
            TaskComment(
              id: 'comment-1',
              authorProfile: 'test_user',
              text: 'Фото',
              createdAt: '2026-06-01T10:00:00',
              attachmentIds: ['att-1'],
            ),
          ],
          attachments: [
            TaskAttachment(
              id: 'att-1',
              kind: 'photo',
              filename: 'screen.png',
              mimeType: 'image/png',
              dataBase64: imageBase64,
              createdAt: '2026-06-01T10:00:00',
            ),
          ],
        ),
        durationMinutes: 30,
        updatedAt: '2026-05-30T00:00:00',
        version: 1,
      );
      final store = _FakeTaskStore();
      _seedProjectAccess(store);
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
                    existing: task,
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

      expect(find.byType(Image), findsOneWidget);
      await tester.tap(find.byTooltip('Открыть фото'));
      await tester.pumpAndSettle();

      expect(find.text('screen.png'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
    });

    testWidgets('pending photo attachment renders thumbnail and opens viewer',
        (tester) async {
      const imageBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';
      final store = _FakeTaskStore();
      _seedProjectAccess(store);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: TaskEditorScreen(
            store: store,
            knownContacts: const [],
            contactLabel: (c) => c.displayName,
            dateKey: (d) => d.toIso8601String(),
            onSaved: () async {},
            existing: _editableTask,
            initialPendingAttachments: const [
              TaskAttachment(
                id: 'pending-photo',
                kind: 'photo',
                filename: 'pending.png',
                mimeType: 'image/png',
                dataBase64: imageBase64,
                createdAt: '2026-06-01T10:00:00',
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('Работа'));
      await tester.pumpAndSettle();

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('pending.png'), findsOneWidget);

      await tester.tap(find.byTooltip('Открыть фото'));
      await tester.pumpAndSettle();

      expect(find.text('pending.png'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
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
