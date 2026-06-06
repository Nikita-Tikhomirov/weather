import 'dart:typed_data';

import 'package:family_todo_mobile/domain/task_domain_service.dart';
import 'package:family_todo_mobile/models/agent_policy.dart';
import 'package:family_todo_mobile/models/family_group.dart';
import 'package:family_todo_mobile/models/task_collaboration.dart';
import 'package:family_todo_mobile/models/task_item.dart';
import 'package:family_todo_mobile/models/task_project.dart';
import 'package:family_todo_mobile/repositories/task_repository.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:family_todo_mobile/services/codewhale_bridge_service.dart';
import 'package:family_todo_mobile/services/local_db.dart';
import 'package:family_todo_mobile/services/task_agent_automation_service.dart';
import 'package:family_todo_mobile/state/task_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'https://api.example.test', apiKey: 'test');

  int ticketCount = 0;
  int contextCount = 0;
  int eventCount = 0;
  final List<Map<String, dynamic>> contextResponses = [];

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
    ticketCount += 1;
    return AgentTicketResult(
      policy: AgentRunPolicy(
        allowed: true,
        mode: requestedMode,
        modeLabel: 'Исполнитель',
        plugins: const [],
        allowedCommands: const ['session_send', 'session_update_task_card'],
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
    contextCount += 1;
    if (contextResponses.isNotEmpty) {
      return AgentContextPack.fromJson(contextResponses.removeAt(0));
    }
    return AgentContextPack.fromJson({
      'task': {
        'id': taskId,
        'title': 'Формы',
        'workflow_status': 'in_progress',
      },
    });
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
    eventCount += 1;
  }
}

class _FakeTaskRepository implements TaskRepository {
  final List<TaskItem> tasks = [];
  final List<TaskItem> upserts = [];
  final _FakeApiClient fakeApi = _FakeApiClient();

  @override
  LocalDb get db => throw UnimplementedError();
  @override
  ApiClient get api => fakeApi;
  @override
  String get actorProfile => 'test_user';

  @override
  Future<void> bindActor(String actorProfile) async {}

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
  Future<void> delete(TaskItem task) async {}

  @override
  Future<void> upsertProject(TaskProject project) async {}

  @override
  Future<void> upsertFamilyGroup(FamilyGroup group) async {}

  @override
  Future<List<TaskProject>> readProjects() async => const [];

  @override
  Future<List<FamilyGroup>> readFamilyGroups() async => const [];

  @override
  Future<Map<String, List<String>>> readProjectGroupMap() async => const {};
}

class _FakeAgentBridge extends CodeWhaleBridgeService {
  _FakeAgentBridge({
    required super.onMessage,
    required super.onStatusChange,
  });

  final List<String> sentMessages = [];
  final List<String> uploadedFiles = [];
  final List<Map<String, dynamic>> settingsUpdates = [];
  int updateTaskCardCount = 0;
  String policyTicket = '';
  String taskPromptReply = 'Готово. Исправил форму и добавил отчет.';

  @override
  Future<bool> connect() async => true;

  @override
  void updatePolicyTicket(String policyTicket) {
    this.policyTicket = policyTicket;
  }

  @override
  void requestCodeWhaleCommands() {
    onMessage(
      CodeWhaleBridgeMessage.fromJson({
        'type': 'codewhale_command_list',
        'commands': const [],
      }),
    );
  }

  @override
  void updateSessionTaskCard({
    required String workspaceId,
    required String sessionId,
    Map<String, dynamic> taskCard = const {},
  }) {
    updateTaskCardCount += 1;
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
  }) {
    settingsUpdates.add({
      'provider': provider,
      'model': model,
      'approval_policy': approvalPolicy,
      'sandbox_mode': sandboxMode,
      'auto_mode': autoMode,
    });
  }

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
    if (text.contains('Продолжи работу')) {
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

TaskItem _taskWithWaitingAgent() {
  return const TaskItem(
    id: 'task-agent-auto-1',
    ownerKey: 'test_user',
    isFamily: true,
    projectId: 'weather',
    title: 'Формы',
    details: 'Поправить формы на сайте.',
    dueDate: '2026-06-07',
    time: '12:00',
    workflowStatus: WorkflowStatus.in_progress,
    priority: Priority.medium,
    tags: [],
    assignees: ['test_user'],
    reminderOffsetsMinutes: [],
    durationMinutes: 0,
    updatedAt: '2026-06-07T12:00:00',
    version: 1,
    collaboration: TaskCollaboration(
      agentSettings: TaskAgentSettings(
        workspaceId: 'weather',
        provider: 'openrouter',
        model: 'deepseek/deepseek-chat',
        approvalPolicy: 'never',
        sandboxMode: 'danger-full-access',
        autoMode: true,
        commandValues: ['/skill family-task-card'],
      ),
      comments: [
        TaskComment(
          id: 'comment-review',
          authorProfile: 'test_user',
          text: 'После проверки поправь валидацию email.',
          createdAt: '2026-06-07T11:00:00',
        ),
      ],
      agentSessions: [
        TaskAgentSession(
          id: 'agent-session-1',
          workspaceId: 'weather',
          sessionId: 'bridge-session-1',
          title: 'Агент: Формы',
          mode: 'executor',
          status: 'waiting_review',
          createdBy: 'test_user',
          createdAt: '2026-06-07T10:00:00',
          provider: 'openrouter',
          model: 'deepseek/deepseek-chat',
          approvalPolicy: 'never',
          sandboxMode: 'danger-full-access',
          autoMode: true,
          commandValues: ['/skill family-task-card'],
        ),
      ],
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'continues latest live agent chat and moves successful run to review automatically',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repository = _FakeTaskRepository();
    final task = _taskWithWaitingAgent();
    repository.tasks.add(task);
    repository.fakeApi.contextResponses.addAll([
      {
        'task': {
          'id': task.id,
          'title': task.title,
          'workflow_status': 'in_progress',
        },
      },
      {
        'task': {
          'id': task.id,
          'title': task.title,
          'workflow_status': 'in_progress',
        },
      },
    ]);
    final store = TaskStore(
      repository: repository,
      domainService: TaskDomainService(),
    );
    await store.initialize(initialOwner: 'test_user');
    _FakeAgentBridge? bridge;
    final service = TaskAgentAutomationService(
      store: store,
      actorPhone: () => '+70000000000',
      bridgeFactory: ({required onMessage, required onStatusChange}) {
        bridge = _FakeAgentBridge(
          onMessage: onMessage,
          onStatusChange: onStatusChange,
        );
        return bridge!;
      },
    );

    final started = await service.continueLatestForInProgressTask(
      task: task,
      policy: const AgentRunPolicy(
        allowed: true,
        mode: 'executor',
        modeLabel: 'Исполнитель',
        plugins: [],
        allowedCommands: ['session_send', 'session_update_task_card'],
        reason: '',
        workspaceId: 'weather',
      ),
    );

    expect(started, isTrue);
    expect(repository.fakeApi.ticketCount, 1);
    expect(bridge!.updateTaskCardCount, 1);
    expect(bridge!.policyTicket, 'test-policy-ticket');
    expect(bridge!.settingsUpdates.single['auto_mode'], isTrue);
    expect(
      bridge!.sentMessages.last,
      contains('После проверки поправь валидацию email'),
    );

    final saved = repository.upserts.last;
    expect(saved.workflowStatus, WorkflowStatus.in_review);
    expect(saved.collaboration.comments.last.text, contains('Исправил форму'));
    expect(saved.collaboration.agentSessions.single.status, 'waiting_review');
  });
}
