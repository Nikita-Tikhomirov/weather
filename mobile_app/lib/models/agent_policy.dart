import 'package:flutter/foundation.dart';

const Map<String, String> _pluginLabels = {
  'task_context': 'Task context',
  'project_chat_context': 'Project chat context',
  'task_write': 'Task write',
  'workspace_read': 'Workspace read',
  'workspace_write': 'Workspace write',
  'git': 'Git',
  'github': 'GitHub',
  'browser': 'Browser',
  'deploy': 'Deploy',
  'audit': 'Audit',
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
    this.scope = 'task',
    this.projectId = '',
    this.conversationKey = '',
    this.sessionId = '',
  });

  const AgentRunPolicy.unavailable()
      : allowed = false,
        mode = '',
        modeLabel = '',
        plugins = const [],
        allowedCommands = const [],
        reason = 'AI is available only to users with workspace access.',
        workspaceId = '',
        taskId = '',
        scope = 'task',
        projectId = '',
        conversationKey = '',
        sessionId = '';

  final bool allowed;
  final String mode;
  final String modeLabel;
  final List<String> plugins;
  final List<String> allowedCommands;
  final String reason;
  final String workspaceId;
  final String taskId;
  final String scope;
  final String projectId;
  final String conversationKey;
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
      scope: (json['scope'] ?? 'task').toString(),
      projectId: (json['project_id'] ?? json['projectId'] ?? '').toString(),
      conversationKey:
          (json['conversation_key'] ?? json['conversationKey'] ?? '')
              .toString(),
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
      'scope': scope,
      'project_id': projectId,
      'conversation_key': conversationKey,
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
          scope == other.scope &&
          projectId == other.projectId &&
          conversationKey == other.conversationKey &&
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
        scope,
        projectId,
        conversationKey,
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

@immutable
class UserAccessPolicy {
  const UserAccessPolicy({
    required this.phone,
    required this.profileKey,
    required this.roles,
    required this.capabilities,
    required this.workspaces,
    required this.isSuperadmin,
  });

  const UserAccessPolicy.messengerOnly()
      : phone = '',
        profileKey = '',
        roles = const ['messenger_user'],
        capabilities = const ['messenger.use'],
        workspaces = const [],
        isSuperadmin = false;

  final String phone;
  final String profileKey;
  final List<String> roles;
  final List<String> capabilities;
  final List<Map<String, dynamic>> workspaces;
  final bool isSuperadmin;

  factory UserAccessPolicy.fromJson(Map<String, dynamic> json) {
    return UserAccessPolicy(
      phone: (json['phone'] ?? '').toString(),
      profileKey: (json['profile_key'] ?? json['profileKey'] ?? '').toString(),
      roles: _stringList(json['roles']),
      capabilities: _stringList(json['capabilities']),
      workspaces: (json['workspaces'] as List<dynamic>?)
              ?.whereType<Map>()
              .map(Map<String, dynamic>.from)
              .toList() ??
          const [],
      isSuperadmin:
          json['is_superadmin'] == true || json['isSuperadmin'] == true,
    );
  }

  bool hasCapability(String capability) {
    return capabilities.contains(capability);
  }

  bool get canUseMessenger => hasCapability('messenger.use');
  bool get canUseTaskManager {
    return isSuperadmin ||
        hasCapability('tasks.view') ||
        hasCapability('projects.view');
  }

  bool get canUseWorkspaces {
    return isSuperadmin || hasCapability('workspaces.use');
  }

  bool get canUseAi {
    return isSuperadmin || hasCapability('ai.use');
  }

  bool get canManageWorkspaceAccess {
    return isSuperadmin || hasCapability('workspaces.grant_access');
  }
}

@immutable
class AgentTicketResult {
  const AgentTicketResult({
    required this.policy,
    required this.policyTicket,
  });

  final AgentRunPolicy policy;
  final String policyTicket;

  factory AgentTicketResult.fromJson(Map<String, dynamic> json) {
    final rawPolicy = json['policy'];
    return AgentTicketResult(
      policy: rawPolicy is Map
          ? AgentRunPolicy.fromJson(Map<String, dynamic>.from(rawPolicy))
          : const AgentRunPolicy.unavailable(),
      policyTicket:
          (json['policy_ticket'] ?? json['policyTicket'] ?? '').toString(),
    );
  }
}

@immutable
class AgentContextPack {
  const AgentContextPack({
    required this.task,
    required this.comments,
    required this.checklists,
    required this.attachments,
    required this.questions,
    required this.activity,
    required this.agentSessions,
  });

  final Map<String, dynamic> task;
  final List<Map<String, dynamic>> comments;
  final List<Map<String, dynamic>> checklists;
  final List<Map<String, dynamic>> attachments;
  final List<Map<String, dynamic>> questions;
  final List<Map<String, dynamic>> activity;
  final List<Map<String, dynamic>> agentSessions;

