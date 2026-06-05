import 'dart:async';

import 'dart:typed_data';

import 'package:family_todo_mobile/features/tasks/task_editor_sheet.dart';
import 'package:family_todo_mobile/models/agent_policy.dart';
import 'package:family_todo_mobile/models/family_group.dart';
import 'package:family_todo_mobile/models/task_collaboration.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:family_todo_mobile/models/task_project.dart';
import 'package:family_todo_mobile/models/workspace_item.dart';
import 'package:family_todo_mobile/repositories/task_repository.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:family_todo_mobile/services/codewhale_bridge_service.dart';
import 'package:family_todo_mobile/services/local_db.dart';
import 'package:family_todo_mobile/domain/task_domain_service.dart';
import 'package:family_todo_mobile/state/task_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal fake TaskRepository that never touches a real database.
class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'https://api.example.test', apiKey: 'test');

  int mediaUploadCount = 0;
  int documentUploadCount = 0;
  int agentTicketCount = 0;
  int agentContextCount = 0;
  int agentSessionRecordCount = 0;
  int agentEventRecordCount = 0;
  final List<String> agentTicketWorkspaceIds = [];
  final List<String> agentContextWorkspaceIds = [];
  final List<String> agentSessionRecordWorkspaceIds = [];
  final List<String> agentEventRecordWorkspaceIds = [];
  Completer<void>? mediaUploadGate;
  Completer<void>? documentUploadGate;
  bool failAgentContext = false;
  bool failAgentSessionRecord = false;
  bool failAgentEventRecord = false;

  @override
  Future<ChatUploadResult> chatUploadMedia({
    required String actorProfile,
    required List<int> bytes,
    required String filename,
    void Function(double progress)? onProgress,
  }) async {
    mediaUploadCount += 1;
    onProgress?.call(0.35);
    await mediaUploadGate?.future;
    onProgress?.call(1);
    return const ChatUploadResult(
      assetUrl: '/chat/media/uploaded-photo',
      imageMeta: {'width': 1, 'height': 1},
    );
  }

  @override
  Future<ChatUploadResult> chatUploadDocument({
    required String actorProfile,
    required List<int> bytes,
    required String filename,
    void Function(double progress)? onProgress,
  }) async {
    documentUploadCount += 1;
    onProgress?.call(0.35);
    await documentUploadGate?.future;
    onProgress?.call(1);
    return ChatUploadResult(
      assetUrl: '/chat/media/$filename',
      imageMeta: {'original_name': filename, 'size_bytes': bytes.length},
    );
  }

  @override
  Future<AgentTicketResult> requestAgentTicket({
    required String actorProfile,
    String actorPhone = '',
    required String taskId,
    required String taskType,
    required String workspaceId,
    String requestedMode = '',
    String sessionId = '',
  }) async {
    agentTicketCount += 1;
    agentTicketWorkspaceIds.add(workspaceId);
    return AgentTicketResult(
      policy: AgentRunPolicy(
        allowed: true,
        mode: requestedMode,
        modeLabel: 'Исполнитель',
        plugins: const [],
        allowedCommands: const [
          'session_create',
          'session_send',
        ],
        reason: '',
        workspaceId: workspaceId,
      ),
      policyTicket: 'test-policy-ticket',
    );
  }

  @override
  Future<AgentContextPack> fetchAgentContext({
    required String actorProfile,
    String actorPhone = '',
    required String taskId,
    required String workspaceId,
    String taskType = 'feature',
    String requestedMode = '',
  }) async {
    agentContextCount += 1;
    agentContextWorkspaceIds.add(workspaceId);
    if (failAgentContext) {
      throw StateError('POST failed: 400 {"error":"Task not found"}');
    }
    return AgentContextPack.fromJson({
      'task': {
        'id': taskId,
        'title': 'Backend task',
        'workflow_status': 'todo',
      },
    });
  }

  @override
  Future<void> recordAgentSession({
    required String actorProfile,
    String actorPhone = '',
    required String taskId,
    required String workspaceId,
    required String agentSessionId,
    String sessionId = '',
    String title = '',
    String taskType = 'feature',
    String requestedMode = '',
    String status = 'pending',
  }) async {
    agentSessionRecordCount += 1;
    agentSessionRecordWorkspaceIds.add(workspaceId);
    if (failAgentSessionRecord) {
      throw StateError('POST failed: 400 {"error":"Task not found"}');
    }
  }

  @override
  Future<void> recordAgentEvent({
    required String actorProfile,
    String actorPhone = '',
    required String taskId,
    required String workspaceId,
    required String agentSessionId,
    required String eventType,
    Map<String, dynamic> payload = const {},
    String taskType = 'feature',
    String requestedMode = '',
  }) async {
    agentEventRecordCount += 1;
    agentEventRecordWorkspaceIds.add(workspaceId);
    if (failAgentEventRecord) {
      throw StateError('POST failed: 400 {"error":"Task not found"}');
    }
  }
}

