// ignore_for_file: invalid_use_of_protected_member

part of 'home_page.dart';

// ───────────────────────────────────────────────────────────────
// Chat section extracted from _HomePageState.
// Messenger page builder and chat-specific helpers.
// ───────────────────────────────────────────────────────────────

extension _ChatSection on _HomePageState {
  // ── Messenger page ──────────────────────────────────────────

  Widget buildMessengerPage(TaskStore store, {required bool compact}) {
    final messages = _chatMessagesByConversation[_activeConversationKey] ??
        const <ChatMessage>[];

    if (_chatLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (isProjectConversation(_activeConversationKey)) {
      return _buildProjectChatView(store, compact: compact);
    }

    final boundProject = _projectForBoundGroupConversation(
      store,
      _activeConversationKey,
    );

    return MessengerPage(
      conversations: _chatConversations,
      contacts: _phoneContacts.isEmpty ? _chatContacts : _phoneContacts,
      messages: messages,
      activeConversationKey: _activeConversationKey,
      owner: store.owner.value,
      compact: compact,
      chatInputController: _chatInputCtl,
      replyToMessage: _replyToMessage,
      editingMessageId: _editingMessageId,
      isRecording: _voiceRecorder?.isRecording ?? false,
      conversationLabel: _conversationLabel,
      contactLabel: contactLabel,
      chatMessageText: chatMessageText,
      profileLabel: _profileLabel,
      stickerAssetFor: chatStickerAssetUrl,
      imageUrlFor: chatImageUrl,
      avatarForContact: _avatarForProfile,
      onRefreshContacts: () => _refreshMessengerContacts(store),
      onCreateGroup: () => _openCreateGroupSheet(store),
      onAddContactToFamily: (contact) => _addContactToFamily(store, contact),
      onOpenDirectContact: (contact) => _openDirectContact(store, contact),
      onOpenWorkspaces: _openCodeWhaleWorkspaces,
      onBackToContacts: () => setState(() => _activeConversationKey = ''),
      onOpenConversation: (conversationKey) =>
          _openConversation(store, conversationKey),
      onOpenMessageActions: (message) => _openMessageActions(store, message),
      onImageTap: _openPhotoViewer,
      hasMoreOlderMessages: _activeConversationKey.isNotEmpty &&
          (_chatOlderCursors[_activeConversationKey]?.isNotEmpty ?? false) &&
          !_chatOlderExhausted.contains(_activeConversationKey),
      loadingOlderMessages: _chatOlderLoading.contains(_activeConversationKey),
      onLoadOlderMessages: () => _loadOlderChatMessages(store),
      onClearReply: () => setState(() => _replyToMessage = null),
      onCancelEdit: () {
        setState(() {
          _editingMessageId = null;
          _chatInputCtl.clear();
        });
      },
      onOpenAttachMenu: () => _openAttachMenu(store),
      onManageGroup: (conv) => _openManageGroupSheet(store, conv),
      activeProject: boundProject,
      onAnalyzeProjectChat: boundProject == null
          ? null
          : () => unawaited(_analyzeProjectChat(store, boundProject)),
      onDraftProjectTask: boundProject == null
          ? null
          : () => unawaited(_analyzeProjectChat(store, boundProject)),
      onStartProjectAgent: boundProject == null
          ? null
          : () => unawaited(_startProjectChatAgent(store, boundProject)),
      onShowProjectStatus: boundProject == null
          ? null
          : () => unawaited(_showProjectChatStatus(store, boundProject)),
      onCallTap: () => _startCallOutgoing(callType: 'audio'),
      onVideoCallTap: () => _startCallOutgoing(callType: 'video'),
      typingUsers: _typingUsers,
      onStartRecord: () => _voiceRecorder?.startRecord(),
      onStopRecord: () => _voiceRecorder?.stopRecord(),
      onSendText: () => _sendTextMessage(store),
    );
  }

  TaskProject? _projectForBoundGroupConversation(
    TaskStore store,
    String conversationKey,
  ) {
    final directProjectId = _projectIdForProjectConversation(conversationKey);
    if (directProjectId.isNotEmpty) {
      return store.projects.value.cast<TaskProject?>().firstWhere(
            (project) => project?.id == directProjectId,
            orElse: () => null,
          );
    }
    final groupId = _familyGroupIdForConversation(conversationKey);
    if (groupId.isEmpty) {
      return null;
    }
    var projectId = '';
    for (final entry in store.projectGroupMap.value.entries) {
      if (entry.value.contains(groupId)) {
        projectId = entry.key;
        break;
      }
    }
    if (projectId.isEmpty) {
      return null;
    }
    return store.projects.value.cast<TaskProject?>().firstWhere(
          (project) => project?.id == projectId,
          orElse: () => null,
        );
  }

  String _familyGroupIdForConversation(String conversationKey) {
    const prefix = 'grp:family:';
    final key = conversationKey.trim();
    return key.startsWith(prefix) ? key.substring(prefix.length) : '';
  }

  String _projectIdForProjectConversation(String conversationKey) {
    const prefix = 'grp:project:';
    final key = conversationKey.trim();
    return key.startsWith(prefix) ? key.substring(prefix.length) : '';
  }

  FamilyGroup? _familyGroupForConversation(TaskStore store, String key) {
    final groupId = _familyGroupIdForConversation(key);
    var effectiveGroupId = groupId;
    if (effectiveGroupId.isEmpty) {
      final projectId = _projectIdForProjectConversation(key);
      final groupIds = store.projectGroupMap.value[projectId] ?? const [];
      effectiveGroupId = groupIds.isEmpty ? '' : groupIds.first;
    }
    if (effectiveGroupId.isEmpty) {
      return null;
    }
    return store.familyGroups.value.cast<FamilyGroup?>().firstWhere(
          (group) => group?.id == effectiveGroupId,
          orElse: () => null,
        );
  }

  Future<ProjectControlSnapshot?> _projectControlSnapshotForChat(
    TaskStore store,
    TaskProject project,
  ) async {
    final cached = _projectControlSnapshots[project.id];
    if (cached != null && cached.primaryWorkspaceId.trim().isNotEmpty) {
      return cached;
    }
    try {
      final snapshot = await store.repository.api.fetchProjectControlSnapshot(
        actorProfile: store.owner.value,
        actorPhone: _currentProfilePhone,
        projectId: project.id,
      );
      _projectControlSnapshots[project.id] = snapshot;
      return snapshot;
    } catch (e, st) {
      debugPrint('[project-chat-agent] project snapshot error: $e\n$st');
      return null;
    }
  }

  Future<String> _workspaceIdForProjectChat(
    TaskStore store,
    TaskProject project,
  ) async {
    final snapshot = await _projectControlSnapshotForChat(store, project);
    return (snapshot?.primaryWorkspaceId ?? '').trim();
  }

  Future<void> _analyzeProjectChat(
    TaskStore store,
    TaskProject project,
  ) async {
    try {
      final request = await _prepareProjectChatAgentRequest(
        store: store,
        project: project,
        userMessage: 'Пользователь нажал кнопку создания черновика задачи.',
      );
      if (request == null) {
        return;
      }
      _showSnack('Тудушкер анализирует чат.');
      final directive = await ProjectChatAgentService.resolveDirective(
        context: request.contextPack,
        userMessage: request.userMessage,
        forcedAction: ProjectChatAgentAction.taskDraft,
        runPrompt: (prompt) {
          return _runProjectChatAgentPrompt(
            workspaceId: request.workspaceId,
            project: project,
            contextPack: request.contextPack,
            policyTicket: request.policyTicket,
            prompt: prompt,
            title: 'Черновик задачи: ${project.name}',
          );
        },
      );
      if (!mounted) {
        return;
      }
      await _applyProjectChatAgentDirective(
        store: store,
        project: project,
        contextPack: request.contextPack,
        directive: directive,
        groupId: request.groupId,
        policyTicket: request.policyTicket,
      );
    } catch (e, st) {
      if (e is ProjectChatAgentRequestCancelled) {
        return;
      }
      if (e is ProjectChatAgentInvalidResponse) {
        _showSnack('Тудушкер вернул неструктурированный ответ.');
        return;
      }
      debugPrint('[project-chat-agent] analyze error: $e\n$st');
      _showSnack('Не удалось проанализировать чат проекта.');
    }
  }

  Future<void> _startProjectChatAgent(
    TaskStore store,
    TaskProject project,
  ) async {
    final workspaceId = await _workspaceIdForProjectChat(store, project);
    if (workspaceId.isEmpty) {
      _showSnack('Выберите workspace проекта в Project Control Center.');
      return;
    }
    try {
      final contextPack = await store.repository.api.fetchProjectChatContext(
        actorProfile: store.owner.value,
        actorPhone: _currentProfilePhone,
        projectId: project.id,
        conversationKey: _activeConversationKey,
        workspaceId: workspaceId,
      );
      final ticket = await store.repository.api.requestProjectChatAgentTicket(
        actorProfile: store.owner.value,
        actorPhone: _currentProfilePhone,
        projectId: project.id,
        conversationKey: _activeConversationKey,
        workspaceId: workspaceId,
        requestedMode: contextPack.automation.defaultAgentMode,
      );
      await _queueProjectChatAgentPrompt(
        workspaceId: workspaceId,
        project: project,
        contextPack: contextPack,
        policyTicket: ticket.policyTicket,
        prompt: contextPack.toPrompt(),
        title: 'Анализ чата: ${project.name}',
      );
      _showSnack('Агент проекта запускается в CodeWhale.');
    } catch (e, st) {
      debugPrint('[project-chat-agent] start error: $e\n$st');
      _showSnack('Не удалось запустить агента проекта.');
    }
  }

  Future<_ProjectChatAgentRequest?> _prepareProjectChatAgentRequest({
    required TaskStore store,
    required TaskProject project,
    required String userMessage,
  }) async {
    final workspaceId = await _workspaceIdForProjectChat(store, project);
    if (workspaceId.isEmpty) {
      _showSnack('Выберите workspace проекта в Project Control Center.');
      return null;
    }
    final group = _familyGroupForConversation(store, _activeConversationKey);
    final contextPack = await store.repository.api.fetchProjectChatContext(
      actorProfile: store.owner.value,
      actorPhone: _currentProfilePhone,
      projectId: project.id,
      conversationKey: _activeConversationKey,
      workspaceId: workspaceId,
    );
    final ticket = await store.repository.api.requestProjectChatAgentTicket(
      actorProfile: store.owner.value,
      actorPhone: _currentProfilePhone,
      projectId: project.id,
      conversationKey: _activeConversationKey,
      workspaceId: workspaceId,
      requestedMode: contextPack.automation.defaultAgentMode,
    );
    return _ProjectChatAgentRequest(
      workspaceId: workspaceId,
      contextPack: contextPack,
      policyTicket: ticket.policyTicket,
      groupId: group?.id ?? '',
      userMessage: userMessage,
    );
  }

  Future<void> _queueProjectChatAgentPrompt({
    required String workspaceId,
    required TaskProject project,
    required ProjectChatContextPack contextPack,
    required String policyTicket,
    required String prompt,
    String title = '',
  }) async {
    final bridge = _ensureProjectChatAgentBridge();
    bridge.updatePolicyTicket(policyTicket);
    _pendingProjectChatAgentWorkspaceId = workspaceId;
    _pendingProjectChatAgentPrompt = prompt;
    bridge.createSession(
      workspaceId,
      title: title.trim().isEmpty ? 'Тудушкер: ${project.name}' : title.trim(),
      taskCard: {
        'scope': 'project_chat',
        'project_id': project.id,
        'conversation_key': _activeConversationKey,
        'workspace_id': workspaceId,
        'actor_profile': _store?.owner.value ?? '',
        'actor_phone': _currentProfilePhone,
        'mode': contextPack.automation.defaultAgentMode,
        'policy_ticket': policyTicket,
      },
    );
    await bridge.connect();
  }

  Future<String> _runProjectChatAgentPrompt({
    required String workspaceId,
    required TaskProject project,
    required ProjectChatContextPack contextPack,
    required String policyTicket,
    required String prompt,
    String title = '',
  }) async {
    final runner = _ensureProjectChatAgentRunner();
    return runner.run(
      workspaceId: workspaceId,
      title: title.trim().isEmpty ? 'Тудушкер: ${project.name}' : title.trim(),
      policyTicket: policyTicket,
      prompt: prompt,
      taskCard: {
        'scope': 'project_chat',
        'project_id': project.id,
        'conversation_key': _activeConversationKey,
        'workspace_id': workspaceId,
        'actor_profile': _store?.owner.value ?? '',
        'actor_phone': _currentProfilePhone,
        'mode': contextPack.automation.defaultAgentMode,
        'policy_ticket': policyTicket,
      },
    );
  }

  ProjectChatAgentBridgeRunner _ensureProjectChatAgentRunner() {
    final existing = _projectChatAgentRunner;
    if (existing != null) {
      return existing;
    }
    final runner = ProjectChatAgentBridgeRunner(
      onSessionLinked: (sessionId) {
        _projectChatAgentSessionId = sessionId;
      },
      onStatusChange: (connected, status) {
        debugPrint('[project-chat-agent] $status');
      },
    );
    _projectChatAgentRunner = runner;
    return runner;
  }

  CodeWhaleBridgeService _ensureProjectChatAgentBridge() {
    final existing = _projectChatAgentBridge;
    if (existing != null) {
      return existing;
    }
    final bridge = CodeWhaleBridgeService(
      onMessage: (message) {
        if (message.isError) {
          _completeProjectChatAgentResponse(
            error: StateError(
              message.error.isEmpty ? 'Ошибка CodeWhale' : message.error,
            ),
          );
          return;
        }
        final session = message.session;
        if (session != null) {
          _projectChatAgentSessionId = session.id;
          final prompt = _pendingProjectChatAgentPrompt.trim();
          final workspaceId = _pendingProjectChatAgentWorkspaceId.trim();
          if (prompt.isNotEmpty && workspaceId.isNotEmpty) {
            _pendingProjectChatAgentPrompt = '';
            _bridgeSendProjectChatPrompt(workspaceId, session.id, prompt);
          }
          return;
        }
        if (message.type == 'assistant_delta') {
          if (_projectChatAgentResponseCompleter != null) {
            _projectChatAgentResponseBuffer.write(message.text);
          }
          return;
        }
        if (message.type == 'session_task') {
          if (_isProjectChatBridgeTaskDone(message.taskStatus)) {
            if (_projectChatAgentResponseCompleter != null &&
                message.taskResultSummary.trim().isNotEmpty) {
              _projectChatAgentResponseBuffer.write(message.taskResultSummary);
            }
            _completeProjectChatAgentResponse();
          }
          return;
        }
        if (message.type == 'session_stream_done') {
          _completeProjectChatAgentResponse();
          return;
        }
        if (message.type == 'output' && message.text.trim().isNotEmpty) {
          if (_projectChatAgentResponseCompleter != null) {
            _projectChatAgentResponseBuffer.write(message.text);
          }
        }
      },
      onStatusChange: (connected, status) {
        debugPrint('[project-chat-agent] $status');
      },
    );
    _projectChatAgentBridge = bridge;
    return bridge;
  }

  bool _isProjectChatBridgeTaskDone(String status) {
    return const {
      'completed',
      'succeeded',
      'success',
      'failed',
      'canceled',
      'cancelled',
    }.contains(status.trim().toLowerCase());
  }

  void _completeProjectChatAgentResponse({Object? error}) {
    final completer = _projectChatAgentResponseCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    if (error != null) {
      completer.completeError(error);
      return;
    }
    completer.complete(_projectChatAgentResponseBuffer.toString());
    _projectChatAgentResponseBuffer = StringBuffer();
  }

  void _bridgeSendProjectChatPrompt(
    String workspaceId,
    String sessionId,
    String prompt,
  ) {
    final bridge = _projectChatAgentBridge;
    if (bridge == null) {
      return;
    }
    bridge.startSession(workspaceId, sessionId);
    bridge.sendSessionMessage(workspaceId, sessionId, prompt);
  }

  Future<void> _showChatTaskDraftPreview({
    required TaskStore store,
    required ChatTaskDraft draft,
    required TaskProject project,
    required String groupId,
  }) async {
    final editedDraft = await showModalBottomSheet<ChatTaskDraft>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return ChatTaskDraftEditorSheet(
          initialDraft: draft,
          onCancel: () => Navigator.of(sheetContext).pop(),
          onConfirm: (value) => Navigator.of(sheetContext).pop(value),
        );
      },
    );
    if (editedDraft == null) {
      return;
    }
    final result = await store.saveDraftWithResult(
      draft: editedDraft.toTaskDraft(projectId: project.id, groupId: groupId),
    );
    if (result.error != null) {
      _showSnack(result.error!);
      return;
    }
    await _safeSyncDelta(store, showErrors: true);
    _showSnack('Задача создана в проекте ${project.name}.');
  }

  Future<void> _handleProjectChatAgentMention(
    TaskStore store,
    TaskProject project,
    String userMessage,
  ) async {
    try {
      final request = await _prepareProjectChatAgentRequest(
        store: store,
        project: project,
        userMessage: userMessage,
      );
      if (request == null) {
        return;
      }
      final directive = await ProjectChatAgentService.resolveDirective(
        context: request.contextPack,
        userMessage: userMessage,
        runPrompt: (prompt) {
          return _runProjectChatAgentPrompt(
            workspaceId: request.workspaceId,
            project: project,
            contextPack: request.contextPack,
            policyTicket: request.policyTicket,
            prompt: prompt,
            title: 'Тудушкер: ${project.name}',
          );
        },
      );
      if (!mounted) {
        return;
      }
      await _applyProjectChatAgentDirective(
        store: store,
        project: project,
        contextPack: request.contextPack,
        directive: directive,
        groupId: request.groupId,
        policyTicket: request.policyTicket,
      );
    } catch (e, st) {
      if (e is ProjectChatAgentRequestCancelled) {
        return;
      }
      if (e is ProjectChatAgentInvalidResponse) {
        await _sendProjectChatAgentMessage(
          store,
          'Я получил неструктурированный ответ модели и не стал отправлять его в чат. Повторите запрос чуть точнее.',
        );
        return;
      }
      debugPrint('[project-chat-agent] mention error: $e\n$st');
      await _sendProjectChatAgentMessage(
        store,
        'Не смог обработать запрос. Проверьте workspace проекта и доступность CodeWhale.',
      );
    }
  }

  Future<void> _applyProjectChatAgentDirective({
    required TaskStore store,
    required TaskProject project,
    required ProjectChatContextPack contextPack,
    required ProjectChatAgentDirective directive,
    required String groupId,
    String policyTicket = '',
  }) async {
    switch (directive.action) {
      case ProjectChatAgentAction.taskDraft:
        final draft = directive.draft;
        if (draft == null) {
          await _sendProjectChatAgentMessage(
            store,
            'Я понял, что нужна карточка, но не смог собрать структурированный черновик.',
          );
          return;
        }
        await _showChatTaskDraftPreview(
          store: store,
          draft: draft,
          project: project,
          groupId: groupId,
        );
        return;
      case ProjectChatAgentAction.startAgent:
        final launchPrompt = directive.launchPrompt.trim().isNotEmpty
            ? directive.launchPrompt.trim()
            : contextPack.toPrompt();
        await _queueProjectChatAgentPrompt(
          workspaceId: contextPack.workspaceId.trim().isNotEmpty
              ? contextPack.workspaceId.trim()
              : contextPack.automation.primaryWorkspaceId,
          project: project,
          contextPack: contextPack,
          policyTicket: policyTicket,
          prompt: launchPrompt,
          title: 'Работа агента: ${project.name}',
        );
        await _sendProjectChatAgentMessage(
          store,
          'Запустил рабочую сессию в workspace проекта.',
        );
        return;
      case ProjectChatAgentAction.status:
      case ProjectChatAgentAction.clarify:
      case ProjectChatAgentAction.reply:
        final text = directive.replyText.trim().isNotEmpty
            ? directive.replyText.trim()
            : 'Я посмотрел контекст, но не смог сформулировать полезный ответ.';
        await _sendProjectChatAgentMessage(store, text);
        return;
    }
  }

  Future<void> _sendProjectChatAgentMessage(
    TaskStore store,
    String text,
  ) async {
    final clean = text.trim();
    if (clean.isEmpty) {
      return;
    }
    final conversationKey = _activeConversationKey;
    try {
      final message = await store.repository.api.chatSendMessage(
        actorProfile: 'tudushker',
        conversationKey: conversationKey,
        messageType: 'text',
        text: clean,
        clientMessageId: 'tudushker-${DateTime.now().microsecondsSinceEpoch}',
      );
      await store.repository.db.upsertMessages([message]);
      final messages = List<ChatMessage>.from(
        _chatMessagesByConversation[conversationKey] ?? const [],
      )..add(message);
      _chatMessagesByConversation[conversationKey] = messages;
      if (mounted) {
        setState(() {});
      }
    } catch (error, stackTrace) {
      debugPrint('[project-chat-agent] bot send failed: $error\n$stackTrace');
      try {
        final fallback = await store.repository.api.chatSendMessage(
          actorProfile: store.owner.value,
          conversationKey: conversationKey,
          messageType: 'text',
          text: 'Тудушкер: $clean',
          clientMessageId:
              'tudushker-fallback-${DateTime.now().microsecondsSinceEpoch}',
        );
        await store.repository.db.upsertMessages([fallback]);
        final messages = List<ChatMessage>.from(
          _chatMessagesByConversation[conversationKey] ?? const [],
        )..add(fallback);
        _chatMessagesByConversation[conversationKey] = messages;
        if (mounted) {
          setState(() {});
        }
      } catch (fallbackError, fallbackStackTrace) {
        debugPrint(
          '[project-chat-agent] owner fallback send failed: '
          '$fallbackError\n$fallbackStackTrace',
        );
        await _appendLocalProjectChatAgentMessage(
          store: store,
          conversationKey: conversationKey,
          text: clean,
        );
      }
    }
  }

  Future<void> _appendLocalProjectChatAgentMessage({
    required TaskStore store,
    required String conversationKey,
    required String text,
  }) async {
    final message = ChatMessage(
      id: 'local-tudushker-${DateTime.now().microsecondsSinceEpoch}',
      conversationKey: conversationKey,
      senderProfile: 'tudushker',
      messageType: 'text',
      text: text,
      createdAt: DateTime.now().toIso8601String(),
      clientMessageId:
          'local-tudushker-${DateTime.now().microsecondsSinceEpoch}',
      deliveryStatus: 'failed',
    );
    try {
      await store.repository.db.upsertMessages([message]);
    } catch (error, stackTrace) {
      debugPrint(
        '[project-chat-agent] local fallback persist failed: $error\n$stackTrace',
      );
    }
    final messages = List<ChatMessage>.from(
      _chatMessagesByConversation[conversationKey] ?? const [],
    )..add(message);
    _chatMessagesByConversation[conversationKey] = messages;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showProjectChatStatus(
    TaskStore store,
    TaskProject project,
  ) async {
    final group = _familyGroupForConversation(store, _activeConversationKey);
    final workspaceId = await _workspaceIdForProjectChat(store, project);
    if (!mounted) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Статус проекта',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined),
                title: Text(project.name),
                subtitle: Text(
                  project.description.isEmpty
                      ? 'Описание не задано'
                      : project.description,
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.forum_outlined),
                title: Text(group?.name ?? _activeConversationKey),
                subtitle: Text(
                  'Участники: ${(group?.members ?? const <String>[]).join(', ')}',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.workspaces_outline),
                title: Text(
                  workspaceId.isEmpty ? 'Workspace не выбран' : workspaceId,
                ),
                subtitle: Text(
                  workspaceId.isEmpty
                      ? 'Выберите workspace в Project Control Center'
                      : _accessPolicy.canUseAi
                          ? 'Агент доступен по кнопке'
                          : 'Нет прав на AI-агента',
                ),
              ),
              if (_projectChatAgentSessionId.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.smart_toy_outlined),
                  title: const Text('Активная сессия агента'),
                  subtitle: Text(_projectChatAgentSessionId),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ── Chat message helpers ────────────────────────────────────

  String chatMessageText(ChatMessage message) {
    if (message.isDeleted) {
      return 'Сообщение удалено';
    }
    if (message.messageType == 'image' ||
        message.messageType == 'image_group') {
      return message.text.isNotEmpty ? message.text : 'Фото';
    }
    if (message.messageType == 'video' ||
        message.messageType == 'video_group') {
      return message.text.isNotEmpty ? message.text : 'Видео';
    }
    if (message.messageType == 'audio') {
      return message.text.isNotEmpty ? message.text : 'Аудио';
    }
    if (message.messageType == 'voice') {
      return message.text.isNotEmpty ? message.text : 'Голосовое сообщение';
    }
    if (message.messageType == 'sticker') {
      final explicitText = message.text.trim();
      if (explicitText.isNotEmpty) {
        return explicitText;
      }
      final item = _stickerItemForMessage(message);
      if (item != null && item.title.trim().isNotEmpty) {
        return item.title.trim();
      }
      return 'Стикер недоступен';
    }
    return message.text;
  }

  String chatStickerAssetUrl(ChatMessage message) {
    if (message.messageType != 'sticker') {
      return '';
    }
    final raw = primaryChatMediaUrl(message);
    if (raw.isNotEmpty) {
      return raw.startsWith('http') ? raw : AvatarUrlResolver.resolveUrl(raw);
    }
    final item = _stickerItemForMessage(message);
    if (item == null || _isLegacyStickerAsset(item.assetUrl)) {
      return '';
    }
    return _absoluteStickerAssetUrl(item.assetUrl);
  }

  StickerItem? _stickerItemForMessage(ChatMessage message) {
    final stickerId = message.stickerId?.trim() ?? '';
    if (stickerId.isEmpty) {
      return null;
    }
    for (final pack in _chatStickerPacks) {
      for (final item in pack.items) {
        if (item.stickerId == stickerId) {
          return item;
        }
      }
    }
    return null;
  }

  bool _isLegacyStickerAsset(String raw) {
    final value = raw.trim();
    return value.isEmpty ||
        value.startsWith('emoji://') ||
        value.startsWith('/stickers/default/');
  }

  String _absoluteStickerAssetUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty ||
        value.startsWith('http://') ||
        value.startsWith('https://')) {
      return value;
    }
    if (!value.startsWith('/')) {
      return value;
    }
    final baseUrl = _store?.repository.api.baseUrl.trim() ?? '';
    if (baseUrl.isEmpty) {
      return value;
    }
    return '${baseUrl.replaceFirst(RegExp(r'/+$'), '')}$value';
  }

  String chatImageUrl(ChatMessage message) {
    if (message.messageType != 'image' &&
        message.messageType != 'voice' &&
        message.messageType != 'audio') {
      return '';
    }
    final raw = primaryChatMediaUrl(message);
    if (raw.isNotEmpty) {
      return raw.startsWith('http') ? raw : AvatarUrlResolver.resolveUrl(raw);
    }
    return '';
  }
}

class _ProjectChatAgentRequest {
  const _ProjectChatAgentRequest({
    required this.workspaceId,
    required this.contextPack,
    required this.policyTicket,
    required this.groupId,
    required this.userMessage,
  });

  final String workspaceId;
  final ProjectChatContextPack contextPack;
  final String policyTicket;
  final String groupId;
  final String userMessage;
}
