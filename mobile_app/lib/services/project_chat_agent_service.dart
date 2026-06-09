import 'dart:async';
import 'dart:convert';

import '../models/project_control_models.dart';
import 'codewhale_bridge_service.dart';

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
      'Это запрос из группового чата проекта, а не задача по коду. Используй только CHAT_CONTEXT ниже.',
      'Не отвечай про файлы workspace, task-card.json, tc.json, index.html, скрипты, репозиторий или рабочую область, если пользователь прямо не попросил смотреть код.',
      'Не пиши дежурные фразы вроде готовности к работе; дай конкретную пользу по вопросу пользователя и сообщениям чата.',
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
      'CHAT_CONTEXT: последние сообщения чата без технических ответов самого Тудушкера:',
    ];
    for (final message in context.messages) {
      final text = message.text.trim();
      if (text.isEmpty ||
          message.isDeleted ||
          message.senderProfile.trim().toLowerCase() == 'tudushker') {
        continue;
      }
      lines.add('${message.id} ${message.senderProfile}: $text');
    }
    return lines.join('\n');
  }

  static String buildRepairPrompt({
    required ProjectChatContextPack context,
    required String userMessage,
    required String invalidOutput,
    ProjectChatAgentAction? forcedAction,
  }) {
    return [
      buildIntentPrompt(
        context: context,
        userMessage: userMessage,
        forcedAction: forcedAction,
      ),
      '',
      'Предыдущий ответ недопустим: модель вернула не JSON или начала говорить про workspace вместо чата.',
      'Перепиши ответ строго по контракту JSON выше. Не добавляй markdown, пояснения или текст вне JSON.',
      'Недопустимый ответ:',
      invalidOutput.trim(),
    ].join('\n');
  }

  static Future<ProjectChatAgentDirective> resolveDirective({
    required ProjectChatContextPack context,
    required String userMessage,
    required Future<String> Function(String prompt) runPrompt,
    ProjectChatAgentAction? forcedAction,
  }) async {
    final primaryPrompt = buildIntentPrompt(
      context: context,
      userMessage: userMessage,
      forcedAction: forcedAction,
    );
    final primaryOutput = await runPrompt(primaryPrompt);
    final primaryDirective = parseStrictModelDirective(primaryOutput);
    if (primaryDirective != null) {
      return primaryDirective;
    }

    final repairOutput = await runPrompt(
      buildRepairPrompt(
        context: context,
        userMessage: userMessage,
        invalidOutput: primaryOutput,
        forcedAction: forcedAction,
      ),
    );
    final repairedDirective = parseStrictModelDirective(repairOutput);
    if (repairedDirective != null) {
      return repairedDirective;
    }

    throw const ProjectChatAgentInvalidResponse();
  }

  static ProjectChatAgentDirective? parseStrictModelDirective(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final jsonText = _extractJsonObject(trimmed);
    if (jsonText.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) {
        return null;
      }
      final json = Map<String, dynamic>.from(decoded);
      final rawAction = (json['action'] ?? '').toString().trim();
      if (rawAction.isEmpty) {
        return null;
      }
      final action = _parseAction(rawAction);
      final directive = parseModelDirective(jsonText);
      switch (action) {
        case ProjectChatAgentAction.taskDraft:
          final draftSource = json['draft'] is Map
              ? Map<String, dynamic>.from(json['draft'] as Map)
              : json;
          final explicitTitle =
              (draftSource['title'] ?? draftSource['task_title'] ?? '')
                  .toString()
                  .trim();
          final details =
              (draftSource['details'] ?? draftSource['description'] ?? '')
                  .toString()
                  .trim();
          final hasWork = _stringList(
                draftSource['checklist'] ?? draftSource['action_items'],
              ).isNotEmpty ||
              _stringList(draftSource['actionItems']).isNotEmpty;
          if (explicitTitle.isEmpty ||
              (details.isEmpty && !hasWork) ||
              _looksLikeWorkspaceChatter('$explicitTitle\n$details')) {
            return null;
          }
          return directive;
        case ProjectChatAgentAction.reply:
        case ProjectChatAgentAction.status:
        case ProjectChatAgentAction.clarify:
          return directive.replyText.trim().isEmpty ||
                  _looksLikeWorkspaceChatter(directive.replyText)
              ? null
              : directive;
        case ProjectChatAgentAction.startAgent:
          return directive;
      }
    } catch (_) {
      return null;
    }
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

  static List<String> _stringList(Object? raw) {
    if (raw is List) {
      return raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw
          .split(RegExp(r'[\n,;]+'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  static bool _looksLikeWorkspaceChatter(String text) {
    final value = text.toLowerCase();
    return const [
      'task-card.json',
      'tc.json',
      'tc2.json',
      'index.html',
      '_extract_sections.py',
      '_post_comment.ps1',
      'рабочей области',
      'рабочая область',
      'workspace files',
      'workspace-фай',
    ].any(value.contains);
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

typedef ProjectChatAgentBridgeFactory = CodeWhaleBridgeService Function({
  required void Function(CodeWhaleBridgeMessage message) onMessage,
  required void Function(bool connected, String status) onStatusChange,
});

class ProjectChatAgentRequestCancelled implements Exception {
  const ProjectChatAgentRequestCancelled();

  @override
  String toString() => 'Project chat agent request cancelled';
}

class ProjectChatAgentInvalidResponse implements Exception {
  const ProjectChatAgentInvalidResponse();

  @override
  String toString() => 'Project chat agent returned invalid structured output';
}

class ProjectChatAgentBridgeRunner {
  ProjectChatAgentBridgeRunner({
    ProjectChatAgentBridgeFactory? bridgeFactory,
    this.taskPollDelay = const Duration(seconds: 2),
    this.timeout = const Duration(seconds: 90),
    this.onSessionLinked,
    this.onStatusChange,
  }) : _bridgeFactory = bridgeFactory;

  final ProjectChatAgentBridgeFactory? _bridgeFactory;
  final Duration taskPollDelay;
  final Duration timeout;
  final void Function(String sessionId)? onSessionLinked;
  final void Function(bool connected, String status)? onStatusChange;

  CodeWhaleBridgeService? _bridge;
  Completer<String>? _activeCompleter;
  StringBuffer _buffer = StringBuffer();
  final List<Timer> _pollTimers = <Timer>[];
  String _workspaceId = '';
  String _sessionId = '';
  String _prompt = '';

  Future<String> run({
    required String workspaceId,
    required String title,
    required Map<String, dynamic> taskCard,
    required String policyTicket,
    required String prompt,
  }) async {
    final current = _activeCompleter;
    if (current != null && !current.isCompleted) {
      current.completeError(const ProjectChatAgentRequestCancelled());
    }
    _cancelPollTimers();

    final completer = Completer<String>();
    _activeCompleter = completer;
    _buffer = StringBuffer();
    _workspaceId = workspaceId.trim();
    _sessionId = '';
    _prompt = prompt.trim();

    final bridge = _ensureBridge();
    bridge.updatePolicyTicket(policyTicket);
    final connected = await bridge.connect();
    if (!connected) {
      _clearIfActive(completer);
      throw StateError('CodeWhale недоступен');
    }

    bridge.createSession(
      _workspaceId,
      title: title,
      taskCard: taskCard,
    );

    try {
      return await completer.future.timeout(
        timeout,
        onTimeout: () {
          _clearIfActive(completer);
          return '';
        },
      );
    } finally {
      _clearIfActive(completer);
    }
  }

  CodeWhaleBridgeService _ensureBridge() {
    final existing = _bridge;
    if (existing != null) {
      return existing;
    }
    final factory = _bridgeFactory;
    final bridge = factory == null
        ? CodeWhaleBridgeService(
            onMessage: _handleMessage,
            onStatusChange: _handleStatusChange,
          )
        : factory(
            onMessage: _handleMessage,
            onStatusChange: _handleStatusChange,
          );
    _bridge = bridge;
    return bridge;
  }

  void _handleStatusChange(bool connected, String status) {
    onStatusChange?.call(connected, status);
  }

  void _handleMessage(CodeWhaleBridgeMessage message) {
    final completer = _activeCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    if (message.isError) {
      completer.completeError(
        StateError(message.error.isEmpty ? 'Ошибка CodeWhale' : message.error),
      );
      return;
    }

    final session = message.session;
    if (session != null) {
      _sessionId = session.id;
      onSessionLinked?.call(session.id);
      final prompt = _prompt.trim();
      if (_workspaceId.isNotEmpty &&
          _sessionId.isNotEmpty &&
          prompt.isNotEmpty) {
        _prompt = '';
        final bridge = _bridge;
        bridge?.startSession(_workspaceId, _sessionId);
        bridge?.sendSessionMessage(_workspaceId, _sessionId, prompt);
      }
      return;
    }

    if (message.type == 'assistant_delta') {
      if (!_belongsToCurrentSession(message)) {
        return;
      }
      _buffer.write(message.text);
      return;
    }

    if (message.type == 'session_task') {
      if (!_belongsToCurrentSession(message)) {
        return;
      }
      _handleSessionTask(message, completer);
      return;
    }

    if (message.type == 'session_stream_done') {
      if (!_belongsToCurrentSession(message)) {
        return;
      }
      completer.complete(_buffer.toString());
      return;
    }

    if (message.type == 'output' && message.text.trim().isNotEmpty) {
      _buffer.write(message.text);
    }
  }

  bool _belongsToCurrentSession(CodeWhaleBridgeMessage message) {
    final messageSessionId = message.sessionId.trim();
    return messageSessionId.isEmpty ||
        _sessionId.isEmpty ||
        messageSessionId == _sessionId;
  }

  void _handleSessionTask(
    CodeWhaleBridgeMessage message,
    Completer<String> completer,
  ) {
    final status = message.taskStatus.trim().toLowerCase();
    if (!_isDoneStatus(status)) {
      _scheduleTaskPoll(message);
      return;
    }
    if (message.taskResultSummary.trim().isNotEmpty) {
      _buffer.write(message.taskResultSummary);
    }
    if (status == 'failed' || status == 'canceled' || status == 'cancelled') {
      final output = _buffer.toString().trim();
      if (output.isEmpty) {
        completer.completeError(StateError('CodeWhale task $status'));
        return;
      }
    }
    completer.complete(_buffer.toString());
  }

  void _scheduleTaskPoll(CodeWhaleBridgeMessage message) {
    final taskId = message.taskId.trim();
    if (taskId.isEmpty) {
      return;
    }
    final workspaceId = message.workspaceId.trim().isNotEmpty
        ? message.workspaceId.trim()
        : _workspaceId;
    final sessionId = message.sessionId.trim().isNotEmpty
        ? message.sessionId.trim()
        : _sessionId;
    if (workspaceId.isEmpty || sessionId.isEmpty) {
      return;
    }
    final timer = Timer(taskPollDelay, () {
      _bridge?.pollSessionTask(workspaceId, sessionId, taskId);
    });
    _pollTimers.add(timer);
  }

  bool _isDoneStatus(String status) {
    return const {
      'completed',
      'succeeded',
      'success',
      'failed',
      'canceled',
      'cancelled',
    }.contains(status);
  }

  void _clearIfActive(Completer<String> completer) {
    if (_activeCompleter != completer) {
      return;
    }
    _activeCompleter = null;
    _buffer = StringBuffer();
    _prompt = '';
    _cancelPollTimers();
  }

  void _cancelPollTimers() {
    for (final timer in _pollTimers) {
      timer.cancel();
    }
    _pollTimers.clear();
  }

  void dispose() {
    _cancelPollTimers();
    _bridge?.dispose();
    _bridge = null;
  }
}
