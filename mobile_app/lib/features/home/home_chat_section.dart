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
      onBackToContacts: _clearActiveConversation,
      onOpenConversation: (conversationKey) =>
          _openConversation(store, conversationKey),
      onOpenMessageActions: (message) => _openMessageActions(store, message),
      onImageTap: _openPhotoViewer,
      hasMoreOlderMessages: _activeConversationKey.isNotEmpty &&
          (_chatOlderCursors[_activeConversationKey]?.isNotEmpty ?? false) &&
          !_chatOlderExhausted.contains(_activeConversationKey),
      loadingOlderMessages: _chatOlderLoading.contains(_activeConversationKey),
      onLoadOlderMessages: () => _loadOlderChatMessages(store),
      onClearReply: _clearChatReply,
      onCancelEdit: _cancelChatEdit,
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
    final labels = _projectChatAgentLabels;
    try {
      final request = await _prepareProjectChatAgentRequest(
        store: store,
        project: project,
        userMessage: labels.draftButtonUserMessage,
      );
      if (request == null) {
        return;
      }
      _showSnack(labels.analyzingChat);
      final directive = await ProjectChatAgentService.resolveDirective(
        context: request.contextPack,
        userMessage: request.userMessage,
        forcedAction: ProjectChatAgentAction.taskDraft,
        fallbackMessages: ProjectChatAgentFallbackMessages(
          replyText: labels.aiUnavailableReplyMessage,
          taskDraftReplyText: labels.aiUnavailableTaskDraftMessage,
        ),
        runPrompt: (prompt) {
          return _runProjectChatAgentPrompt(
            workspaceId: request.workspaceId,
            project: project,
            contextPack: request.contextPack,
            policyTicket: request.policyTicket,
            prompt: prompt,
            title: labels.agentTitle(project.name),
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
        _showSnack(labels.unstructuredResponseSnack);
        return;
      }
      debugPrint('[project-chat-agent] analyze error: $e\n$st');
      _showSnack(labels.analyzeFailed);
    }
  }

  Future<void> _startProjectChatAgent(
    TaskStore store,
    TaskProject project,
  ) async {
    final labels = _projectChatAgentLabels;
    final workspaceId = await _workspaceIdForProjectChat(store, project);
    if (workspaceId.isEmpty) {
      _showSnack(labels.selectProjectWorkspace);
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
        title: labels.agentTitle(project.name),
      );
      _showSnack(labels.agentStarting);
    } catch (e, st) {
      debugPrint('[project-chat-agent] start error: $e\n$st');
      _showSnack(labels.agentStartFailed);
    }
  }

  Future<_ProjectChatAgentRequest?> _prepareProjectChatAgentRequest({
    required TaskStore store,
    required TaskProject project,
    required String userMessage,
  }) async {
    final labels = _projectChatAgentLabels;
    final workspaceId = await _workspaceIdForProjectChat(store, project);
    if (workspaceId.isEmpty) {
      _showSnack(labels.selectProjectWorkspace);
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
    final labels = _projectChatAgentLabels;
    _pendingProjectChatAgentWorkspaceId = workspaceId;
    _pendingProjectChatAgentPrompt = prompt;
    bridge.createSession(
      workspaceId,
      title:
          title.trim().isEmpty ? labels.agentTitle(project.name) : title.trim(),
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
    final labels = _projectChatAgentLabels;
    return runner.run(
      workspaceId: workspaceId,
      title:
          title.trim().isEmpty ? labels.agentTitle(project.name) : title.trim(),
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
    final labels = _projectChatAgentLabels;
    final runner = ProjectChatAgentBridgeRunner(
      unavailableMessage: labels.codeWhaleUnavailable,
      codeWhaleErrorFallback: labels.codeWhaleErrorFallback,
      defaultSessionTitle: labels.defaultAgentTitle,
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
        final labels = _projectChatAgentLabels;
        if (message.isError) {
          _completeProjectChatAgentResponse(
            error: StateError(
              message.error.isEmpty
                  ? labels.codeWhaleErrorFallback
                  : message.error,
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
    _showSnack(_projectChatAgentLabels.taskCreatedInProject(project.name));
  }

  Future<void> _handleProjectChatAgentMention(
    TaskStore store,
    TaskProject project,
    String userMessage,
  ) async {
    final labels = _projectChatAgentLabels;
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
        fallbackMessages: ProjectChatAgentFallbackMessages(
          replyText: labels.aiUnavailableReplyMessage,
          taskDraftReplyText: labels.aiUnavailableTaskDraftMessage,
        ),
        runPrompt: (prompt) {
          return _runProjectChatAgentPrompt(
            workspaceId: request.workspaceId,
            project: project,
            contextPack: request.contextPack,
            policyTicket: request.policyTicket,
            prompt: prompt,
            title: labels.agentTitle(project.name),
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
          labels.unstructuredResponseMessage,
        );
        return;
      }
      debugPrint('[project-chat-agent] mention error: $e\n$st');
      await _sendProjectChatAgentMessage(
        store,
        labels.requestFailedMessage,
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
    final labels = _projectChatAgentLabels;
    switch (directive.action) {
      case ProjectChatAgentAction.taskDraft:
        final draft = directive.draft;
        if (draft == null) {
          await _sendProjectChatAgentMessage(
            store,
            labels.taskDraftMissingMessage,
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
          title: labels.agentTitle(project.name),
        );
        await _sendProjectChatAgentMessage(
          store,
          labels.agentSessionStartedMessage,
        );
        return;
      case ProjectChatAgentAction.status:
      case ProjectChatAgentAction.clarify:
      case ProjectChatAgentAction.reply:
        final text = directive.replyText.trim().isNotEmpty
            ? directive.replyText.trim()
            : labels.emptyReplyMessage;
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
        _markChatMessagesChanged();
      }
    } catch (error, stackTrace) {
      debugPrint('[project-chat-agent] bot send failed: $error\n$stackTrace');
      try {
        final fallback = await store.repository.api.chatSendMessage(
          actorProfile: store.owner.value,
          conversationKey: conversationKey,
          messageType: 'text',
          text: _projectChatAgentLabels.ownerFallbackMessage(clean),
          clientMessageId:
              'tudushker-fallback-${DateTime.now().microsecondsSinceEpoch}',
        );
        await store.repository.db.upsertMessages([fallback]);
        final messages = List<ChatMessage>.from(
          _chatMessagesByConversation[conversationKey] ?? const [],
        )..add(fallback);
        _chatMessagesByConversation[conversationKey] = messages;
        if (mounted) {
          _markChatMessagesChanged();
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
      _markChatMessagesChanged();
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
      builder: (_) {
        return ProjectChatStatusSheet(
          project: project,
          conversationTitle: group?.name ?? _activeConversationKey,
          members: group?.members ?? const <String>[],
          workspaceId: workspaceId,
          canUseAi: _accessPolicy.canUseAi,
          agentSessionId: _projectChatAgentSessionId,
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
    final l10n = AppLocalizations.of(context);
    if (message.isDeleted) {
      return l10n?.messageDeleted ?? 'Message deleted';
    }
    if (message.messageType == 'image' ||
        message.messageType == 'image_group') {
      return message.text.isNotEmpty
          ? message.text
          : (l10n?.imageMessage ?? 'Image');
    }
    if (message.messageType == 'video' ||
        message.messageType == 'video_group') {
      return message.text.isNotEmpty ? message.text : 'Video';
    }
    if (message.messageType == 'audio') {
      return message.text.isNotEmpty
          ? message.text
          : (l10n?.audioMessage ?? 'Audio');
    }
    if (message.messageType == 'voice') {
      return message.text.isNotEmpty
          ? message.text
          : (l10n?.voiceMessage ?? 'Voice message');
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
      return l10n?.stickerUnavailable ?? 'Sticker unavailable';
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

  String _conversationLabel(ChatConversation conversation, String actor) {
    if (conversation.kind == 'group' ||
        conversation.conversationKey == 'group:common') {
      final title = conversation.title.trim();
      return title.isNotEmpty ? title : 'Group';
    }
    final peer = conversation.members.firstWhere(
      (item) => item != actor,
      orElse: () => '',
    );
    if (peer.isNotEmpty) {
      return _profileLabel(peer);
    }

    final fromContacts = _chatContacts
        .where((item) => item.conversationKey == conversation.conversationKey)
        .toList();
    if (fromContacts.isNotEmpty) {
      return contactLabel(fromContacts.first);
    }
    return conversation.conversationKey;
  }

  List<ChatContact> _allKnownContacts(TaskStore store) {
    final seen = <String>{};
    final result = <ChatContact>[];
    final self = ChatContact(
      profileKey: store.owner.value,
      displayName: _profileLabel(store.owner.value),
      phone: _currentProfilePhone,
      conversationKey: '',
      avatarUrl: _currentProfileAvatarUrl,
    );
    result.add(self);
    seen.add(self.profileKey);
    for (final member in _familyMembers) {
      if (seen.add(member.profileKey)) result.add(member);
    }
    for (final contact in _chatContacts) {
      if (seen.add(contact.profileKey)) result.add(contact);
    }
    for (final contact in _phoneContacts) {
      if (seen.add(contact.profileKey)) result.add(contact);
    }
    return result;
  }

  String? _avatarForProfile(String profile) {
    final store = _store;
    if (store == null) return null;
    if (profile == store.owner.value) return _currentProfileAvatarUrl;
    final cached = _profileAvatarUrls[profile];
    if (cached != null && cached.isNotEmpty) return cached;
    for (final contact in [..._chatContacts, ..._familyMembers]) {
      if (contact.profileKey == profile &&
          contact.avatarUrl != null &&
          contact.avatarUrl!.isNotEmpty) {
        _profileAvatarUrls[profile] = contact.avatarUrl!;
        return contact.avatarUrl;
      }
    }
    return null;
  }

  Future<void> _saveAvatarUrlsFromContacts(List<ChatContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    for (final contact in contacts) {
      final url = contact.avatarUrl;
      if (url != null && url.isNotEmpty) {
        await prefs.setString('avatar_${contact.profileKey}', url);
      }
    }
  }

  Future<void> _loadProfileAvatars(Iterable<String> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    for (final raw in profiles) {
      final profile = raw.trim();
      if (profile.isEmpty) continue;
      final avatar = prefs.getString('avatar_$profile')?.trim() ?? '';
      if (avatar.isNotEmpty) {
        _profileAvatarUrls[profile] = avatar;
      }
    }
  }

  String _groupLabel(String groupId) {
    final store = _store;
    if (store == null) return groupId;
    final group = store.familyGroups.value.cast<FamilyGroup?>().firstWhere(
          (group) => group?.id == groupId,
          orElse: () => null,
        );
    return group?.name ?? groupId;
  }

  String _profileLabel(String profile) {
    for (final contact in [
      ..._chatContacts,
      ..._phoneContacts,
      ..._familyMembers,
    ]) {
      if (contact.profileKey == profile &&
          contact.displayName.trim().isNotEmpty) {
        return contact.displayName.trim();
      }
    }
    if (profile == (_store?.owner.value ?? '') &&
        _currentProfileDisplayName.trim().isNotEmpty) {
      return _currentProfileDisplayName.trim();
    }
    return profileLabel(profile);
  }

  Future<void> _saveImageToGallery(String url) async {
    try {
      const channel = MethodChannel('family_todo_mobile/share');
      await channel.invokeMethod<bool>('saveImage', {'url': url});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_projectChatAgentLabels.imageSavedToGallery)),
        );
      }
    } catch (e, st) {
      debugPrint('[gallery] save photo error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_projectChatAgentLabels.imageSaveFailed)),
        );
      }
    }
  }

  void _openPhotoViewer(ChatMessage message, int initialIndex) {
    showChatPhotoViewer(
      context: context,
      urls: _messageImageUrls(message),
      initialIndex: initialIndex,
      onSaveImage: _saveImageToGallery,
    );
  }

  List<String> _messageImageUrls(ChatMessage message) {
    final attachments = message.attachments
        .where((item) => item.kind == 'image' && item.assetUrl.isNotEmpty)
        .map((item) => _absoluteAssetUrl(item.assetUrl))
        .where((item) => item.isNotEmpty)
        .toList();
    if (attachments.isNotEmpty) {
      return attachments;
    }
    final single = chatImageUrl(message);
    return single.isEmpty ? const [] : [single];
  }

  String _absoluteAssetUrl(String raw) {
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