  factory AgentContextPack.fromJson(Map<String, dynamic> json) {
    return AgentContextPack(
      task: _mapFrom(json['task']),
      comments: _mapList(json['comments']),
      checklists: _mapList(json['checklists']),
      attachments: _mapList(json['attachments']),
      questions: _mapList(json['questions']),
      activity: _mapList(json['activity']),
      agentSessions: _mapList(
        json['agent_sessions'] ?? json['agentSessions'],
      ),
    );
  }

  String get taskTitle => (task['title'] ?? '').toString();

  String toPrompt() {
    final lines = <String>[
      'Контекст задачи для агентского чата.',
      'Задача: ${taskTitle.isEmpty ? (task['id'] ?? '').toString() : taskTitle}',
      'Статус: ${(task['workflow_status'] ?? '').toString()}',
    ];
    final details = (task['details'] ?? '').toString().trim();
    if (details.isNotEmpty) {
      lines.add('Описание: $details');
    }
    if (comments.isNotEmpty) {
      lines.add('Комментарии:');
      for (final comment in comments.take(12)) {
        final text = (comment['text'] ?? '').toString().trim();
        if (text.isNotEmpty) {
          final author = (comment['author_profile'] ?? '').toString().trim();
          lines.add('- ${author.isEmpty ? 'Пользователь' : author}: $text');
        }
      }
    }
    if (checklists.isNotEmpty) {
      lines.add('Чеклисты:');
      for (final checklist in checklists) {
        final title = (checklist['title'] ?? '').toString().trim();
        lines.add('- ${title.isEmpty ? 'Без названия' : title}');
        final rawItems = checklist['items'];
        final items = rawItems is List
            ? rawItems.whereType<Map>().toList()
            : const <Map>[];
        for (final item in items.take(20)) {
          final text = (item['text'] ?? '').toString().trim();
          if (text.isEmpty) {
            continue;
          }
          final done = item['done'] == true || item['done'] == 1;
          lines.add('  - [${done ? 'x' : ' '}] $text');
        }
      }
    }
    final taskAttachments = _mapList(task['attachments']).isNotEmpty
        ? _mapList(task['attachments'])
        : _mapList(
            task['collaboration'] is Map
                ? (task['collaboration'] as Map)['attachments']
                : null,
          );
    final allAttachments =
        attachments.isNotEmpty ? attachments : taskAttachments;
    if (allAttachments.isNotEmpty) {
      lines.add('Вложения:');
      for (final attachment in allAttachments.take(20)) {
        final filename = (attachment['filename'] ?? '').toString().trim();
        final assetUrl = (attachment['asset_url'] ?? '').toString().trim();
        final caption = (attachment['caption'] ?? '').toString().trim();
        lines.add(
          '- ${filename.isEmpty ? 'Файл' : filename}'
          '${assetUrl.isEmpty ? '' : ' ($assetUrl)'}'
          '${caption.isEmpty ? '' : ': $caption'}',
        );
      }
    }
    if (agentSessions.isNotEmpty) {
      lines.add('Уже подключенные агентские чаты: ${agentSessions.length}');
    }
    lines.add(
      'Работай строго в рамках задачи и своих прав. Итоги пиши кратко, чтобы их можно было сохранить комментарием.',
    );
    return lines.join('\n');
  }
}

@immutable
class WorkspaceAccessGrant {
  const WorkspaceAccessGrant({
    required this.workspaceId,
    required this.profileKey,
    required this.role,
    this.grantedBy = '',
    this.createdAt = '',
    this.updatedAt = '',
    this.revokedAt = '',
  });

  final String workspaceId;
  final String profileKey;
  final String role;
  final String grantedBy;
  final String createdAt;
  final String updatedAt;
  final String revokedAt;

  bool get isActive => revokedAt.trim().isEmpty;

  factory WorkspaceAccessGrant.fromJson(Map<String, dynamic> json) {
    return WorkspaceAccessGrant(
      workspaceId:
          (json['workspace_id'] ?? json['workspaceId'] ?? '').toString(),
      profileKey: (json['profile_key'] ?? json['profileKey'] ?? '').toString(),
      role: (json['role'] ?? 'workspace_user').toString(),
      grantedBy: (json['granted_by'] ?? json['grantedBy'] ?? '').toString(),
      createdAt: (json['created_at'] ?? json['createdAt'] ?? '').toString(),
      updatedAt: (json['updated_at'] ?? json['updatedAt'] ?? '').toString(),
      revokedAt: (json['revoked_at'] ?? json['revokedAt'] ?? '').toString(),
    );
  }
}

Map<String, dynamic> _mapFrom(Object? raw) {
  return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
}

List<Map<String, dynamic>> _mapList(Object? raw) {
  return (raw as List<dynamic>?)
          ?.whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList() ??
      const [];
}
