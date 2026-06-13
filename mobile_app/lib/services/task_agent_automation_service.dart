import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../features/tasks/agent_launch_plan.dart';
import '../models/agent_policy.dart';
import '../models/task_collaboration.dart';
import '../models/task_item.dart';
import '../state/task_store.dart';
import 'codewhale_bridge_service.dart';

part 'task_agent_automation_context.dart';

typedef TaskAgentBridgeFactory = CodeWhaleBridgeService Function({
  required void Function(CodeWhaleBridgeMessage message) onMessage,
  required void Function(bool connected, String status) onStatusChange,
});

class TaskAgentAutomationService {
  TaskAgentAutomationService({
    required this.store,
    required this.actorPhone,
    TaskAgentBridgeFactory? bridgeFactory,
    void Function(String message)? onLog,
  })  : _bridgeFactory = bridgeFactory,
        _onLog = onLog;

  final TaskStore store;
  final String Function() actorPhone;
  final TaskAgentBridgeFactory? _bridgeFactory;
  final void Function(String message)? _onLog;

  CodeWhaleBridgeService? _bridge;
  _TaskAgentAutomationRun? _activeRun;
  final Set<String> _activeKeys = <String>{};

  Future<bool> continueLatestForInProgressTask({
    required TaskItem task,
    required AgentRunPolicy policy,
  }) async {
    if (task.workflowStatus != WorkflowStatus.in_progress) {
      return false;
    }
    final session = _latestAutoContinuableSession(task, policy);
    if (session == null) {
      return false;
    }
    final key = '${task.id}:${session.id}';
    if (!_activeKeys.add(key)) {
      return false;
    }
    try {
      await _runContinuation(task: task, session: session, policy: policy);
      return true;
    } catch (error, stackTrace) {
      _log('Task agent auto continuation failed: $error\n$stackTrace');
      await _markSessionStatusBestEffort(task, session.id, 'error');
      return false;
    } finally {
      _activeKeys.remove(key);
      if (_activeRun?.task.id == task.id &&
          _activeRun?.session.id == session.id) {
        _activeRun = null;
      }
    }
  }

  Future<void> _runContinuation({
    required TaskItem task,
    required TaskAgentSession session,
    required AgentRunPolicy policy,
  }) async {
    final workspaceId = session.workspaceId.trim().isNotEmpty
        ? session.workspaceId.trim()
        : policy.workspaceId.trim();
    final bridgeSessionId = session.sessionId.trim();
    if (workspaceId.isEmpty || bridgeSessionId.isEmpty) {
      return;
    }

    await _markSessionStatusBestEffort(task, session.id, 'running');
    await store.syncDelta();

    final api = store.repository.api;
    final taskType = _taskTypeForAgent(task);
    final requestedMode =
        session.mode.trim().isNotEmpty ? session.mode.trim() : policy.mode;
    final ticket = await api.requestAgentTicket(
      actorProfile: store.owner.value,
      actorPhone: actorPhone(),
      taskId: task.id,
      taskType: taskType,
      workspaceId: workspaceId,
      requestedMode: requestedMode,
      sessionId: bridgeSessionId,
    );
    final backendPrompt = await _fetchContextPromptBestEffort(
      task: task,
      workspaceId: workspaceId,
      taskType: taskType,
      requestedMode: requestedMode,
    );
    final launchPlan = AgentLaunchPlan.buildContinuation(
      contextPrompt: _buildAgentCardPrompt(backendPrompt, task),
      selectedCommandValues: _agentCommandValuesFor(task, session),
      commands: const [],
    );
    final taskCard = <String, dynamic>{
      'task_id': task.id,
      'agent_session_id': session.id,
      'actor_profile': store.owner.value,
      'actor_phone': actorPhone(),
      'api_url': api.baseUrl,
      'policy_ticket': ticket.policyTicket,
      'task_type': taskType,
      'mode': requestedMode,
      'workspace_id': workspaceId,
    };

    final bridge = _ensureBridge();
    final connected = await bridge.connect();
    if (!connected) {
      throw StateError('CodeWhale is unavailable');
    }
    final run = _TaskAgentAutomationRun(
      task: task,
      session: session,
      workspaceId: workspaceId,
      bridgeSessionId: bridgeSessionId,
      taskType: taskType,
      requestedMode: requestedMode,
      taskCard: taskCard,
      steps: List<AgentLaunchStep>.from(launchPlan.steps),
    );
    _activeRun = run;

    bridge.updatePolicyTicket(ticket.policyTicket);
    bridge.requestCodeWhaleCommands();
    bridge.updateSessionTaskCard(
      workspaceId: workspaceId,
      sessionId: bridgeSessionId,
      taskCard: taskCard,
    );
    bridge.updateSessionSettings(
      workspaceId: workspaceId,
      sessionId: bridgeSessionId,
      provider: _sessionProvider(task, session),
      model: _sessionModel(task, session),
      approvalPolicy: _sessionApprovalPolicy(task, session),
      sandboxMode: _sessionSandboxMode(task, session),
      autoMode: _sessionAutoMode(task, session),
    );
    _uploadTaskFiles(task, workspaceId, bridgeSessionId);
    _sendNextStep(run);
    await run.done.future;
  }

