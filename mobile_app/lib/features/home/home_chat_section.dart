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
      onCallTap: () => _startCallOutgoing(callType: 'audio'),
      onVideoCallTap: () => _startCallOutgoing(callType: 'video'),
      typingUsers: _typingUsers,
      onStartRecord: () => _voiceRecorder?.startRecord(),
      onStopRecord: () => _voiceRecorder?.stopRecord(),
      onSendText: () => _sendTextMessage(store),
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
