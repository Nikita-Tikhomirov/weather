part of 'task_agent_automation_service.dart';

extension TaskAgentAutomationContextMerge on TaskAgentAutomationService {
  TaskItem _markSessionStatus(
    TaskItem task,
    String sessionId,
    String status,
  ) {
    final sessions = task.collaboration.agentSessions.map((session) {
      if (session.id != sessionId) {
        return session;
      }
      return session.copyWith(status: status);
    }).toList();
    return task.copyWith(
      collaboration: task.collaboration.copyWith(agentSessions: sessions),
    );
  }

  TaskItem _forceReviewAfterSuccessfulAgentRun(
    TaskItem task,
    String agentSessionId,
  ) {
    if (task.workflowStatus == WorkflowStatus.in_review ||
        task.workflowStatus == WorkflowStatus.done ||
        task.workflowStatus == WorkflowStatus.archive ||
        _hasOpenBlockingQuestion(task, agentSessionId)) {
      return task;
    }
    return task.copyWith(
      workflowStatus: WorkflowStatus.in_review,
      collaboration: task.collaboration.copyWith(
        activity: [
          ...task.collaboration.activity,
          _activity(
            type: 'agent_status_changed',
            text: 'автоматически перевел карточку в статус На проверке',
            targetId: agentSessionId,
          ),
        ],
      ),
    );
  }

  bool _hasOpenBlockingQuestion(TaskItem task, String agentSessionId) {
    return task.collaboration.questions.any((question) {
      return question.blocking && question.isOpen;
    });
  }

  String _sessionStatusAfterRun(TaskItem task, String agentSessionId) {
    final session = task.collaboration.agentSessions
        .cast<TaskAgentSession?>()
        .firstWhere((item) => item?.id == agentSessionId, orElse: () => null);
    if (session?.status == 'blocked' ||
        _hasOpenBlockingQuestion(task, agentSessionId)) {
      return 'blocked';
    }
    if (task.workflowStatus == WorkflowStatus.done ||
        task.workflowStatus == WorkflowStatus.archive) {
      return 'completed';
    }
    return 'waiting_review';
  }

  TaskItem _applyAgentResultToTask(
    TaskItem task,
    String text,
    String agentSessionId,
  ) {
    final contextTask = _applyAgentContextPackFromText(task, text);
    if (contextTask != null) {
      return contextTask;
    }
    return _applyAgentTaskActionsFromText(task, text, agentSessionId);
  }

  TaskItem? _applyAgentContextPackFromText(TaskItem task, String text) {
    for (final json in _jsonMapsFromText(text)) {
      final rawSnapshot = json['snapshot'] ?? json['context'];
      if (rawSnapshot is! Map && json['task'] is! Map) {
        continue;
      }
      final rawPack = rawSnapshot is Map ? rawSnapshot : json;
      final pack = AgentContextPack.fromJson(
        Map<String, dynamic>.from(rawPack),
      );
      if (!_hasAgentContextPayload(pack)) {
        continue;
      }
      return _applyContextPack(task, pack);
    }
    return null;
  }

  bool _hasAgentContextPayload(AgentContextPack pack) {
    return (pack.task['workflow_status'] ?? '').toString().trim().isNotEmpty ||
        pack.comments.isNotEmpty ||
        pack.checklists.isNotEmpty ||
        pack.attachments.isNotEmpty ||
        pack.questions.isNotEmpty ||
        pack.activity.isNotEmpty ||
        pack.agentSessions.isNotEmpty;
  }

  TaskItem _applyContextPack(TaskItem task, AgentContextPack pack) {
    final remoteStatus = _workflowStatusFromString(
      (pack.task['workflow_status'] ?? '').toString(),
    );
    var nextStatus = task.workflowStatus;
    if (remoteStatus != null &&
        (_hasRemoteCardPayload(pack) ||
            _workflowRank(remoteStatus) >= _workflowRank(nextStatus))) {
      nextStatus = remoteStatus;
    }
    final remoteComments = pack.comments.map(TaskComment.fromJson).toList();
    final remoteAttachments =
        pack.attachments.map(TaskAttachment.fromJson).toList();
    final remoteChecklists =
        pack.checklists.map(TaskChecklist.fromJson).toList();
    final remoteQuestions =
        pack.questions.map(TaskAgentQuestion.fromJson).toList();
    final remoteActivity =
        pack.activity.map(TaskActivityEntry.fromJson).toList();
    final remoteSessions =
        pack.agentSessions.map(TaskAgentSession.fromJson).toList();
    return task.copyWith(
      workflowStatus: nextStatus,
      collaboration: task.collaboration.copyWith(
        comments: _mergeById(
          task.collaboration.comments,
          remoteComments,
          (item) => item.id,
        ),
        attachments: _mergeById(
          task.collaboration.attachments,
          remoteAttachments,
          (item) => item.id,
        ),
        checklists: _mergeById(
          task.collaboration.checklists,
          remoteChecklists,
          (item) => item.id,
        ),
        questions: _mergeById(
          task.collaboration.questions,
          remoteQuestions,
          (item) => item.id,
        ),
        activity: _mergeById(
          task.collaboration.activity,
          remoteActivity,
          (item) => item.id,
        ),
        agentSessions: _mergeAgentSessions(
          task.collaboration.agentSessions,
          remoteSessions,
        ),
      ),
    );
  }

  bool _hasRemoteCardPayload(AgentContextPack pack) {
    return pack.comments.isNotEmpty ||
        pack.checklists.isNotEmpty ||
        pack.attachments.isNotEmpty ||
        pack.questions.isNotEmpty ||
        pack.activity.isNotEmpty ||
        pack.agentSessions.isNotEmpty;
  }

