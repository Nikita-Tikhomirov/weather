import 'dart:async';
import 'dart:convert';

import '../models/chat_models.dart';
import '../models/project_control_models.dart';
import '../models/workspace_session.dart';
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
      'Синтезируй смысл обсуждения, а не копируй фразы из чата. Убирай повторы, объединяй одинаковые идеи и пиши связно.',
      'Для action "reply": ответь обычным связным текстом 2-6 предложений. Не делай список, если пользователь не попросил список.',
      'Для action "task_draft": title должен быть результатом задачи, details - связным описанием, checklist - конкретными шагами без дублей.',
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
      'CHAT_CONTEXT: последние уникальные сообщения чата без технических ответов самого Тудушкера:',
    ];
    for (final signal in _chatSignals(context)) {
      lines.add('${signal.id} ${signal.senderProfile}: ${signal.text}');
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
    String primaryOutput;
    try {
      primaryOutput = await runPrompt(primaryPrompt);
    } catch (_) {
      return buildUnavailableDirective(
        userMessage: userMessage,
        forcedAction: forcedAction,
      );
    }
    if (primaryOutput.trim().isEmpty) {
      return buildUnavailableDirective(
        userMessage: userMessage,
        forcedAction: forcedAction,
      );
    }
    final primaryDirective = parseStrictModelDirective(primaryOutput);
    if (primaryDirective != null) {
      return primaryDirective;
    }
    final primaryPlainReply = parsePlainModelReply(
      primaryOutput,
      userMessage: userMessage,
      forcedAction: forcedAction,
    );
    if (primaryPlainReply != null) {
      return primaryPlainReply;
    }

    String repairOutput;
    try {
      repairOutput = await runPrompt(
        buildRepairPrompt(
          context: context,
          userMessage: userMessage,
          invalidOutput: primaryOutput,
          forcedAction: forcedAction,
        ),
      );
    } catch (_) {
      return buildUnavailableDirective(
        userMessage: userMessage,
        forcedAction: forcedAction,
      );
    }
    final repairedDirective = parseStrictModelDirective(repairOutput);
    if (repairedDirective != null) {
      return repairedDirective;
    }
    final repairedPlainReply = parsePlainModelReply(
      repairOutput,
      userMessage: userMessage,
      forcedAction: forcedAction,
    );
    if (repairedPlainReply != null) {
      return repairedPlainReply;
    }

    return buildUnavailableDirective(
      userMessage: userMessage,
      forcedAction: forcedAction,
    );
  }

  static ProjectChatAgentDirective buildUnavailableDirective({
    required String userMessage,
    ProjectChatAgentAction? forcedAction,
  }) {
    if (forcedAction == ProjectChatAgentAction.taskDraft ||
        _looksLikeTaskRequest(userMessage)) {
      return const ProjectChatAgentDirective(
        action: ProjectChatAgentAction.reply,
        replyText:
            'Я не смог собрать нормальный черновик: не получил ответ AI. Не буду создавать карточку из кусков чата. Проверьте CodeWhale и workspace проекта, затем повторите запрос.',
        rawText: 'ai_unavailable',
      );
    }

    return const ProjectChatAgentDirective(
      action: ProjectChatAgentAction.reply,
      replyText:
          'Сейчас не получил ответ AI, поэтому не буду придумывать ответ из кусков чата. Проверьте CodeWhale и workspace проекта, затем повторите запрос.',
      rawText: 'ai_unavailable',
    );
  }

  static ProjectChatAgentDirective? parsePlainModelReply(
    String text, {
    required String userMessage,
    ProjectChatAgentAction? forcedAction,
  }) {
    if (forcedAction == ProjectChatAgentAction.taskDraft ||
        _looksLikeTaskRequest(userMessage)) {
      return null;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty ||
        _extractJsonObject(trimmed).isNotEmpty ||
        _looksLikeWorkspaceChatter(trimmed) ||
        _looksLikeLowValueAssistantChatter(trimmed)) {
      return null;
    }
    return ProjectChatAgentDirective(
      action: ProjectChatAgentAction.reply,
      replyText: _cleanModelReply(trimmed),
      rawText: text,
    );
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
          return _normalizeDirective(directive);
        case ProjectChatAgentAction.reply:
        case ProjectChatAgentAction.status:
        case ProjectChatAgentAction.clarify:
          return directive.replyText.trim().isEmpty ||
                  _looksLikeWorkspaceChatter(directive.replyText) ||
                  _looksLikeLowValueAssistantChatter(directive.replyText)
              ? null
              : _normalizeDirective(directive);
        case ProjectChatAgentAction.startAgent:
          return _normalizeDirective(directive);
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

  static bool _looksLikeLowValueAssistantChatter(String text) {
    final value = text.toLowerCase();
    return const [
      'принято. я тудушкер',
      'я тудушкер',
      'в канале',
      'на связи',
      'готов работать',
      'готов к работе',
      'что сегодня по задачам',
    ].any(value.contains);
  }

  static bool _looksLikeTaskRequest(String text) {
    final value = text.toLowerCase();
    return const [
      'карточк',
      'таск',
      'todo',
      'черновик',
      'оформ',
      'заплан',
    ].any(value.contains);
  }

  static List<_ChatSignal> _chatSignals(ProjectChatContextPack context) {
    final result = <_ChatSignal>[];
    final seen = <String>{};
    for (final message in context.messages) {
      if (message.isDeleted || _isTudushkerMessage(message)) {
        continue;
      }
      final text = _cleanChatText(message.text);
      if (text.isEmpty || _looksLikeWorkspaceChatter(text)) {
        continue;
      }
      final fingerprint = _messageFingerprint(text);
      if (fingerprint.isEmpty || seen.contains(fingerprint)) {
        continue;
      }
      seen.add(fingerprint);
      result.add(
        _ChatSignal(
          id: message.id,
          senderProfile: message.senderProfile,
          text: text,
        ),
      );
    }
    return result.length <= 8 ? result : result.sublist(result.length - 8);
  }

  static bool _isTudushkerMessage(ChatMessage message) {
    final profile = message.senderProfile.trim().toLowerCase();
    if (profile == 'tudushker' || profile == 'тудушкер') {
      return true;
    }
    return _looksLikeTudushkerFallbackText(message.text);
  }

  static bool _looksLikeTudushkerFallbackText(String text) {
    return RegExp(
      r'^\s*тудушкер\s*[:\-—]',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(text);
  }

  static String _cleanChatText(String text) {
    return text
        .replaceAll(_wakeWordPattern, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _messageFingerprint(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-zа-яё0-9]+', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static ProjectChatAgentDirective _normalizeDirective(
    ProjectChatAgentDirective directive,
  ) {
    final draft = directive.draft;
    return ProjectChatAgentDirective(
      action: directive.action,
      replyText: _cleanModelReply(directive.replyText),
      draft: draft == null ? null : _normalizeDraft(draft),
      launchPrompt: directive.launchPrompt.trim(),
      rawText: directive.rawText,
    );
  }

  static ChatTaskDraft _normalizeDraft(ChatTaskDraft draft) {
    return ChatTaskDraft(
      title: draft.title.trim(),
      details: _cleanModelReply(draft.details),
      summary: _cleanModelReply(draft.summary),
      decisions: _dedupeStrings(draft.decisions),
      actionItems: _dedupeStrings(draft.actionItems),
      blockers: _dedupeStrings(draft.blockers),
      checklist: _dedupeStrings(draft.checklist),
      assignees: _dedupeStrings(draft.assignees),
      sourceMessageIds: _dedupeStrings(draft.sourceMessageIds),
      priority: draft.priority,
    );
  }

  static List<String> _dedupeStrings(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final clean = _cleanModelReply(value);
      if (clean.isEmpty) {
        continue;
      }
      final fingerprint = _messageFingerprint(clean);
      if (fingerprint.isEmpty || seen.contains(fingerprint)) {
        continue;
      }
      seen.add(fingerprint);
      result.add(clean);
    }
    return result;
  }

  static String _cleanModelReply(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
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

class _ChatSignal {
  const _ChatSignal({
    required this.id,
    required this.senderProfile,
    required this.text,
  });

  final String id;
  final String senderProfile;
  final String text;
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
  Timer? _sessionListFallbackTimer;
  String _workspaceId = '';
  String _sessionId = '';
  String _prompt = '';
  String _title = '';
  Map<String, dynamic> _taskCard = const {};
  bool _waitingForSessionList = false;

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
    _title = title.trim();
    _taskCard = Map<String, dynamic>.from(taskCard);
    _waitingForSessionList = false;

    final bridge = _ensureBridge();
    bridge.updatePolicyTicket(policyTicket);
    final connected = await bridge.connect();
    if (!connected) {
      _clearIfActive(completer);
      throw StateError('CodeWhale недоступен');
    }

    _waitingForSessionList = true;
    bridge.requestSessionList(_workspaceId);
    _sessionListFallbackTimer = Timer(const Duration(seconds: 2), () {
      final active = _activeCompleter;
      if (active == completer &&
          !completer.isCompleted &&
          _waitingForSessionList) {
        _waitingForSessionList = false;
        _createSession();
      }
    });

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
      if (_waitingForSessionList) {
        _waitingForSessionList = false;
        _sessionListFallbackTimer?.cancel();
        _sessionListFallbackTimer = null;
        _createSession();
        return;
      }
      completer.completeError(
        StateError(message.error.isEmpty ? 'Ошибка CodeWhale' : message.error),
      );
      return;
    }

    if (message.type == 'session_list') {
      _handleSessionList(message);
      return;
    }

    final session = message.session;
    if (session != null) {
      if (_waitingForSessionList) {
        return;
      }
      if (_sessionId.isNotEmpty && session.id != _sessionId) {
        return;
      }
      _useSession(session);
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
      if (_sessionId.isEmpty) {
        return;
      }
      _buffer.write(message.text);
    }
  }

  void _handleSessionList(CodeWhaleBridgeMessage message) {
    if (!_waitingForSessionList) {
      return;
    }
    final messageWorkspaceId = message.workspaceId.trim();
    if (messageWorkspaceId.isNotEmpty && messageWorkspaceId != _workspaceId) {
      return;
    }
    _waitingForSessionList = false;
    _sessionListFallbackTimer?.cancel();
    _sessionListFallbackTimer = null;

    final reusable = _selectReusableProjectChatSession(message.sessions);
    if (reusable != null) {
      _useSession(reusable);
      return;
    }
    _createSession();
  }

  WorkspaceSession? _selectReusableProjectChatSession(
    List<WorkspaceSession> sessions,
  ) {
    final candidates = sessions
        .where(_matchesProjectChatTaskCard)
        .where(_isReusableSession)
        .toList();
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort((a, b) {
      final rank = _sessionReuseRank(b).compareTo(_sessionReuseRank(a));
      if (rank != 0) {
        return rank;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return candidates.first;
  }

  bool _matchesProjectChatTaskCard(WorkspaceSession session) {
    if (!session.isProjectChatSession) {
      return false;
    }
    final projectId = (_taskCard['project_id'] ?? '').toString().trim();
    final conversationKey =
        (_taskCard['conversation_key'] ?? '').toString().trim();
    if (projectId.isEmpty || conversationKey.isEmpty) {
      return false;
    }
    return session.projectChatKey == '$projectId::$conversationKey';
  }

  bool _isReusableSession(WorkspaceSession session) {
    return switch (session.status) {
      WorkspaceSessionStatus.killed ||
      WorkspaceSessionStatus.stopped ||
      WorkspaceSessionStatus.error =>
        false,
      WorkspaceSessionStatus.idle ||
      WorkspaceSessionStatus.running ||
      WorkspaceSessionStatus.unknown =>
        true,
    };
  }

  int _sessionReuseRank(WorkspaceSession session) {
    return switch (session.status) {
      WorkspaceSessionStatus.running => 3,
      WorkspaceSessionStatus.idle => 2,
      WorkspaceSessionStatus.unknown => 1,
      WorkspaceSessionStatus.stopped ||
      WorkspaceSessionStatus.killed ||
      WorkspaceSessionStatus.error =>
        0,
    };
  }

  void _createSession() {
    _bridge?.createSession(
      _workspaceId,
      title: _title.isEmpty ? 'Тудушкер' : _title,
      taskCard: _taskCard,
    );
  }

  void _useSession(WorkspaceSession session) {
    _sessionId = session.id;
    onSessionLinked?.call(session.id);
    _sendPromptToCurrentSession();
  }

  void _sendPromptToCurrentSession() {
    final prompt = _prompt.trim();
    if (_workspaceId.isEmpty || _sessionId.isEmpty || prompt.isEmpty) {
      return;
    }
    _prompt = '';
    final bridge = _bridge;
    bridge?.startSession(_workspaceId, _sessionId);
    bridge?.sendSessionMessage(_workspaceId, _sessionId, prompt);
  }

  bool _belongsToCurrentSession(CodeWhaleBridgeMessage message) {
    final messageSessionId = message.sessionId.trim();
    if (_sessionId.isEmpty) {
      return false;
    }
    return messageSessionId.isEmpty || messageSessionId == _sessionId;
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
    _title = '';
    _taskCard = const {};
    _waitingForSessionList = false;
    _sessionListFallbackTimer?.cancel();
    _sessionListFallbackTimer = null;
    _cancelPollTimers();
  }

  void _cancelPollTimers() {
    for (final timer in _pollTimers) {
      timer.cancel();
    }
    _pollTimers.clear();
  }

  void dispose() {
    _sessionListFallbackTimer?.cancel();
    _sessionListFallbackTimer = null;
    _cancelPollTimers();
    _bridge?.dispose();
    _bridge = null;
  }
}
