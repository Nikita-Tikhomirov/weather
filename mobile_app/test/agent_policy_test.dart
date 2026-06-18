import 'package:family_todo_mobile/models/agent_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentAccessPolicy', () {
    test('uses English fallback labels and unavailable reason', () {
      const policy = AgentRunPolicy.unavailable();
      final allowed = AgentRunPolicy.fromJson(const {
        'allowed': true,
        'mode': 'executor',
        'plugins': [
          'task_context',
          'project_chat_context',
          'task_write',
          'workspace_read',
          'workspace_write',
          'browser',
          'deploy',
          'audit',
        ],
        'allowed_commands': ['session_create', 'session_send'],
        'reason': '',
      });

      expect(
        policy.reason,
        'AI is available only to users with workspace access.',
      );
      expect(allowed.pluginLabels, [
        'Task context',
        'Project chat context',
        'Task write',
        'Workspace read',
        'Workspace write',
        'Browser',
        'Deploy',
        'Audit',
      ]);
    });

    test('parses allowed policy with fallback labels', () {
      final policy = AgentRunPolicy.fromJson(const {
        'allowed': true,
        'mode': 'executor',
        'mode_label': 'Исполнитель',
        'plugins': ['task_context', 'task_write', 'workspace_write', 'git'],
        'allowed_commands': ['session_create', 'session_send'],
        'reason': '',
      });

      expect(policy.allowed, isTrue);
      expect(policy.modeLabel, 'Исполнитель');
      expect(policy.pluginLabels, [
        'Task context',
        'Task write',
        'Workspace write',
        'Git',
      ]);
      expect(policy.canStartAgentChat, isTrue);
    });

    test('denied policy explains missing rights', () {
      final policy = AgentRunPolicy.fromJson(const {
        'allowed': false,
        'mode': '',
        'plugins': [],
        'allowed_commands': [],
        'reason': 'Нет прав на запуск агента из задачи.',
      });

      expect(policy.allowed, isFalse);
      expect(policy.canStartAgentChat, isFalse);
      expect(policy.reason, 'Нет прав на запуск агента из задачи.');
    });
  });
}