  TaskItem _applyAgentTaskActionsFromText(
    TaskItem task,
    String text,
    String agentSessionId,
  ) {
    final actions = AgentTaskActions.parse(text);
    final summary = AgentTaskActions.stripActionsBlock(text);
    if (actions.isEmpty && summary.trim().isEmpty) {
      return task;
    }
    final now = DateTime.now().toIso8601String();
    final status = _workflowStatusFromString(actions.status);
    final attachments = actions.attachments.map((draft) {
      final filename = draft.filename.isNotEmpty
          ? draft.filename
          : draft.path.split(RegExp(r'[/\\]')).last;
      final mimeType = draft.mimeType.isNotEmpty
          ? draft.mimeType
          : _mimeTypeForName(filename);
      return TaskAttachment(
        id: _newId('attachment'),
        kind: _attachmentKind(filename, mimeType),
        filename: filename.isEmpty ? 'agent-report' : filename,
        mimeType: mimeType,
        assetUrl: draft.path,
        caption: draft.caption,
        authorProfile: 'agent',
        createdAt: now,
      );
    }).toList();
    final comments = <TaskComment>[];
    final actionComments = actions.comments.isEmpty && summary.trim().isNotEmpty
        ? [summary.trim()]
        : actions.comments;
    for (final commentText in actionComments) {
      comments.add(
        TaskComment(
          id: _newId('comment'),
          authorProfile: 'agent',
          text: commentText,
          createdAt: now,
          attachmentIds: attachments.map((item) => item.id).toList(),
        ),
      );
    }
    final checklists = actions.checklists.map((draft) {
      return TaskChecklist(
        id: _newId('checklist'),
        title: draft.title.isEmpty ? 'План агента' : draft.title,
        createdBy: 'agent',
        createdAt: now,
        items: draft.items
            .map(
              (item) => TaskChecklistItem(
                id: _newId('checklist-item'),
                text: item,
                createdAt: now,
                createdBy: 'agent',
              ),
            )
            .toList(),
      );
    }).toList();
    return task.copyWith(
      workflowStatus: status ?? task.workflowStatus,
      collaboration: task.collaboration.copyWith(
        comments: [...task.collaboration.comments, ...comments],
        attachments: [...task.collaboration.attachments, ...attachments],
        checklists: [...task.collaboration.checklists, ...checklists],
        activity: [
          ...task.collaboration.activity,
          if (status != null && status != task.workflowStatus)
            _activity(
              type: 'agent_status_changed',
              text: 'перевел карточку в статус ${_workflowStatusLabel(status)}',
              targetId: agentSessionId,
            ),
          _activity(
            type: 'agent_card_updated',
            text: 'обновил карточку задачи',
            targetId: agentSessionId,
          ),
        ],
      ),
    );
  }

  Iterable<Map<String, dynamic>> _jsonMapsFromText(String text) sync* {
    for (var start = 0; start < text.length; start += 1) {
      if (text.codeUnitAt(start) != 123) {
        continue;
      }
      var depth = 0;
      var inString = false;
      var escaped = false;
      for (var index = start; index < text.length; index += 1) {
        final unit = text.codeUnitAt(index);
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (unit == 92) {
            escaped = true;
          } else if (unit == 34) {
            inString = false;
          }
          continue;
        }
        if (unit == 34) {
          inString = true;
          continue;
        }
        if (unit == 123) {
          depth += 1;
        } else if (unit == 125) {
          depth -= 1;
          if (depth == 0) {
            final candidate = text.substring(start, index + 1);
            try {
              final decoded = jsonDecode(candidate);
              if (decoded is Map) {
                yield Map<String, dynamic>.from(decoded);
              }
            } on FormatException {
              // Ignore non-JSON braces from agent output.
            }
            start = index;
            break;
          }
        }
      }
    }
  }

  List<T> _mergeById<T>(
    List<T> local,
    List<T> remote,
    String Function(T item) idOf,
  ) {
    if (remote.isEmpty) {
      return local;
    }
    final remoteIds =
        remote.map(idOf).where((id) => id.trim().isNotEmpty).toSet();
    return [
      ...remote,
      ...local.where((item) {
        final id = idOf(item).trim();
        return id.isEmpty || !remoteIds.contains(id);
      }),
    ];
  }

  List<TaskAgentSession> _mergeAgentSessions(
    List<TaskAgentSession> local,
    List<TaskAgentSession> remote,
  ) {
    if (remote.isEmpty) {
      return local;
    }
    final localById = {for (final session in local) session.id: session};
    final mergedRemote = remote.map((session) {
      final localSession = localById[session.id];
      if (localSession == null) {
        return session;
      }
      return session.copyWith(
        provider: session.provider.trim().isNotEmpty
            ? session.provider
            : localSession.provider,
        model: session.model.trim().isNotEmpty
            ? session.model
            : localSession.model,
        approvalPolicy: session.approvalPolicy.trim().isNotEmpty
            ? session.approvalPolicy
            : localSession.approvalPolicy,
        sandboxMode: session.sandboxMode.trim().isNotEmpty
            ? session.sandboxMode
            : localSession.sandboxMode,
        autoMode: session.autoMode || localSession.autoMode,
        commandValues: session.commandValues.isNotEmpty
            ? session.commandValues
            : localSession.commandValues,
      );
    }).toList();
    return _mergeById(local, mergedRemote, (item) => item.id);
  }
}
