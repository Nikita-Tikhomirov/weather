import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../models/call_models.dart';
import '../../models/chat_models.dart';
import '../../models/task_project.dart';
import '../../services/call_service.dart';
import '../../shared/utils/avatar_url_resolver.dart';
import 'active_call_banner.dart';
import 'chat_messages_list.dart';

class MessengerPage extends StatelessWidget {
  const MessengerPage({
    super.key,
    required this.conversations,
    required this.contacts,
    required this.messages,
    required this.activeConversationKey,
    required this.owner,
    required this.compact,
    required this.chatInputController,
    required this.replyToMessage,
    required this.editingMessageId,
    required this.isRecording,
    required this.conversationLabel,
    required this.contactLabel,
    required this.chatMessageText,
    required this.profileLabel,
    required this.stickerAssetFor,
    required this.imageUrlFor,
    required this.onRefreshContacts,
    required this.onCreateGroup,
    required this.onAddContactToFamily,
    required this.onOpenDirectContact,
    required this.onOpenWorkspaces,
    required this.onBackToContacts,
    required this.onOpenConversation,
    required this.onOpenMessageActions,
    required this.onImageTap,
    required this.hasMoreOlderMessages,
    required this.loadingOlderMessages,
    required this.onLoadOlderMessages,
    required this.onClearReply,
    required this.onCancelEdit,
    required this.onOpenAttachMenu,
    required this.onStartRecord,
    required this.onStopRecord,
    required this.onSendText,
    required this.onManageGroup,
    this.typingUsers = const {},
    this.avatarForContact,
    this.onCallTap,
    this.onVideoCallTap,
    this.activeCallSession,
    this.activeCallState = CallState.idle,
    this.onOpenActiveCall,
    this.onEndActiveCall,
    this.onAcceptActiveCall,
    this.activeProject,
    this.onAnalyzeProjectChat,
    this.onDraftProjectTask,
    this.onStartProjectAgent,
    this.onShowProjectStatus,
  });

  final List<ChatConversation> conversations;
  final List<ChatContact> contacts;
  final List<ChatMessage> messages;
  final String activeConversationKey;
  final String owner;
  final bool compact;
  final TextEditingController chatInputController;
  final ChatMessage? replyToMessage;
  final String? editingMessageId;
  final bool isRecording;
  final String Function(ChatConversation conversation, String actor)
      conversationLabel;
  final String Function(ChatContact contact) contactLabel;
  final String Function(ChatMessage message) chatMessageText;
  final String Function(String profile) profileLabel;
  final String Function(ChatMessage message) stickerAssetFor;
  final String Function(ChatMessage message) imageUrlFor;
  final VoidCallback onRefreshContacts;
  final VoidCallback onCreateGroup;
  final void Function(ChatContact contact) onAddContactToFamily;
  final void Function(ChatContact contact) onOpenDirectContact;
  final VoidCallback onOpenWorkspaces;
  final String? Function(String profileKey)? avatarForContact;
  final VoidCallback onBackToContacts;
  final void Function(String conversationKey) onOpenConversation;
  final void Function(ChatMessage message) onOpenMessageActions;
  final void Function(ChatMessage message, int index) onImageTap;
  final VoidCallback onClearReply;
  final VoidCallback onCancelEdit;
  final VoidCallback onOpenAttachMenu;
  final VoidCallback onStartRecord;
  final VoidCallback onStopRecord;
  final VoidCallback onSendText;
  final void Function(ChatConversation conv) onManageGroup;
  final bool hasMoreOlderMessages;
  final bool loadingOlderMessages;
  final Future<void> Function() onLoadOlderMessages;
  final Map<String, Set<String>> typingUsers;
  final VoidCallback? onCallTap;
  final VoidCallback? onVideoCallTap;
  final CallSession? activeCallSession;
  final CallState activeCallState;
  final VoidCallback? onOpenActiveCall;
  final VoidCallback? onEndActiveCall;
  final VoidCallback? onAcceptActiveCall;
  final TaskProject? activeProject;
  final VoidCallback? onAnalyzeProjectChat;
  final VoidCallback? onDraftProjectTask;
  final VoidCallback? onStartProjectAgent;
  final VoidCallback? onShowProjectStatus;