  CodeWhaleBridgeService _ensureBridge() {
    final existing = _bridge;
    if (existing != null) {
      return existing;
    }
    final factory = _bridgeFactory;
    final bridge = factory == null
        ? CodeWhaleBridgeService(
            onMessage: _handleBridgeMessage,
            onStatusChange: (connected, status) {
              if (!connected) {
                _log(status);
              }
            },
          )
        : factory(
            onMessage: _handleBridgeMessage,
            onStatusChange: (connected, status) {
              if (!connected) {
                _log(status);
              }
            },
          );
    _bridge = bridge;
    return bridge;
  }

  void _handleBridgeMessage(CodeWhaleBridgeMessage message) {
    final run = _activeRun;
    if (run == null || run.done.isCompleted) {
      return;
    }
    if (message.isError) {
      final errorText =
          message.error.isEmpty ? 'CodeWhale error' : message.error;
      _finishRunWithError(run, errorText);
      return;
    }
    if (message.type == 'assistant_delta') {
      run.buffer.write(message.text);
      return;
    }
    if (message.type == 'session_task') {
      if (!_isBridgeTaskDone(message.taskStatus)) {
        return;
      }
      if (message.taskResultSummary.trim().isNotEmpty) {
        run.buffer.write(message.taskResultSummary);
      }
      _finishActiveStep(run, message.taskStatus);
      return;
    }
    if (message.type == 'session_stream_done') {
      _finishActiveStep(run, 'completed');
    }
  }

  void _sendNextStep(_TaskAgentAutomationRun run) {
    if (run.steps.isEmpty) {
      unawaited(_completeRun(run));
      return;
    }
    final step = run.steps.removeAt(0);
    run.activeStep = step;
    run.buffer = StringBuffer();
    _bridge?.sendSessionMessage(
      run.workspaceId,
      run.bridgeSessionId,
      step.text,
    );
    unawaited(
      store.repository.api
          .recordAgentEvent(
        actorProfile: store.owner.value,
        actorPhone: actorPhone(),
        taskId: run.task.id,
        workspaceId: run.workspaceId,
        agentSessionId: run.session.id,
        eventType: 'agent_auto_step_sent',
        payload: {
          'label': step.label,
          'kind': step.kind.name,
        },
        taskType: run.taskType,
        requestedMode: run.requestedMode,
      )
          .catchError((Object error) {
        _log('Task agent auto event skipped: $error');
      }),
    );
  }

  void _finishActiveStep(_TaskAgentAutomationRun run, String taskStatus) {
    if (taskStatus == 'failed' || taskStatus == 'canceled') {
      _finishRunWithError(
        run,
        'One of the agent steps did not complete: $taskStatus',
      );
      return;
    }
    final step = run.activeStep;
    final resultText = run.buffer.toString();
    if (_mandatoryStepFailed(step, resultText)) {
      _finishRunWithError(
        run,
        'family-task-card is unavailable. Auto continuation stopped.',
      );
      return;
    }
    if (step?.kind == AgentLaunchStepKind.taskPrompt) {
      run.task = _applyAgentResultToTask(run.task, resultText, run.session.id);
      unawaited(_saveTask(run.task));
    }
    run.activeStep = null;
    run.buffer = StringBuffer();
    _sendNextStep(run);
  }