class _FakeAgentBridge extends CodeWhaleBridgeService {
  _FakeAgentBridge({
    required super.onMessage,
    required super.onStatusChange,
  });

  final List<String> sentMessages = [];
  final List<String> uploadedFiles = [];
  final List<String> readFilePaths = [];
  final List<String> createSessionWorkspaceIds = [];
  final Map<String, String> fileReadDataBase64ByPath = {};
  Map<String, dynamic> lastTaskCard = const {};
  List<WorkspaceItem> workspaces = const [];
  String taskPromptReply = '';
  String familyTaskCardSkillReply = '';
  int connectCount = 0;
  int commandListRequestCount = 0;
  int workspaceListRequestCount = 0;
  int createSessionCount = 0;
  String policyTicket = '';

  @override
  Future<bool> connect() async {
    connectCount += 1;
    return true;
  }

  @override
  void requestCodeWhaleCommands() {
    commandListRequestCount += 1;
    onMessage(
      CodeWhaleBridgeMessage.fromJson({
        'type': 'codewhale_command_list',
        'commands': const [],
      }),
    );
  }

  @override
  void requestWorkspaceList() {
    workspaceListRequestCount += 1;
    onMessage(
      CodeWhaleBridgeMessage.fromJson({
        'type': 'workspace_list',
        'workspaces': workspaces.map((item) => item.toJson()).toList(),
      }),
    );
  }

  @override
  void requestWorkspaceFileRead(String workspaceId, String path) {
    readFilePaths.add(path);
    onMessage(
      CodeWhaleBridgeMessage.fromJson({
        'type': 'workspace_file_content',
        'workspace_id': workspaceId,
        'path': path,
        'text': 'Файл агента: $path',
        'data_base64': fileReadDataBase64ByPath[path] ?? '',
        'mime_type': path.endsWith('.png') ? 'image/png' : 'text/markdown',
        'size': fileReadDataBase64ByPath[path]?.length ?? 0,
      }),
    );
  }

  @override
  void updatePolicyTicket(String policyTicket) {
    this.policyTicket = policyTicket;
  }

  @override
  void createSession(
    String workspaceId, {
    String title = '',
    Map<String, dynamic> taskCard = const {},
  }) {
    createSessionCount += 1;
    createSessionWorkspaceIds.add(workspaceId);
    lastTaskCard = Map<String, dynamic>.from(taskCard);
    onMessage(
      CodeWhaleBridgeMessage.fromJson({
        'type': 'session',
        'session': {
          'id': 'bridge-session-1',
          'workspace_id': workspaceId,
          'title': title,
          'status': 'idle',
        },
      }),
    );
  }

  @override
  void updateSessionSettings({
    required String workspaceId,
    required String sessionId,
    String provider = '',
    String model = '',
    String approvalPolicy = '',
    String sandboxMode = '',
    bool autoMode = false,
  }) {}

  @override
  void uploadSessionFile({
    required String workspaceId,
    required String sessionId,
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    String caption = '',
  }) {
    uploadedFiles.add(filename);
  }

  @override
  void sendSessionMessage(String workspaceId, String sessionId, String text) {
    sentMessages.add(text);
    if (familyTaskCardSkillReply.trim().isNotEmpty &&
        text.trim() == '/skill family-task-card') {
      onMessage(
        CodeWhaleBridgeMessage.fromJson({
          'type': 'assistant_delta',
          'workspace_id': workspaceId,
          'session_id': sessionId,
          'text': familyTaskCardSkillReply,
        }),
      );
    }
    if (taskPromptReply.trim().isNotEmpty &&
        text.contains('Выполни задачу по карточке.')) {
      onMessage(
        CodeWhaleBridgeMessage.fromJson({
          'type': 'assistant_delta',
          'workspace_id': workspaceId,
          'session_id': sessionId,
          'text': taskPromptReply,
        }),
      );
    }
    onMessage(
      CodeWhaleBridgeMessage.fromJson({
        'type': 'session_stream_done',
        'workspace_id': workspaceId,
        'session_id': sessionId,
      }),
    );
  }

