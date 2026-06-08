import 'package:flutter/foundation.dart';

import '../domain/task_draft.dart';
import 'agent_policy.dart';
import 'chat_models.dart';
import 'task_item.dart';
import 'task_project.dart';

@immutable
class ProjectChatBinding {
  const ProjectChatBinding({
    required this.projectId,
    required this.conversationKey,
    this.groupId = '',
    this.source = '',
    this.isPrimary = false,
    this.title = '',
    this.members = const [],
    this.createdAt = '',
    this.updatedAt = '',
  });

  final String projectId;
  final String conversationKey;
  final String groupId;
  final String source;
  final bool isPrimary;
  final String title;
  final List<String> members;
  final String createdAt;
  final String updatedAt;

  factory ProjectChatBinding.fromJson(Map<String, dynamic> json) {
    return ProjectChatBinding(
      projectId: (json['project_id'] ?? json['projectId'] ?? '').toString(),
      conversationKey:
          (json['conversation_key'] ?? json['conversationKey'] ?? '')
              .toString(),
      groupId: (json['group_id'] ?? json['groupId'] ?? '').toString(),
      source: (json['source'] ?? '').toString(),
      isPrimary: json['is_primary'] == true || json['isPrimary'] == true,
      title: (json['title'] ?? json['name'] ?? '').toString(),
      members: _stringList(json['members']),
      createdAt: (json['created_at'] ?? json['createdAt'] ?? '').toString(),
      updatedAt: (json['updated_at'] ?? json['updatedAt'] ?? '').toString(),
    );
  }

  String get displayTitle {
    final value = title.trim();
    if (value.isNotEmpty) return value;
    if (groupId.trim().isNotEmpty) return groupId;
    return conversationKey;
  }
}

@immutable
class ProjectAutomationConfig {
  const ProjectAutomationConfig({
    required this.projectId,
    this.primaryWorkspaceId = '',
    this.agentEnabled = false,
    this.defaultAgentMode = 'planner',
    this.chatAnalysisMessageLimit = 40,
  });

  final String projectId;
  final String primaryWorkspaceId;
  final bool agentEnabled;
  final String defaultAgentMode;
  final int chatAnalysisMessageLimit;

  factory ProjectAutomationConfig.fromJson(Map<String, dynamic> json) {
    final rawLimit =
        json['chat_analysis_message_limit'] ?? json['chatAnalysisMessageLimit'];
    final limit = int.tryParse((rawLimit ?? 40).toString()) ?? 40;
    return ProjectAutomationConfig(
      projectId: (json['project_id'] ?? json['projectId'] ?? '').toString(),
      primaryWorkspaceId:
          (json['primary_workspace_id'] ?? json['primaryWorkspaceId'] ?? '')
              .toString(),
      agentEnabled:
          json['agent_enabled'] == true || json['agentEnabled'] == true,
      defaultAgentMode:
          (json['default_agent_mode'] ?? json['defaultAgentMode'] ?? 'planner')
              .toString(),
      chatAnalysisMessageLimit: limit.clamp(1, 100).toInt(),
    );
  }
}

@immutable
class ProjectControlSnapshot {
  const ProjectControlSnapshot({
    required this.project,
    required this.chatBindings,
    required this.automation,
    this.primaryWorkspaceId = '',
    this.canManageProject = false,
    this.canUseAgent = false,
    this.canUseWorkspace = false,
  });

  final TaskProject project;
  final List<ProjectChatBinding> chatBindings;
  final ProjectAutomationConfig automation;
  final String primaryWorkspaceId;
  final bool canManageProject;
  final bool canUseAgent;
  final bool canUseWorkspace;

  factory ProjectControlSnapshot.fromJson(Map<String, dynamic> json) {
    final source = json['snapshot'] is Map
        ? Map<String, dynamic>.from(json['snapshot'] as Map)
        : json;
    final rawProject = source['project'];
    final project = rawProject is Map
        ? TaskProject.fromJson(Map<String, dynamic>.from(rawProject))
        : const TaskProject(id: '', name: '');
    final automation = ProjectAutomationConfig.fromJson(
      _mapFrom(source['automation']),
    );
    final rawWorkspace = _mapFrom(source['primary_workspace']);
    final permissions = _mapFrom(source['permissions']);
    return ProjectControlSnapshot(
      project: project,
      chatBindings: _mapList(source['chat_bindings'] ?? source['chatBindings'])
          .map(ProjectChatBinding.fromJson)
          .toList(),
      automation: automation,
      primaryWorkspaceId:
          (rawWorkspace['id'] ?? automation.primaryWorkspaceId).toString(),
      canManageProject: permissions['can_manage_project'] == true ||
          permissions['canManageProject'] == true,
      canUseAgent: permissions['can_use_agent'] == true ||
          permissions['canUseAgent'] == true,
      canUseWorkspace: permissions['can_use_workspace'] == true ||
          permissions['canUseWorkspace'] == true,
    );
  }

  ProjectChatBinding? bindingForConversation(String conversationKey) {
    final key = conversationKey.trim();
    if (key.isEmpty) return null;
    for (final binding in chatBindings) {
      if (binding.conversationKey == key) {
        return binding;
      }
    }
    return null;
  }
}

