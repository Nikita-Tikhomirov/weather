import 'package:family_todo_mobile/services/codewhale_bridge_service.dart';
import 'package:family_todo_mobile/services/project_chat_agent_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('polls queued project chat task until completed', () async {
    late _FakeProjectChatBridge bridge;
    final runner = ProjectChatAgentBridgeRunner(
      bridgeFactory: ({
        required void Function(CodeWhaleBridgeMessage message) onMessage,
        required void Function(bool connected, String status) onStatusChange,
      }) {
        bridge = _FakeProjectChatBridge(
          onMessage: onMessage,
          onStatusChange: onStatusChange,
        );
        return bridge;
      },
      taskPollDelay: Duration.zero,
      timeout: const Duration(seconds: 2),
    );

    final result = await runner.run(
      workspaceId: 'workspace-1',
      title: 'Тудушкер: проект',
      taskCard: const {
        'scope': 'project_chat',
        'project_id': 'project-1',
        'conversation_key': 'grp:project:project-1',
      },
      policyTicket: 'ticket-1',
      prompt: 'Верни JSON',
    );

    expect(result, contains('"reply"'));
    expect(bridge.commands, [
      'policy',
      'connect',
      'create_session',
      'start_session',
      'send_message',
      'poll_task',
    ]);
  });
}

class _FakeProjectChatBridge extends CodeWhaleBridgeService {
  _FakeProjectChatBridge({
    required super.onMessage,
    required super.onStatusChange,
  });

  final List<String> commands = <String>[];

  @override
  Future<bool> connect() async {
    commands.add('connect');
    return true;
  }

  @override
  void updatePolicyTicket(String policyTicket) {
    commands.add('policy');
  }

  @override
  void createSession(
    String workspaceId, {
    String title = '',
    Map<String, dynamic> taskCard = const {},
  }) {
    commands.add('create_session');
    onMessage(
      CodeWhaleBridgeMessage.fromJson({
        'type': 'session',
        'session': {
          'id': 'session-1',
          'workspace_id': workspaceId,
          'title': title,
          'status': 'linked',
          'created_at': '2026-06-09T10:00:00Z',
          'updated_at': '2026-06-09T10:00:00Z',
        },
      }),
    );
  }

  @override
  void startSession(String workspaceId, String sessionId) {
    commands.add('start_session');
  }

  @override
  void sendSessionMessage(String workspaceId, String sessionId, String text) {
    commands.add('send_message');
    onMessage(
      CodeWhaleBridgeMessage.fromJson({
        'type': 'session_task',
        'workspace_id': workspaceId,
        'session_id': sessionId,
        'task_id': 'task-1',
        'status': 'queued',
      }),
    );
  }

  @override
  void pollSessionTask(String workspaceId, String sessionId, String taskId) {
    commands.add('poll_task');
    onMessage(
      CodeWhaleBridgeMessage.fromJson({
        'type': 'session_task',
        'workspace_id': workspaceId,
        'session_id': sessionId,
        'task_id': taskId,
        'status': 'completed',
        'task': {
          'result_summary': '{"action":"reply","reply_text":"Готово"}',
        },
      }),
    );
  }
}