  @override
  Widget build(BuildContext context) {
    final activeCallBanner = ActiveCallBanner(
      session: activeCallSession,
      state: activeCallState,
      owner: owner,
      profileLabel: profileLabel,
      onOpen: onOpenActiveCall,
      onEnd: onEndActiveCall,
      onAccept: onAcceptActiveCall,
    );

    if (activeConversationKey.isEmpty) {
      return Column(
        children: [
          activeCallBanner,
          Expanded(
            child: _ContactList(
              contacts: contacts,
              owner: owner,
              contactLabel: contactLabel,
              avatarForContact: avatarForContact,
              typingUsers: typingUsers,
              groupConversations: conversations,
              groupLabel: conversationLabel,
              onRefreshContacts: onRefreshContacts,
              onCreateGroup: onCreateGroup,
              onAddContactToFamily: onAddContactToFamily,
              onOpenDirectContact: onOpenDirectContact,
              onOpenWorkspaces: onOpenWorkspaces,
              onOpenConversation: onOpenConversation,
              onManageGroup: onManageGroup,
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        activeCallBanner,
        _ChatHeader(
          activeConversationKey: activeConversationKey,
          conversations: conversations,
          conversationLabel: conversationLabel,
          owner: owner,
          onBackToContacts: onBackToContacts,
          onCallTap: onCallTap,
          onVideoCallTap: onVideoCallTap,
          activeProject: activeProject,
          onAnalyzeProjectChat: onAnalyzeProjectChat,
          onDraftProjectTask: onDraftProjectTask,
          onStartProjectAgent: onStartProjectAgent,
          onShowProjectStatus: onShowProjectStatus,
        ),
        Expanded(
          child: ChatMessagesList(
            key: ValueKey(activeConversationKey),
            messages: messages,
            owner: owner,
            compact: compact,
            textFor: chatMessageText,
            senderLabelFor: profileLabel,
            stickerAssetFor: stickerAssetFor,
            imageUrlFor: imageUrlFor,
            avatarForContact: avatarForContact,
            onLongPress: onOpenMessageActions,
            onImageTap: onImageTap,
            hasMoreOlder: hasMoreOlderMessages,
            loadingOlder: loadingOlderMessages,
            onLoadOlder: onLoadOlderMessages,
          ),
        ),
        _TypingIndicator(
          conversationKey: activeConversationKey,
          typingUsers: typingUsers,
          owner: owner,
          profileLabel: profileLabel,
        ),
        _ChatComposer(
          chatInputController: chatInputController,
          replyToMessage: replyToMessage,
          editingMessageId: editingMessageId,
          isRecording: isRecording,
          chatMessageText: chatMessageText,
          onClearReply: onClearReply,
          onCancelEdit: onCancelEdit,
          onOpenAttachMenu: onOpenAttachMenu,
          onStartRecord: onStartRecord,
          onStopRecord: onStopRecord,
          onSendText: onSendText,
        ),
      ],
    );
  }
}

class _ContactList extends StatelessWidget {
  const _ContactList({
    required this.contacts,
    required this.owner,
    required this.contactLabel,
    required this.typingUsers,
    required this.onRefreshContacts,
    required this.onCreateGroup,
    required this.onAddContactToFamily,
    required this.onOpenDirectContact,
    required this.onOpenWorkspaces,
    required this.groupConversations,
    required this.groupLabel,
    required this.onOpenConversation,
    required this.onManageGroup,
    this.avatarForContact,
  });

  final List<ChatContact> contacts;
  final String owner;
  final Map<String, Set<String>> typingUsers;
  final List<ChatConversation> groupConversations;
  final String Function(ChatContact contact) contactLabel;
  final String Function(ChatConversation conv, String owner) groupLabel;
  final VoidCallback onRefreshContacts;
  final VoidCallback onCreateGroup;
  final void Function(ChatContact contact) onAddContactToFamily;
  final void Function(ChatContact contact) onOpenDirectContact;
  final VoidCallback onOpenWorkspaces;
  final void Function(String conversationKey) onOpenConversation;
  final void Function(ChatConversation conv) onManageGroup;
  final String? Function(String profileKey)? avatarForContact;

  Widget _buildContactAvatar(ChatContact contact) {
    final url = avatarForContact?.call(contact.profileKey);
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('http') || url.startsWith('/')) {
        return CircleAvatar(
          backgroundImage: NetworkImage(AvatarUrlResolver.resolveUrl(url)),
          onBackgroundImageError: (_, __) {},
        );
      }
      return CircleAvatar(
        backgroundImage: FileImage(File(url)),
        onBackgroundImageError: (_, __) {},
      );
    }
    return const CircleAvatar(child: Icon(Icons.person));
  }

  Widget _buildGroupAvatar(ChatConversation conv) {
    final url = conv.avatarUrl;
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('http') || url.startsWith('/')) {
        return CircleAvatar(
          backgroundImage: NetworkImage(AvatarUrlResolver.resolveUrl(url)),
          onBackgroundImageError: (_, __) {},
        );
      }
      return CircleAvatar(
        backgroundImage: FileImage(File(url)),
        onBackgroundImageError: (_, __) {},
      );
    }
    return const CircleAvatar(child: Icon(Icons.group));
  }

  bool _isGroupConversation(ChatConversation conv) {
    return conv.kind == 'group' ||
        conv.conversationKey == 'group:common' ||
        conv.conversationKey.startsWith('grp:');
  }

  bool _isProjectConversation(ChatConversation conv) {
    return conv.conversationKey.startsWith('grp:project:');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final projectChats = groupConversations
        .where(
          (conv) => _isGroupConversation(conv) && _isProjectConversation(conv),
        )
        .toList();
    final groups = groupConversations
        .where(
          (conv) => _isGroupConversation(conv) && !_isProjectConversation(conv),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n?.contacts ?? 'Контакты',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n?.workspaces ?? 'Рабочие пространства',
                icon: const Icon(Icons.workspaces_outline),
                onPressed: onOpenWorkspaces,
              ),
              IconButton(
                tooltip: l10n?.refreshContacts ?? 'Обновить контакты',
                icon: const Icon(Icons.refresh),
                onPressed: onRefreshContacts,
              ),
              IconButton.filled(
                tooltip: l10n?.createGroupAction ?? 'Создать группу',
                icon: const Icon(Icons.group_add_outlined),
                onPressed: onCreateGroup,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (projectChats.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                  child: Text(
                    l10n?.projectChats ?? 'Проектные чаты',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ...projectChats.map((conv) {
                  return ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.hub_outlined),
                    ),
                    title: Text(groupLabel(conv, owner)),
                    subtitle: Text(
                      l10n?.chatParticipantsCount(conv.members.length) ??
                          'Участники: ${conv.members.length}',
                    ),
                    onTap: () => onOpenConversation(conv.conversationKey),
                  );
                }),
                const Divider(height: 24),
              ],
              if (groups.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                  child: Text(
                    projectChats.isEmpty
                        ? l10n?.groups ?? 'Группы'
                        : l10n?.regularGroups ?? 'Обычные группы',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ...groups.map((conv) {
                  return ListTile(
                    leading: _buildGroupAvatar(conv),
                    title: Text(groupLabel(conv, owner)),
                    onTap: () => onOpenConversation(conv.conversationKey),
                    onLongPress: () => onManageGroup(conv),
                  );
                }),
                const Divider(height: 24),
              ],
              if (contacts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Нет зарегистрированных контактов из телефона'),
                )
              else
                ...List.generate(contacts.length, (index) {
                  final contact = contacts[index];
                  final typing = typingUsers[contact.conversationKey]
                          ?.where((profile) => profile != owner)
                          .isNotEmpty ==
                      true;
                  return ListTile(
                    leading: _buildContactAvatar(contact),
                    title: Text(contactLabel(contact)),
                    subtitle: Text(
                      typing ? 'печатает...' : contact.phone,
                      style: typing
                          ? TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            )
                          : null,
                    ),
                    trailing: IconButton(
                      tooltip: 'Добавить в семью',
                      icon: const Icon(Icons.family_restroom_outlined),
                      onPressed: () => onAddContactToFamily(contact),
                    ),
                    onTap: () => onOpenDirectContact(contact),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.activeConversationKey,
    required this.conversations,
    required this.conversationLabel,
    required this.owner,
    required this.onBackToContacts,
    this.onCallTap,
    this.onVideoCallTap,
    this.activeProject,
    this.onAnalyzeProjectChat,
    this.onDraftProjectTask,
    this.onStartProjectAgent,
    this.onShowProjectStatus,
  });

  final String activeConversationKey;
  final List<ChatConversation> conversations;
  final String Function(ChatConversation conversation, String actor)
      conversationLabel;
  final String owner;
  final VoidCallback onBackToContacts;
  final VoidCallback? onCallTap;
  final VoidCallback? onVideoCallTap;
  final TaskProject? activeProject;
  final VoidCallback? onAnalyzeProjectChat;
  final VoidCallback? onDraftProjectTask;
  final VoidCallback? onStartProjectAgent;
  final VoidCallback? onShowProjectStatus;

  @override
  Widget build(BuildContext context) {
    final conv = conversations.firstWhere(
      (c) => c.conversationKey == activeConversationKey,
      orElse: () => conversations.isEmpty
          ? ChatConversation(
              conversationKey: activeConversationKey,
              kind: 'direct',
              title: '',
              members: const [],
            )
          : conversations.first,
    );
    final isGroup = conv.kind == 'group' ||
        conv.conversationKey == 'group:common' ||
        conv.conversationKey.startsWith('grp:');
    final avatarUrl = conv.avatarUrl;
    const baseUrl = AppConfig.apiBaseUrl;

    final project = activeProject;
    final l10n = AppLocalizations.of(context);
    final hasProjectActions = project != null &&
        (onAnalyzeProjectChat != null ||
            onDraftProjectTask != null ||
            onStartProjectAgent != null ||
            onShowProjectStatus != null);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: l10n?.contacts ?? 'Контакты',
                onPressed: onBackToContacts,
              ),
              if (isGroup && avatarUrl != null && avatarUrl.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: CircleAvatar(
                    radius: 16,
                    backgroundImage: NetworkImage(
                      avatarUrl.startsWith('/')
                          ? '$baseUrl$avatarUrl'
                          : avatarUrl,
                    ),
                    onBackgroundImageError: (_, __) {},
                  ),
                ),
              Expanded(
                child: Text(
                  conversationLabel(conv, owner),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hasProjectActions)
                PopupMenuButton<String>(
                  key: const ValueKey('messenger-project-agent-menu'),
                  tooltip: l10n?.projectAgentMenu ?? 'Агент проекта',
                  icon: const Icon(Icons.smart_toy_outlined),
                  onSelected: (value) {
                    if (value == 'analyze') {
                      onAnalyzeProjectChat?.call();
                    } else if (value == 'draft') {
                      onDraftProjectTask?.call();
                    } else if (value == 'start') {
                      onStartProjectAgent?.call();
                    } else if (value == 'status') {
                      onShowProjectStatus?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'analyze',
                      child: Text(
                        l10n?.projectControlAnalyzeChat ?? 'Анализ чата',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'draft',
                      child: Text(
                        l10n?.projectControlDraftTask ?? 'Черновик задачи',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'start',
                      child: Text(
                        l10n?.projectControlStartAgent ?? 'Запустить агента',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'status',
                      child: Text(
                        l10n?.projectControlProjectStatus ?? 'Статус проекта',
                      ),
                    ),
                  ],
                ),
              if (onCallTap != null)
                IconButton(
                  icon: const Icon(Icons.call),
                  tooltip: l10n?.audioCall ?? 'Аудиозвонок',
                  onPressed: onCallTap,
                ),
              if (onVideoCallTap != null)
                IconButton(
                  icon: const Icon(Icons.videocam),
                  tooltip: l10n?.videoCall ?? 'Видеозвонок',
                  onPressed: onVideoCallTap,
                ),
            ],
          ),
          if (project != null)
            Padding(
              padding: const EdgeInsets.only(left: 48, right: 8, bottom: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  key: const ValueKey('messenger-project-chip'),
                  avatar: const Icon(Icons.folder_outlined, size: 16),
                  label: Text(project.name),
                  visualDensity: VisualDensity.compact,
                  onPressed: onShowProjectStatus,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator({
    required this.conversationKey,
    required this.typingUsers,
    required this.owner,
    required this.profileLabel,
  });

  final String conversationKey;
  final Map<String, Set<String>> typingUsers;
  final String owner;
  final String Function(String) profileLabel;

  @override
  Widget build(BuildContext context) {
    final users = typingUsers[conversationKey];
    if (users == null || users.isEmpty) return const SizedBox.shrink();
    final others = users.where((p) => p != owner).toList();
    if (others.isEmpty) return const SizedBox.shrink();
    final label = others.length == 1
        ? '${profileLabel(others.first)} печатает...'
        : '${others.length} человека печатают...';
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).disabledColor,
        ),
      ),
    );
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.chatInputController,
    required this.replyToMessage,
    required this.editingMessageId,
    required this.isRecording,
    required this.chatMessageText,
    required this.onClearReply,
    required this.onCancelEdit,
    required this.onOpenAttachMenu,
    required this.onStartRecord,
    required this.onStopRecord,
    required this.onSendText,
  });

  final TextEditingController chatInputController;
  final ChatMessage? replyToMessage;
  final String? editingMessageId;
  final bool isRecording;
  final String Function(ChatMessage message) chatMessageText;
  final VoidCallback onClearReply;
  final VoidCallback onCancelEdit;
  final VoidCallback onOpenAttachMenu;
  final VoidCallback onStartRecord;
  final VoidCallback onStopRecord;
  final VoidCallback onSendText;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final replyPreview =
        replyToMessage == null ? null : chatMessageText(replyToMessage!);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyToMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.reply_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n?.replyPreview(replyPreview!) ??
                          'Ответ: $replyPreview',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: onClearReply,
                    child: Text(l10n?.cancel ?? 'Отмена'),
                  ),
                ],
              ),
            ),
          if (editingMessageId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n?.editingMessage ?? 'Редактирование сообщения',
                    ),
                  ),
                  TextButton(
                    onPressed: onCancelEdit,
                    child: Text(l10n?.cancel ?? 'Отмена'),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              IconButton(
                tooltip: l10n?.attachment ?? 'Вложение',
                icon: const Icon(Icons.attach_file),
                onPressed: onOpenAttachMenu,
              ),
              Expanded(
                child: TextField(
                  controller: chatInputController,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  onSubmitted:
                      editingMessageId != null ? (_) => onSendText() : null,
                  decoration: InputDecoration(
                    hintText: editingMessageId == null
                        ? l10n?.message ?? 'Сообщение'
                        : l10n?.editMessage ?? 'Изменить сообщение',
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              GestureDetector(
                onLongPressStart: (_) => onStartRecord(),
                onLongPressEnd: (_) => onStopRecord(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isRecording ? Colors.red : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    isRecording ? Icons.mic : Icons.mic_none,
                    color: isRecording ? Colors.white : null,
                  ),
                ),
              ),
              IconButton.filled(
                tooltip: l10n?.send ?? 'Отправить',
                onPressed: onSendText,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