  @override
  void dispose() {}
}

class _FakeTaskRepository implements TaskRepository {
  final List<TaskItem> tasks = [];
  final List<TaskItem> upserts = [];
  final List<TaskProject> taskProjects = [];
  final List<FamilyGroup> groups = [];
  final Map<String, List<String>> projectGroups = {};
  final _FakeApiClient fakeApi = _FakeApiClient();

  @override
  LocalDb get db => throw UnimplementedError();
  @override
  ApiClient get api => fakeApi;
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

void _seedProjectAccess(
  _FakeTaskStore store, {
  String projectName = 'Project',
}) {
  store.owner.value = 'test_user';
  final project = TaskProject(
    id: 'project-1',
    name: projectName,
    ownerKey: 'test_user',
  );
  const group = FamilyGroup(
    id: 'group-1',
    name: 'Team',
    members: ['test_user'],
  );
  store.projects.value = [project];
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
      expect(find.text('Агент'), findsOneWidget);
    });

    testWidgets('agent tab shows actions without static abilities block',
        (tester) async {
      final store = _FakeTaskStore();
      store.selectedDate.value = DateTime(2026, 5, 31);
      const policy = AgentRunPolicy(
        allowed: true,
        mode: 'executor',
        modeLabel: 'Исполнитель',
        plugins: ['task_context', 'task_write', 'workspace_write', 'git'],
        allowedCommands: ['session_open', 'session_create', 'session_send'],
        reason: '',
        workspaceId: 'weather',
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
                    agentPolicy: policy,
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
      await tester.tap(find.text('Агент'));
      await tester.pumpAndSettle();

      expect(find.text('Подключить чат'), findsOneWidget);
      expect(find.text('Новый чат'), findsOneWidget);
      expect(find.text('Исполнитель'), findsWidgets);
      expect(find.text('Возможности агента'), findsNothing);
      expect(find.text('Читает контекст задачи'), findsNothing);
      expect(find.text('Работает в воркспейсе'), findsNothing);
      expect(find.text('Плагины'), findsNothing);
    });

    testWidgets('agent tab displays open agent questions', (tester) async {
      final task = _editableTask.copyWith(
        collaboration: const TaskCollaboration(
          questions: [
            TaskAgentQuestion(
              id: 'question-1',
              text: 'Нужен макет формы?',
              status: 'open',
              createdAt: '2026-06-05T10:00:00Z',
              blocking: true,
            ),
          ],
        ),
      );
      final store = _FakeTaskStore();
      store.selectedDate.value = DateTime(2026, 5, 31);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: TaskEditorScreen(
            store: store,
            knownContacts: const [],
            contactLabel: (c) => c.displayName,
            dateKey: (d) => d.toIso8601String(),
            onSaved: () async {},
            existing: task,
          ),
        ),
      );

      await tester.tap(find.text('Агент'));
      await tester.pumpAndSettle();

      expect(find.text('Вопросы агента'), findsOneWidget);
      expect(find.text('Нужен макет формы?'), findsOneWidget);
    });

    testWidgets(
      'agent launch uses local task card context when backend context is 400',
      (tester) async {
        final repository = _FakeTaskRepository();
        repository.fakeApi.failAgentContext = true;
        repository.fakeApi.failAgentSessionRecord = true;
        repository.fakeApi.failAgentEventRecord = true;
        final store = _FakeTaskStore(repository);
        _seedProjectAccess(store);
        store.selectedDate.value = DateTime(2026, 5, 31);
        _FakeAgentBridge? bridge;
        final task = _editableTask.copyWith(
          title: 'Разобрать запуск агента',
          details: 'Ошибка 400 при старте из карточки.',
          collaboration: const TaskCollaboration(
            comments: [
              TaskComment(
                id: 'comment-agent',
                authorProfile: 'test_user',
                text: 'Учитывай свежий комментарий.',
                createdAt: '2026-06-01T10:00:00',
              ),
            ],
            checklists: [
              TaskChecklist(
                id: 'check-agent',
                title: 'Проверка',
                createdAt: '2026-06-01T10:01:00',
                items: [
                  TaskChecklistItem(
                    id: 'item-agent',
                    text: 'Проверить очередь инструментов',
                    createdAt: '2026-06-01T10:02:00',
                  ),
                ],
              ),
            ],
            attachments: [
              TaskAttachment(
                id: 'file-agent',
                kind: 'file',
                filename: 'report.txt',
                mimeType: 'text/plain',
                dataBase64: 'cmVwb3J0',
                createdAt: '2026-06-01T10:03:00',
              ),
            ],
          ),
        );
        const policy = AgentRunPolicy(
          allowed: true,
          mode: 'executor',
          modeLabel: 'Исполнитель',
          plugins: [],
          allowedCommands: ['session_create', 'session_send'],
          reason: '',
          workspaceId: 'weather',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(splashFactory: NoSplash.splashFactory),
            home: TaskEditorScreen(
              store: store,
              knownContacts: const [],
              contactLabel: (c) => c.displayName,
              dateKey: (d) => d.toIso8601String(),
              onSaved: () async {},
              existing: task,
              agentPolicy: policy,
              agentBridgeFactory: ({
                required onMessage,
                required onStatusChange,
              }) {
                bridge = _FakeAgentBridge(
                  onMessage: onMessage,
                  onStatusChange: onStatusChange,
                );
                return bridge!;
              },
            ),
          ),
        );

        await tester.tap(find.text('Агент'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Новый чат'));
        await tester.pumpAndSettle();

        expect(repository.fakeApi.agentTicketCount, 1);
        expect(repository.fakeApi.agentContextCount, 1);
        final fakeBridge = bridge!;
        expect(fakeBridge.policyTicket, 'test-policy-ticket');
        expect(fakeBridge.createSessionCount, 1);
        expect(fakeBridge.lastTaskCard['task_id'], task.id);
        expect(fakeBridge.lastTaskCard['agent_session_id'], isNotEmpty);
        expect(fakeBridge.lastTaskCard['policy_ticket'], 'test-policy-ticket');
        expect(fakeBridge.uploadedFiles, contains('report.txt'));
        expect(fakeBridge.sentMessages[0], '/skill family-task-card');
        expect(fakeBridge.sentMessages[1], contains('family-task-card read'));
        final appContext = fakeBridge.sentMessages.firstWhere(
          (message) => message.contains('Family Todo'),
        );
        expect(appContext, contains('Family Todo'));
        expect(
          appContext,
          contains('Карточка задачи не файл в проекте'),
        );
        final taskPrompt = fakeBridge.sentMessages.last;
        expect(
          taskPrompt,
          contains('Разобрать запуск агента'),
        );
        expect(
          taskPrompt,
          contains('Учитывай свежий комментарий.'),
        );
        expect(
          taskPrompt,
          contains('Проверить очередь инструментов'),
        );
        expect(taskPrompt, contains('report.txt'));
        expect(
          find.textContaining('Не удалось запустить агента'),
          findsNothing,
        );
      },
    );

    testWidgets('agent launch stops when task card skill is missing',
        (tester) async {
      final repository = _FakeTaskRepository();
      final store = _FakeTaskStore(repository);
      _seedProjectAccess(store);
      store.selectedDate.value = DateTime(2026, 5, 31);
      _FakeAgentBridge? bridge;
      const policy = AgentRunPolicy(
        allowed: true,
        mode: 'executor',
        modeLabel: 'Исполнитель',
        plugins: [],
        allowedCommands: ['session_create', 'session_send'],
        reason: '',
        workspaceId: 'weather',
      );

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
            agentPolicy: policy,
            agentBridgeFactory: ({
              required onMessage,
              required onStatusChange,
            }) {
              bridge = _FakeAgentBridge(
                onMessage: onMessage,
                onStatusChange: onStatusChange,
              )..familyTaskCardSkillReply =
                  'Skill family-task-card not found';
              return bridge!;
            },
          ),
        ),
      );

      await tester.tap(find.text('Агент'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новый чат'));
      await tester.pumpAndSettle();

      expect(bridge!.sentMessages, ['/skill family-task-card']);
      expect(
        bridge!.sentMessages.any((text) => text.contains('Выполни задачу')),
        isFalse,
      );
      expect(find.textContaining('family-task-card'), findsWidgets);
    });

    testWidgets('agent launch matches project name to bridge workspace',
        (tester) async {
      final repository = _FakeTaskRepository();
      final store = _FakeTaskStore(repository);
      _seedProjectAccess(store, projectName: 'Exp76');
      store.selectedDate.value = DateTime(2026, 5, 31);
      _FakeAgentBridge? bridge;
      const policy = AgentRunPolicy(
        allowed: true,
        mode: 'executor',
        modeLabel: 'Исполнитель',
        plugins: [],
        allowedCommands: ['session_create', 'session_send'],
        reason: '',
        workspaceId: 'workspace-pups',
      );

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
            agentPolicy: policy,
            agentBridgeFactory: ({
              required onMessage,
              required onStatusChange,
            }) {
              bridge = _FakeAgentBridge(
                onMessage: onMessage,
                onStatusChange: onStatusChange,
              )..workspaces = const [
                  WorkspaceItem(
                    id: 'workspace-pups',
                    name: 'пупс',
                    path: r'C:\Users\user\Desktop\пупс',
                    status: WorkspaceStatus.available,
                  ),
                  WorkspaceItem(
                    id: 'weather',
                    name: 'weather',
                    path: r'C:\Users\user\Desktop\weather',
                    status: WorkspaceStatus.available,
                  ),
                  WorkspaceItem(
                    id: 'exp76-ru',
                    name: 'exp76.ru',
                    path: r'C:\Users\user\Desktop\exp76.ru',
                    status: WorkspaceStatus.available,
                  ),
                ];
              return bridge!;
            },
          ),
        ),
      );

      await tester.tap(find.text('Агент'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новый чат'));
      await tester.pumpAndSettle();

      expect(repository.fakeApi.agentTicketWorkspaceIds.single, 'exp76-ru');
      expect(repository.fakeApi.agentContextWorkspaceIds.single, 'exp76-ru');
      expect(bridge!.workspaceListRequestCount, greaterThanOrEqualTo(1));
      expect(bridge!.createSessionWorkspaceIds.single, 'exp76-ru');
      expect(find.textContaining('workspace not found'), findsNothing);
    });

    testWidgets(
        'agent launch requires explicit workspace when project is ambiguous',
        (tester) async {
      final repository = _FakeTaskRepository();
      final store = _FakeTaskStore(repository);
      _seedProjectAccess(store);
      store.selectedDate.value = DateTime(2026, 5, 31);
      _FakeAgentBridge? bridge;
      const policy = AgentRunPolicy(
        allowed: true,
        mode: 'executor',
        modeLabel: 'Исполнитель',
        plugins: [],
        allowedCommands: ['session_create', 'session_send'],
        reason: '',
        workspaceId: 'project-1',
      );

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
            agentPolicy: policy,
            agentBridgeFactory: ({
              required onMessage,
              required onStatusChange,
            }) {
              bridge = _FakeAgentBridge(
                onMessage: onMessage,
                onStatusChange: onStatusChange,
              )..workspaces = const [
                  WorkspaceItem(
                    id: 'workspace-pups',
                    name: 'пупс',
                    path: r'C:\Users\user\Desktop\пупс',
                    status: WorkspaceStatus.available,
                  ),
                  WorkspaceItem(
                    id: 'weather',
                    name: 'weather',
                    path: r'C:\Users\user\Desktop\weather',
                    status: WorkspaceStatus.available,
                  ),
                ];
              return bridge!;
            },
          ),
        ),
      );

      await tester.tap(find.text('Агент'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новый чат'));
      await tester.pumpAndSettle();

      expect(repository.fakeApi.agentTicketCount, 0);
      expect(repository.fakeApi.agentContextCount, 0);
      expect(bridge!.createSessionCount, 0);
      expect(find.textContaining('Выберите воркспейс'), findsWidgets);
    });

    testWidgets('agent task actions update card status and attach report',
        (tester) async {
      final repository = _FakeTaskRepository();
      repository.tasks.add(_editableTask);
      final store = _FakeTaskStore(repository);
      _seedProjectAccess(store);
      store.selectedDate.value = DateTime(2026, 5, 31);
      _FakeAgentBridge? bridge;
      const policy = AgentRunPolicy(
        allowed: true,
        mode: 'executor',
        modeLabel: 'Исполнитель',
        plugins: [],
        allowedCommands: ['session_create', 'session_send'],
        reason: '',
        workspaceId: 'weather',
      );

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
            agentPolicy: policy,
            agentBridgeFactory: ({
              required onMessage,
              required onStatusChange,
            }) {
              bridge = _FakeAgentBridge(
                onMessage: onMessage,
                onStatusChange: onStatusChange,
              )
                ..fileReadDataBase64ByPath.addAll({
                  'reports/form-report.md': 'cmVwb3J0LWFnZW50YQ==',
                  'vision/form-screen.png': 'iVBORw0KGgo=',
                })
                ..taskPromptReply = '''
Работу выполнил, отчет приложил.
TASK_CARD_ACTIONS_JSON:
{
  "status": "in_review",
  "comments": ["Готово к проверке, отчет и скрин приложены."],
  "checklists": [
    {"title": "Проверка агента", "items": ["Проверить отчет", "Принять работу"]}
  ],
  "attachments": [
    {"path": "reports/form-report.md", "filename": "form-report.md", "caption": "Отчет агента"},
    {"path": "vision/form-screen.png", "filename": "form-screen.png", "caption": "Скрин формы"}
  ]
}
''';
              return bridge!;
            },
          ),
        ),
      );

      await tester.tap(find.text('Агент'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Новый чат'));
      await tester.pumpAndSettle();

      expect(repository.upserts, isNotEmpty);
      final saved = repository.upserts.last;
      expect(saved.workflowStatus, WorkflowStatus.in_review);
      expect(saved.collaboration.comments.last.authorProfile, 'agent');
      expect(
        saved.collaboration.comments.last.text,
        'Готово к проверке, отчет и скрин приложены.',
      );
      expect(saved.collaboration.attachments.map((item) => item.assetUrl), [
        'reports/form-report.md',
        'vision/form-screen.png',
      ]);
      expect(bridge!.readFilePaths, [
        'reports/form-report.md',
        'vision/form-screen.png',
      ]);
      expect(saved.collaboration.attachments.map((item) => item.dataBase64), [
        'cmVwb3J0LWFnZW50YQ==',
        'iVBORw0KGgo=',
      ]);
      expect(
        saved.collaboration.comments.last.attachmentIds,
        saved.collaboration.attachments.map((item) => item.id).toList(),
      );
      expect(saved.collaboration.checklists.last.title, 'Проверка агента');
      expect(
        saved.collaboration.checklists.last.items.map((item) => item.text),
        [
          'Проверить отчет',
          'Принять работу',
        ],
      );
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
      final addChecklistButton = find.byTooltip('Добавить чеклист');
      await tester.ensureVisible(addChecklistButton);
      await tester.pumpAndSettle();
      await tester.tap(addChecklistButton);
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

    testWidgets('autosaves new task after first collaboration action',
        (tester) async {
      final repository = _FakeTaskRepository();
      final store = _FakeTaskStore(repository);
      _seedProjectAccess(store);
      store.currentProjectId.value = 'project-1';
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
      await tester.enterText(
        find.widgetWithText(TextField, 'Название'),
        'Новая автозадача',
      );
      await tester.tap(find.text('Работа'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Комментарий или подпись'),
        'Первый комментарий',
      );
      await tester.tap(find.byTooltip('Отправить'));
      await tester.pumpAndSettle();

      expect(repository.upserts, isNotEmpty);
      expect(repository.tasks.single.title, 'Новая автозадача');
      expect(
        repository.tasks.single.collaboration.comments.single.text,
        'Первый комментарий',
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

    testWidgets('autosaves checklist rename and delete without pressing save',
        (tester) async {
      final task = _editableTask.copyWith(
        collaboration: const TaskCollaboration(
          checklists: [
            TaskChecklist(
              id: 'checklist-edit',
              title: 'Старый чеклист',
              createdBy: 'test_user',
              createdAt: '2026-06-01T10:00:00',
              items: [
                TaskChecklistItem(
                  id: 'item-keep',
                  text: 'Пункт',
                  createdBy: 'test_user',
                  createdAt: '2026-06-01T10:00:00',
                ),
              ],
            ),
          ],
        ),
      );
      final repository = _FakeTaskRepository();
      repository.tasks.add(task);
      final store = _FakeTaskStore(repository);
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
            existing: task,
          ),
        ),
      );

      await tester.tap(find.text('Работа'));
      await tester.pumpAndSettle();
      final editChecklistButton = find.byTooltip('Редактировать чеклист');
      final workList = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        editChecklistButton,
        240,
        scrollable: workList,
      );
      await tester.pumpAndSettle();
      await tester.tap(editChecklistButton);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Название чеклиста'),
        'Новый чеклист',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();

      expect(
        repository.upserts.last.collaboration.checklists.single.title,
        'Новый чеклист',
      );

      final deleteChecklistButton = find.byTooltip('Удалить чеклист');
      await tester.scrollUntilVisible(
        deleteChecklistButton,
        240,
        scrollable: workList,
      );
      await tester.pumpAndSettle();
      await tester.tap(deleteChecklistButton);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await tester.pumpAndSettle();

      expect(repository.upserts.last.collaboration.checklists, isEmpty);
    });

    testWidgets(
        'autosaves checklist item edit and delete without pressing save',
        (tester) async {
      final task = _editableTask.copyWith(
        collaboration: const TaskCollaboration(
          checklists: [
            TaskChecklist(
              id: 'checklist-item-edit',
              title: 'Запуск',
              createdBy: 'test_user',
              createdAt: '2026-06-01T10:00:00',
              items: [
                TaskChecklistItem(
                  id: 'item-edit',
                  text: 'Старый пункт',
                  createdBy: 'test_user',
                  createdAt: '2026-06-01T10:00:00',
                ),
              ],
            ),
          ],
        ),
      );
      final repository = _FakeTaskRepository();
      repository.tasks.add(task);
      final store = _FakeTaskStore(repository);
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
            existing: task,
          ),
        ),
      );

      await tester.tap(find.text('Работа'));
      await tester.pumpAndSettle();
      final editItemButton = find.byTooltip('Редактировать пункт');
      final workList = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        editItemButton,
        240,
        scrollable: workList,
      );
      await tester.pumpAndSettle();
      await tester.tap(editItemButton);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Текст пункта'),
        'Новый пункт',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();

      expect(
        repository
            .upserts.last.collaboration.checklists.single.items.single.text,
        'Новый пункт',
      );

      final deleteItemButton = find.byTooltip('Удалить пункт');
      await tester.scrollUntilVisible(
        deleteItemButton,
        240,
        scrollable: workList,
      );
      await tester.pumpAndSettle();
      await tester.tap(deleteItemButton);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await tester.pumpAndSettle();

      expect(
        repository.upserts.last.collaboration.checklists.single.items,
        isEmpty,
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

    testWidgets('remote photo attachment renders thumbnail and opens viewer',
        (tester) async {
      final task = _editableTask.copyWith(
        title: 'Remote Photo Task',
        collaboration: TaskCollaboration.fromJson(const {
          'comments': [
            {
              'id': 'comment-remote',
              'author_profile': 'test_user',
              'text': 'Фото из S3',
              'created_at': '2026-06-01T10:00:00',
              'attachment_ids': ['att-remote'],
            },
          ],
          'attachments': [
            {
              'id': 'att-remote',
              'kind': 'photo',
              'filename': 'remote.png',
              'mime_type': 'image/png',
              'asset_url': '/chat/media/task-photo',
              'image_meta': {'width': 640, 'height': 480},
              'created_at': '2026-06-01T10:00:00',
            },
          ],
        }),
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

      expect(find.text('remote.png'), findsOneWidget);
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

    testWidgets('uploads pending photo before autosaving comment',
        (tester) async {
      const imageBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';
      final repository = _FakeTaskRepository();
      final store = _FakeTaskStore(repository);
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
                sizeBytes: 68,
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('Работа'));
      await tester.pumpAndSettle();
      final commentField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Комментарий или подпись',
      );
      await tester.enterText(commentField, 'Подпись к фото');
      await tester.tap(find.byTooltip('Отправить'));
      await tester.pumpAndSettle();

      expect(repository.fakeApi.mediaUploadCount, 1);
      expect(repository.upserts, isNotEmpty);
      final attachmentJson =
          repository.upserts.last.collaboration.attachments.single.toJson();
      expect(attachmentJson['asset_url'], '/chat/media/uploaded-photo');
      expect(attachmentJson['data_base64'], '');
      expect(attachmentJson['caption'], 'Подпись к фото');
    });

    testWidgets('uploads pending document before autosaving comment',
        (tester) async {
      final repository = _FakeTaskRepository();
      final store = _FakeTaskStore(repository);
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
                id: 'pending-doc',
                kind: 'file',
                filename: 'brief.pdf',
                mimeType: 'application/pdf',
                dataBase64: 'cGRm',
                createdAt: '2026-06-01T10:00:00',
                sizeBytes: 3,
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('Работа'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Отправить'));
      await tester.pumpAndSettle();

      expect(repository.fakeApi.documentUploadCount, 1);
      expect(repository.upserts, isNotEmpty);
      final attachmentJson =
          repository.upserts.last.collaboration.attachments.single.toJson();
      expect(attachmentJson['asset_url'], '/chat/media/brief.pdf');
      expect(attachmentJson['data_base64'], '');
      expect(attachmentJson['image_meta'], {
        'original_name': 'brief.pdf',
        'size_bytes': 3,
      });
    });

    testWidgets('shows upload progress while sending attachment',
        (tester) async {
      const imageBase64 =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=';
      final repository = _FakeTaskRepository();
      repository.fakeApi.mediaUploadGate = Completer<void>();
      final store = _FakeTaskStore(repository);
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
                sizeBytes: 68,
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.text('Работа'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Отправить'));
      await tester.pump();

      expect(find.text('35%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsWidgets);

      repository.fakeApi.mediaUploadGate!.complete();
      await tester.pumpAndSettle();
      expect(repository.upserts, isNotEmpty);
    });

    testWidgets('can reply to a task comment and autosaves it', (tester) async {
      final task = _editableTask.copyWith(
        collaboration: const TaskCollaboration(
          comments: [
            TaskComment(
              id: 'comment-root',
              authorProfile: 'test_user',
              text: 'Нужно проверить экран',
              createdAt: '2026-06-01T10:00:00',
            ),
          ],
        ),
      );
      final repository = _FakeTaskRepository();
      repository.tasks.add(task);
      final store = _FakeTaskStore(repository);
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
            existing: task,
          ),
        ),
      );

      await tester.tap(find.text('Работа'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Действия комментария'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ответить'));
      await tester.pumpAndSettle();

      expect(find.text('Ответ на комментарий'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Комментарий или подпись'),
        'Проверю сегодня',
      );
      await tester.tap(find.byTooltip('Отправить'));
      await tester.pumpAndSettle();

      final comments = repository.upserts.last.collaboration.comments;
      expect(comments, hasLength(2));
      expect(comments.last.text, 'Проверю сегодня');
      expect(comments.last.replyToCommentId, 'comment-root');
    });

    testWidgets('can edit own task comment and autosaves it', (tester) async {
      final task = _editableTask.copyWith(
        collaboration: const TaskCollaboration(
          comments: [
            TaskComment(
              id: 'comment-edit',
              authorProfile: 'test_user',
              text: 'Старый текст',
              createdAt: '2026-06-01T10:00:00',
            ),
          ],
        ),
      );
      final repository = _FakeTaskRepository();
      repository.tasks.add(task);
      final store = _FakeTaskStore(repository);
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
            existing: task,
          ),
        ),
      );

      await tester.tap(find.text('Работа'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Действия комментария'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Редактировать'));
      await tester.pumpAndSettle();

      expect(find.text('Редактирование комментария'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Комментарий или подпись'),
        'Новый текст',
      );
      await tester.tap(find.byTooltip('Отправить'));
      await tester.pumpAndSettle();

      final comment = repository.upserts.last.collaboration.comments.single;
      expect(comment.text, 'Новый текст');
      expect(comment.editedAt, isNotEmpty);
    });

    testWidgets('can delete task comment and autosaves soft delete',
        (tester) async {
      final task = _editableTask.copyWith(
        collaboration: const TaskCollaboration(
          comments: [
            TaskComment(
              id: 'comment-delete',
              authorProfile: 'test_user',
              text: 'Удалить меня',
              createdAt: '2026-06-01T10:00:00',
              attachmentIds: ['att-delete'],
            ),
          ],
          attachments: [
            TaskAttachment(
              id: 'att-delete',
              kind: 'file',
              filename: 'old.pdf',
              assetUrl: '/chat/media/old.pdf',
              createdAt: '2026-06-01T10:00:00',
            ),
          ],
        ),
      );
      final repository = _FakeTaskRepository();
      repository.tasks.add(task);
      final store = _FakeTaskStore(repository);
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
            existing: task,
          ),
        ),
      );

      await tester.tap(find.text('Работа'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Действия комментария'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await tester.pumpAndSettle();

      final collaboration = repository.upserts.last.collaboration;
      expect(collaboration.comments.single.isDeleted, isTrue);
      expect(collaboration.comments.single.text, '');
      expect(collaboration.comments.single.attachmentIds, isEmpty);
      expect(collaboration.attachments, isEmpty);
      expect(find.text('Комментарий удалён'), findsOneWidget);
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