  Future<void> _completeRun(_TaskAgentAutomationRun run) async {
    var task = await _refreshTaskFromBackendBestEffort(run);
    task = _forceReviewAfterSuccessfulAgentRun(task, run.session.id);
    final sessionStatus = _sessionStatusAfterRun(task, run.session.id);
    task = _markSessionStatus(task, run.session.id, sessionStatus);
    await _saveTask(task);
    unawaited(
      store.repository.api
          .recordAgentEvent(
        actorProfile: store.owner.value,
        actorPhone: actorPhone(),
        taskId: task.id,
        workspaceId: run.workspaceId,
        agentSessionId: run.session.id,
        eventType: 'agent_auto_completed',
        payload: {'status': sessionStatus},
        taskType: run.taskType,
        requestedMode: run.requestedMode,
      )
          .catchError((Object error) {
        _log('Task agent auto completion event skipped: $error');
      }),
    );
    if (!run.done.isCompleted) {
      run.done.complete();
    }
  }

  void _finishRunWithError(_TaskAgentAutomationRun run, String message) {
    unawaited(_markSessionStatusBestEffort(run.task, run.session.id, 'error'));
    _log(message);
    if (!run.done.isCompleted) {
      run.done.complete();
    }
  }

  Future<TaskItem> _refreshTaskFromBackendBestEffort(
    _TaskAgentAutomationRun run,
  ) async {
    try {
      final contextPack = await store.repository.api.fetchAgentContext(
        actorProfile: store.owner.value,
        actorPhone: actorPhone(),
        taskId: run.task.id,
        workspaceId: run.workspaceId,
        taskType: run.taskType,
        requestedMode: run.requestedMode,
      );
      return _applyContextPack(run.task, contextPack);
    } catch (error) {
      _log('Task agent auto backend refresh skipped: $error');
      return run.task;
    }
  }

  Future<String> _fetchContextPromptBestEffort({
    required TaskItem task,
    required String workspaceId,
    required String taskType,
    required String requestedMode,
  }) async {
    try {
      final pack = await store.repository.api.fetchAgentContext(
        actorProfile: store.owner.value,
        actorPhone: actorPhone(),
        taskId: task.id,
        workspaceId: workspaceId,
        taskType: taskType,
        requestedMode: requestedMode,
      );
      return pack.toPrompt();
    } catch (error) {
      _log('Task agent auto context skipped: $error');
      return '';
    }
  }

  Future<void> _saveTask(TaskItem task) async {
    final current = _currentTask(task.id) ?? task;
    await store.saveExistingSnapshot(
      previous: current,
      task: task.copyWith(
        updatedAt: DateTime.now().toIso8601String(),
        version: current.id == task.id ? current.version + 1 : task.version + 1,
      ),
      rememberUndo: false,
    );
  }

  TaskItem? _currentTask(String taskId) {
    for (final task in store.allTasksView.value) {
      if (task.id == taskId) {
        return task;
      }
    }
    for (final tasks in store.personalByStatus.value.values) {
      for (final task in tasks) {
        if (task.id == taskId) {
          return task;
        }
      }
    }
    return null;
  }

  Future<void> _markSessionStatusBestEffort(
    TaskItem task,
    String sessionId,
    String status,
  ) async {
    try {
      await _saveTask(_markSessionStatus(task, sessionId, status));
    } catch (error) {
      _log('Task agent auto session status skipped: $error');
    }
  }

  TaskAgentSession? _latestAutoContinuableSession(
    TaskItem task,
    AgentRunPolicy policy,
  ) {
    for (final session in task.collaboration.agentSessions.reversed) {
      if (_shouldAutoResumeSession(session) &&
          _canContinueSession(task, session, policy)) {
        return session;
      }
    }
    return null;
  }

  bool _shouldAutoResumeSession(TaskAgentSession session) {
    switch (session.status.trim()) {
      case 'pending':
      case 'linked':
      case 'waiting_review':
      case 'blocked':
      case 'completed':
        return true;
      default:
        return false;
    }
  }

  bool _canContinueSession(
    TaskItem task,
    TaskAgentSession session,
    AgentRunPolicy policy,
  ) {
    if (!policy.allowed || session.sessionId.trim().isEmpty) {
      return false;
    }
    if (task.workflowStatus == WorkflowStatus.done ||
        task.workflowStatus == WorkflowStatus.archive) {
      return false;
    }
    if (!policy.allowedCommands.contains('session_send') ||
        !policy.allowedCommands.contains('session_update_task_card')) {
      return false;
    }
    return session.status != 'error' && session.status != 'running';
  }