@immutable
class ProjectChatContextPack {
  const ProjectChatContextPack({
    required this.project,
    required this.binding,
    required this.automation,
    required this.messages,
    required this.policy,
    this.workspaceId = '',
  });

  final TaskProject project;
  final ProjectChatBinding binding;
  final ProjectAutomationConfig automation;
  final List<ChatMessage> messages;
  final AgentRunPolicy policy;
  final String workspaceId;

  factory ProjectChatContextPack.fromJson(Map<String, dynamic> json) {
    final source = json['context'] is Map
        ? Map<String, dynamic>.from(json['context'] as Map)
        : json;
    return ProjectChatContextPack(
      project: TaskProject.fromJson(_mapFrom(source['project'])),
      binding: ProjectChatBinding.fromJson(_mapFrom(source['binding'])),
      automation: ProjectAutomationConfig.fromJson(
        _mapFrom(source['automation']),
      ),
      messages: _mapList(source['messages']).map(ChatMessage.fromJson).toList(),
      policy: AgentRunPolicy.fromJson(_mapFrom(source['policy'])),
      workspaceId: (_mapFrom(source['workspace'])['id'] ?? '').toString(),
    );
  }

  String toPrompt() {
    final lines = <String>[
      'Проанализируй последние сообщения проектного чата и верни только JSON черновика задачи.',
      'Проект: ${project.name}',
      'Чат: ${binding.displayTitle}',
      'Формат JSON: title, details, checklist, decisions, action_items, blockers, assignees, source_message_ids.',
      'Сообщения:',
    ];
    for (final message in messages) {
      final text = message.text.trim();
      if (text.isEmpty) continue;
      lines.add('- ${message.id} ${message.senderProfile}: $text');
    }
    return lines.join('\n');
  }
}

@immutable
class ChatTaskDraft {
  const ChatTaskDraft({
    required this.title,
    this.details = '',
    this.summary = '',
    this.decisions = const [],
    this.actionItems = const [],
    this.blockers = const [],
    this.checklist = const [],
    this.assignees = const [],
    this.sourceMessageIds = const [],
    this.priority = Priority.medium,
  });

  final String title;
  final String details;
  final String summary;
  final List<String> decisions;
  final List<String> actionItems;
  final List<String> blockers;
  final List<String> checklist;
  final List<String> assignees;
  final List<String> sourceMessageIds;
  final Priority priority;

  factory ChatTaskDraft.fromJson(Map<String, dynamic> json) {
    final source = json['draft'] is Map
        ? Map<String, dynamic>.from(json['draft'] as Map)
        : json;
    final title = (source['title'] ?? source['task_title'] ?? '').toString();
    return ChatTaskDraft(
      title: title.trim().isEmpty ? 'Задача из чата' : title.trim(),
      details: (source['details'] ?? source['description'] ?? '').toString(),
      summary: (source['summary'] ?? '').toString(),
      decisions: _stringList(source['decisions']),
      actionItems: _stringList(source['action_items'] ?? source['actionItems']),
      blockers: _stringList(source['blockers']),
      checklist: _stringList(source['checklist']),
      assignees: _stringList(source['assignees']),
      sourceMessageIds: _stringList(
        source['source_message_ids'] ?? source['sourceMessageIds'],
      ),
      priority: Priority.parse((source['priority'] ?? '').toString()),
    );
  }

  TaskDraft toTaskDraft({
    required String projectId,
    String groupId = '',
  }) {
    return TaskDraft(
      title: title,
      details: composedDetails,
      dueDate: '',
      time: '',
      priority: priority,
      workflowStatus: WorkflowStatus.todo,
      isFamily: true,
      assignees: assignees,
      durationMinutes: 0,
      reminderOffsetsMinutes: const [],
      projectId: projectId,
      groupId: groupId,
    );
  }

  String get composedDetails {
    final lines = <String>[];
    final rawDetails = details.trim();
    if (rawDetails.isNotEmpty) lines.add(rawDetails);
    if (summary.trim().isNotEmpty) lines.add('Резюме: ${summary.trim()}');
    _appendList(lines, 'Решения', decisions);
    _appendList(lines, 'Action items', actionItems);
    _appendList(lines, 'Блокеры', blockers);
    _appendList(lines, 'Чеклист', checklist);
    if (sourceMessageIds.isNotEmpty) {
      lines.add('Источники: ${sourceMessageIds.join(', ')}');
    }
    return lines.join('\n\n');
  }

  static void _appendList(
    List<String> lines,
    String title,
    List<String> values,
  ) {
    final clean = values.where((value) => value.trim().isNotEmpty).toList();
    if (clean.isEmpty) return;
    lines.add('$title:\n${clean.map((value) => '- $value').join('\n')}');
  }
}

List<String> _stringList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

Map<String, dynamic> _mapFrom(Object? raw) {
  if (raw is Map) {
    return Map<String, dynamic>.from(raw);
  }
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _mapList(Object? raw) {
  if (raw is! List) return const [];
  return raw.whereType<Map>().map(Map<String, dynamic>.from).toList();
}
