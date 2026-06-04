import 'package:family_todo_mobile/models/agent_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AgentAccessPolicy', () {
    test('parses allowed policy with Russian labels', () {
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
        'Контекст задачи',
        'Запись в задачу',
        'Запись в воркспейс',
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