  String _buildAgentCardPrompt(String backendPrompt, TaskItem task) {
    final lines = <String>[];
    final remote = backendPrompt.trim();
    if (remote.isNotEmpty) {
      lines.add(remote);
      lines.add('');
    }
    lines.add('Актуальная карточка из мобильного приложения:');
    lines.add('Название: ${task.title}');
    if (task.details.trim().isNotEmpty) {
      lines.add('Описание: ${task.details.trim()}');
    }
    lines.add('Статус: ${task.workflowStatus.name}');
    lines.add('Проект: ${task.projectId}');
    final comments =
        task.collaboration.comments.where((item) => !item.isDeleted);
    if (comments.isNotEmpty) {
      lines.add('');
      lines.add('Комментарии карточки:');
      for (final comment in comments.take(30)) {
        final text = comment.text.trim();
        if (text.isNotEmpty) {
          lines.add('- ${comment.authorProfile}: $text');
        }
      }
    }
    if (task.collaboration.checklists.isNotEmpty) {
      lines.add('');
      lines.add('Чеклисты карточки:');
      for (final checklist in task.collaboration.checklists) {
        lines.add('- ${checklist.title}');
        for (final item in checklist.items) {
          lines.add('  - [${item.done ? 'x' : ' '}] ${item.text}');
        }
      }
    }
    if (task.collaboration.attachments.isNotEmpty) {
      lines.add('');
      lines.add('Вложения карточки:');
      for (final attachment in task.collaboration.attachments) {
        final source = attachment.assetUrl.trim().isNotEmpty
            ? attachment.assetUrl.trim()
            : 'будет прикреплено в агентский чат';
        final caption = attachment.caption.trim();
        lines.add(
          '- ${attachment.filename} - $source'
          '${caption.isEmpty ? '' : ' - $caption'}',
        );
      }
    }
    lines.add('');
    lines.add(
      'После работы обнови карточку через family-task-card и не спрашивай подтверждение на перевод: если работа готова и нет блокирующего вопроса, сразу выполни family-task-card finish --summary "<краткий итог>" --result-status ready_for_review.',
    );
    lines.add(
      'Если без ответа пользователя продолжать нельзя, задай блокирующий вопрос через family-task-card question ask --text "..." --blocking.',
    );
    return lines.join('\n');
  }

  List<String> _agentCommandValuesFor(
    TaskItem task,
    TaskAgentSession session,
  ) {
    if (session.commandValues.isNotEmpty) {
      return session.commandValues;
    }
    return task.collaboration.agentSettings.commandValues;
  }

  String _sessionProvider(TaskItem task, TaskAgentSession session) {
    return session.provider.trim().isNotEmpty
        ? session.provider
        : task.collaboration.agentSettings.provider;
  }

  String _sessionModel(TaskItem task, TaskAgentSession session) {
    return session.model.trim().isNotEmpty
        ? session.model
        : task.collaboration.agentSettings.model;
  }

  String _sessionApprovalPolicy(TaskItem task, TaskAgentSession session) {
    return session.approvalPolicy.trim().isNotEmpty
        ? session.approvalPolicy
        : task.collaboration.agentSettings.approvalPolicy;
  }

  String _sessionSandboxMode(TaskItem task, TaskAgentSession session) {
    return session.sandboxMode.trim().isNotEmpty
        ? session.sandboxMode
        : task.collaboration.agentSettings.sandboxMode;
  }

  bool _sessionAutoMode(TaskItem task, TaskAgentSession session) {
    return session.autoMode || task.collaboration.agentSettings.autoMode;
  }

  void _uploadTaskFiles(TaskItem task, String workspaceId, String sessionId) {
    for (final attachment in task.collaboration.attachments) {
      final bytes = _decodeAttachmentBytes(attachment.dataBase64);
      if (bytes == null || bytes.isEmpty) {
        continue;
      }
      _bridge?.uploadSessionFile(
        workspaceId: workspaceId,
        sessionId: sessionId,
        bytes: bytes,
        filename: attachment.filename.isEmpty
            ? 'task-attachment.bin'
            : attachment.filename,
        mimeType: attachment.mimeType.isEmpty
            ? _mimeTypeForName(attachment.filename)
            : attachment.mimeType,
        caption: attachment.caption.isEmpty
            ? 'Файл из карточки задачи'
            : attachment.caption,
      );
    }
  }

