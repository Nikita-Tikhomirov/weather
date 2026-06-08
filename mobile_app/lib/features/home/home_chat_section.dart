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
    final workspaceId = await _workspaceIdForProjectChat(store, project);
    if (workspaceId.isEmpty) {
      _showSnack('Выберите workspace проекта в Project Control Center.');
      return;
    }
    try {
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
      await _queueProjectChatAgentPrompt(
        workspaceId: workspaceId,
        project: project,
        contextPack: contextPack,
        policyTicket: ticket.policyTicket,
      );
      final draft = _draftFromProjectChatContext(contextPack);
      if (!mounted) {
        return;
      }
      await _showChatTaskDraftPreview(
        store: store,
        draft: draft,
        project: project,
        groupId: group?.id ?? '',
      );
    } catch (e, st) {
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
      );
      _showSnack('Агент проекта запускается в CodeWhale.');
    } catch (e, st) {
      debugPrint('[project-chat-agent] start error: $e\n$st');
      _showSnack('Не удалось запустить агента проекта.');
    }
  }

  Future<void> _queueProjectChatAgentPrompt({
    required String workspaceId,
    required TaskProject project,
    required ProjectChatContextPack contextPack,
    required String policyTicket,
  }) async {
    final bridge = _ensureProjectChatAgentBridge();
    bridge.updatePolicyTicket(policyTicket);
    _pendingProjectChatAgentWorkspaceId = workspaceId;
    _pendingProjectChatAgentPrompt = contextPack.toPrompt();
    bridge.createSession(
      workspaceId,
      title: 'Анализ чата: ${project.name}',
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

  CodeWhaleBridgeService _ensureProjectChatAgentBridge() {
    final existing = _projectChatAgentBridge;
    if (existing != null) {
      return existing;
    }
    final bridge = CodeWhaleBridgeService(
      onMessage: (message) {
        final session = message.session;
        if (session != null) {
          _projectChatAgentSessionId = session.id;
          final prompt = _pendingProjectChatAgentPrompt.trim();
          final workspaceId = _pendingProjectChatAgentWorkspaceId.trim();
          if (prompt.isNotEmpty && workspaceId.isNotEmpty) {
            _pendingProjectChatAgentPrompt = '';
            _bridgeSendProjectChatPrompt(workspaceId, session.id, prompt);
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

  ChatTaskDraft _draftFromProjectChatContext(ProjectChatContextPack context) {
    final textMessages =
        context.messages.where((message) => message.text.trim().isNotEmpty);
    final sourceIds = textMessages.map((message) => message.id).toList();
    final actionItems = <String>[];
    for (final message in textMessages) {
      final text = message.text.trim();
      if (text.isEmpty) {
        continue;
      }
      actionItems.add('${message.senderProfile}: $text');
    }
    final titleSource = actionItems.isEmpty
        ? 'Задача из чата'
        : actionItems.last.replaceFirst(RegExp(r'^[^:]+:\s*'), '');
    final title = titleSource.length > 80
        ? '${titleSource.substring(0, 77)}...'
        : titleSource;
    return ChatTaskDraft(
      title: title,
      summary: 'Черновик создан из последних сообщений чата проекта.',
      actionItems: actionItems.take(8).toList(),
      sourceMessageIds: sourceIds.take(12).toList(),
    );
  }

  Future<void> _showChatTaskDraftPreview({
    required TaskStore store,
    required ChatTaskDraft draft,
    required TaskProject project,
    required String groupId,
  }) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Черновик задачи',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                draft.title,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: Text(draft.composedDetails),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    key: const ValueKey('chat-draft-cancel'),
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: const Text('Отмена'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    key: const ValueKey('chat-draft-confirm'),
                    icon: const Icon(Icons.check),
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    label: const Text('Создать задачу'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    final result = await store.saveDraftWithResult(
      draft: draft.toTaskDraft(projectId: project.id, groupId: groupId),
    );
    if (result.error != null) {
      _showSnack(result.error!);
      return;
    }
    await _safeSyncDelta(store, showErrors: true);
    _showSnack('Задача создана в проекте ${project.name}.');
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
