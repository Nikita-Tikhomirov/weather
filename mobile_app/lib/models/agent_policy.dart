import 'package:flutter/foundation.dart';

const Map<String, String> _pluginLabels = {
  'task_context': 'Контекст задачи',
  'task_write': 'Запись в задачу',
  'workspace_read': 'Чтение воркспейса',
  'workspace_write': 'Запись в воркспейс',
  'git': 'Git',
  'github': 'GitHub',
  'browser': 'Браузер',
  'deploy': 'Деплой',
  'audit': 'Аудит',
};

@immutable
class AgentRunPolicy {
  const AgentRunPolicy({
    required this.allowed,
    required this.mode,
    required this.modeLabel,
    required this.plugins,
    required this.allowedCommands,
    required this.reason,
    this.workspaceId = '',
    this.taskId = '',
    this.sessionId = '',
  });

  const AgentRunPolicy.unavailable()
      : allowed = false,
        mode = '',
        modeLabel = '',
        plugins = const [],
        allowedCommands = const [],
        reason = 'AI доступен только пользователям с правами на воркспейс.',
        workspaceId = '',
        taskId = '',
        sessionId = '';

  final bool allowed;
  final String mode;
  final String modeLabel;
  final List<String> plugins;
  final List<String> allowedCommands;
  final String reason;
  final String workspaceId;
  final String taskId;
  final String sessionId;

  factory AgentRunPolicy.fromJson(Map<String, dynamic> json) {
    return AgentRunPolicy(
      allowed: json['allowed'] == true || json['allowed'] == 1,
      mode: (json['mode'] ?? '').toString(),
      modeLabel: (json['mode_label'] ?? json['modeLabel'] ?? '').toString(),
      plugins: _stringList(json['plugins']),
      allowedCommands: _stringList(
        json['allowed_commands'] ?? json['allowedCommands'],
      ),
      reason: (json['reason'] ?? '').toString(),
      workspaceId:
          (json['workspace_id'] ?? json['workspaceId'] ?? '').toString(),
      taskId: (json['task_id'] ?? json['taskId'] ?? '').toString(),
      sessionId: (json['session_id'] ?? json['sessionId'] ?? '').toString(),
    );
  }

  bool get canStartAgentChat {
    return allowed &&
        allowedCommands.contains('session_create') &&
        allowedCommands.contains('session_send');
  }

  bool get canLinkExistingChat {
    return allowed && allowedCommands.contains('session_open');
  }

  List<String> get pluginLabels {
    return plugins
        .map((plugin) => _pluginLabels[plugin] ?? plugin)
        .where((label) => label.trim().isNotEmpty)
        .toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'allowed': allowed,
      'mode': mode,
      'mode_label': modeLabel,
      'plugins': plugins,
      'allowed_commands': allowedCommands,
      'reason': reason,
      'workspace_id': workspaceId,
      'task_id': taskId,
      'session_id': sessionId,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentRunPolicy &&
          runtimeType == other.runtimeType &&
          allowed == other.allowed &&
          mode == other.mode &&
          modeLabel == other.modeLabel &&
          listEquals(plugins, other.plugins) &&
          listEquals(allowedCommands, other.allowedCommands) &&
          reason == other.reason &&
          workspaceId == other.workspaceId &&
          taskId == other.taskId &&
          sessionId == other.sessionId;

  @override
  int get hashCode => Object.hash(
        allowed,
        mode,
        modeLabel,
        Object.hashAll(plugins),
        Object.hashAll(allowedCommands),
        reason,
        workspaceId,
        taskId,
        sessionId,
      );
}

List<String> _stringList(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  return raw
      .map((item) => item.toString())
      .where((item) => item.trim().isNotEmpty)
      .toList();
}
