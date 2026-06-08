import 'dart:convert';

import '../models/project_control_models.dart';

enum ProjectChatAgentAction {
  reply,
  taskDraft,
  startAgent,
  status,
  clarify,
}

class ProjectChatAgentDirective {
  const ProjectChatAgentDirective({
    required this.action,
    this.replyText = '',
    this.draft,
    this.launchPrompt = '',
    this.rawText = '',
  });

  final ProjectChatAgentAction action;
  final String replyText;
  final ChatTaskDraft? draft;
  final String launchPrompt;
  final String rawText;
}

class ProjectChatAgentService {
  const ProjectChatAgentService._();

  static const wakeWord = 'Тудушкер';

  static final RegExp _wakeWordPattern = RegExp(
    r'(^|[^\p{L}\p{N}_])тудушкер([^\p{L}\p{N}_]|$)',
    caseSensitive: false,
    unicode: true,
  );

  static bool isAddressed(String text) {
    return _wakeWordPattern.hasMatch(text);
  }

  static String buildIntentPrompt({
    required ProjectChatContextPack context,
    required String userMessage,
    ProjectChatAgentAction? forcedAction,
  }) {
    final lines = <String>[
      'Ты Тудушкер, AI-помощник проектного группового чата.',
      'Тебя вызвали wake word "$wakeWord". Не подбирай действие по хардкоду фраз: сам определи намерение по смыслу сообщения и контекста.',
      'Верни только валидный JSON без markdown.',
      'Разрешенные значения "action": "reply", "task_draft", "start_agent", "status", "clarify".',
      'Контракт JSON:',
      '{"action":"reply|task_draft|start_agent|status|clarify","reply_text":"","draft":{"title":"","details":"","summary":"","decisions":[],"action_items":[],"blockers":[],"checklist":[],"assignees":[],"source_message_ids":[],"priority":"low|medium|high"},"launch_prompt":""}',
      'Если нужен черновик задачи, не используй последнее сообщение как заголовок: выведи короткий логичный title по смыслу обсуждения.',
      'Карточку не создавай сам; только подготовь draft для подтверждения человеком.',
      'Проект: ${context.project.name}',
      if (context.project.description.trim().isNotEmpty)
        'Описание проекта: ${context.project.description.trim()}',
      'Чат: ${context.binding.displayTitle}',
      'Workspace: ${context.workspaceId.trim().isNotEmpty ? context.workspaceId : context.automation.primaryWorkspaceId}',
      if (forcedAction != null)
        'Пользователь нажал действие: ${_wireAction(forcedAction)}. Верни action "${_wireAction(forcedAction)}", если контекст позволяет.',
      'Сообщение пользователя: $userMessage',
      'Последние сообщения чата:',
    ];
    for (final message in context.messages) {
      final text = message.text.trim();
      if (text.isEmpty || message.isDeleted) {
        continue;
      }
      lines.add('${message.id} ${message.senderProfile}: $text');
    }
    return lines.join('\n');
  }

  static ProjectChatAgentDirective parseModelDirective(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const ProjectChatAgentDirective(
        action: ProjectChatAgentAction.reply,
      );
    }

    final jsonText = _extractJsonObject(trimmed);
    if (jsonText.isEmpty) {
      return ProjectChatAgentDirective(
        action: ProjectChatAgentAction.reply,
        replyText: trimmed,
        rawText: text,
      );
    }

    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) {
        return ProjectChatAgentDirective(
          action: ProjectChatAgentAction.reply,
          replyText: trimmed,
          rawText: text,
        );
      }
      final json = Map<String, dynamic>.from(decoded);
      final action = _parseAction((json['action'] ?? '').toString());
      final draftSource = json['draft'] is Map
          ? Map<String, dynamic>.from(json['draft'] as Map)
          : json;
      final draft = action == ProjectChatAgentAction.taskDraft
          ? ChatTaskDraft.fromJson(draftSource)
          : null;
      final replyText = _firstText(json, const [
        'reply_text',
        'replyText',
        'message',
        'answer',
        'question',
      ]);
      return ProjectChatAgentDirective(
        action: action,
        replyText: replyText,
        draft: draft,
        launchPrompt: _firstText(json, const ['launch_prompt', 'launchPrompt']),
        rawText: text,
      );
    } catch (_) {
      return ProjectChatAgentDirective(
        action: ProjectChatAgentAction.reply,
        replyText: trimmed,
        rawText: text,
      );
    }
  }

  static ProjectChatAgentAction _parseAction(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'task_draft':
      case 'draft':
      case 'task':
        return ProjectChatAgentAction.taskDraft;
      case 'start_agent':
      case 'run_agent':
      case 'launch':
        return ProjectChatAgentAction.startAgent;
      case 'status':
        return ProjectChatAgentAction.status;
      case 'clarify':
      case 'question':
        return ProjectChatAgentAction.clarify;
      case 'reply':
      default:
        return ProjectChatAgentAction.reply;
    }
  }

  static String _wireAction(ProjectChatAgentAction action) {
    switch (action) {
      case ProjectChatAgentAction.taskDraft:
        return 'task_draft';
      case ProjectChatAgentAction.startAgent:
        return 'start_agent';
      case ProjectChatAgentAction.status:
        return 'status';
      case ProjectChatAgentAction.clarify:
        return 'clarify';
      case ProjectChatAgentAction.reply:
        return 'reply';
    }
  }

  static String _firstText(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  static String _extractJsonObject(String text) {
    var source = text.trim();
    if (source.startsWith('```')) {
      source = source
          .replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '')
          .trim();
    }

    final start = source.indexOf('{');
    if (start < 0) {
      return '';
    }
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < source.length; index += 1) {
      final char = source[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) {
        continue;
      }
      if (char == '{') {
        depth += 1;
      } else if (char == '}') {
        depth -= 1;
        if (depth == 0) {
          return source.substring(start, index + 1);
        }
      }
    }
    return '';
  }
}