  Uint8List? _decodeAttachmentBytes(String value) {
    if (value.trim().isEmpty) {
      return null;
    }
    try {
      return base64Decode(value);
    } on FormatException {
      return null;
    }
  }

  bool _mandatoryStepFailed(AgentLaunchStep? step, String resultText) {
    if (step == null) {
      return false;
    }
    final mandatory = step.kind == AgentLaunchStepKind.taskCardRead ||
        step.text.trim() == '/skill family-task-card';
    if (!mandatory) {
      return false;
    }
    final lower = resultText.toLowerCase();
    if (lower.trim().isEmpty) {
      return false;
    }
    return lower.contains('not found') ||
        lower.contains('unknown skill') ||
        lower.contains('command not found') ||
        lower.contains('no such file') ||
        lower.contains('не найден') ||
        lower.contains('не найдена') ||
        lower.contains('недоступ') ||
        lower.contains('ошибка') ||
        lower.contains('error') ||
        lower.contains('/familly-task-card');
  }

  bool _isBridgeTaskDone(String status) {
    return status == 'completed' || status == 'failed' || status == 'canceled';
  }

  WorkflowStatus? _workflowStatusFromString(String value) {
    final normalized = AgentTaskActions.parse(
      'TASK_CARD_ACTIONS_JSON: {"status": ${jsonEncode(value)}}',
    ).status;
    final statusValue = normalized.isEmpty ? value.trim() : normalized;
    return WorkflowStatus.values.cast<WorkflowStatus?>().firstWhere(
          (item) => item?.name == statusValue,
          orElse: () => null,
        );
  }

  int _workflowRank(WorkflowStatus status) {
    switch (status) {
      case WorkflowStatus.todo:
        return 0;
      case WorkflowStatus.in_progress:
        return 1;
      case WorkflowStatus.in_review:
        return 2;
      case WorkflowStatus.done:
        return 3;
      case WorkflowStatus.archive:
        return 4;
    }
  }

  String _workflowStatusLabel(WorkflowStatus status) {
    switch (status) {
      case WorkflowStatus.todo:
        return 'To do';
      case WorkflowStatus.in_progress:
        return 'In progress';
      case WorkflowStatus.in_review:
        return 'In review';
      case WorkflowStatus.done:
        return 'Done';
      case WorkflowStatus.archive:
        return 'Archive';
    }
  }

  String _taskTypeForAgent(TaskItem task) {
    final tags = task.tags.map((item) => item.toLowerCase()).toSet();
    if (tags.contains('bugfix') || tags.contains('bug')) {
      return 'bugfix';
    }
    if (tags.contains('review')) {
      return 'review';
    }
    if (tags.contains('docs') || tags.contains('doc')) {
      return 'docs';
    }
    if (tags.contains('planning') || tags.contains('plan')) {
      return 'planning';
    }
    return 'feature';
  }

  String _attachmentKind(String filename, String mimeType) {
    final lower = '$filename $mimeType'.toLowerCase();
    if (lower.contains('image/') ||
        lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif')) {
      return 'photo';
    }
    return 'file';
  }

  String _mimeTypeForName(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.md')) return 'text/markdown';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }

  TaskActivityEntry _activity({
    required String type,
    required String text,
    required String targetId,
  }) {
    final now = DateTime.now().toIso8601String();
    return TaskActivityEntry(
      id: _newId('activity'),
      type: type,
      actorProfile: 'agent',
      text: text,
      createdAt: now,
      targetId: targetId,
    );
  }

  String _newId(String prefix) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
  }

  void _log(String message) {
    final handler = _onLog;
    if (handler != null) {
      handler(message);
    } else {
      debugPrint(message);
    }
  }

  void dispose() {
    _bridge?.dispose();
    _bridge = null;
  }
}

class _TaskAgentAutomationRun {
  _TaskAgentAutomationRun({
    required this.task,
    required this.session,
    required this.workspaceId,
    required this.bridgeSessionId,
    required this.taskType,
    required this.requestedMode,
    required this.taskCard,
    required this.steps,
  });

  TaskItem task;
  final TaskAgentSession session;
  final String workspaceId;
  final String bridgeSessionId;
  final String taskType;
  final String requestedMode;
  final Map<String, dynamic> taskCard;
  final List<AgentLaunchStep> steps;
  final Completer<void> done = Completer<void>();

  AgentLaunchStep? activeStep;
  StringBuffer buffer = StringBuffer();
}
