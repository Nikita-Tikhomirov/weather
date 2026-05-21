import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/chat_models.dart';
import '../../models/project_contact.dart';
import '../projects/project_icons.dart';
import 'chat_messages_list.dart';

class MessengerPage extends StatelessWidget {
  const MessengerPage({
    super.key,
    required this.conversations,
    required this.contacts,
    required this.projects,
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
    required this.onOpenProjectContact,
    required this.onOpenBridgeSettings,
    required this.onBackToContacts,
    required this.onOpenConversation,
    required this.onOpenMessageActions,
    required this.onImageTap,
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
  });

  final List<ChatConversation> conversations;
  final List<ChatContact> contacts;
  final List<ProjectContact> projects;
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
  final void Function(ProjectContact project) onOpenProjectContact;
  final VoidCallback onOpenBridgeSettings;
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
  final Map<String, Set<String>> typingUsers;
  final VoidCallback? onCallTap;
  final VoidCallback? onVideoCallTap;

  @override
  Widget build(BuildContext context) {
    if (activeConversationKey.isEmpty) {
      return _ContactList(
        contacts: contacts,
        projects: projects,
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
        onOpenProjectContact: onOpenProjectContact,
        onOpenBridgeSettings: onOpenBridgeSettings,
        onOpenConversation: onOpenConversation,
        onManageGroup: onManageGroup,
      );
    }

    return Column(
      children: [
        _ChatHeader(
          activeConversationKey: activeConversationKey,
          conversations: conversations,
          conversationLabel: conversationLabel,
          owner: owner,
          onBackToContacts: onBackToContacts,
          onCallTap: onCallTap,
          onVideoCallTap: onVideoCallTap,
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
    required this.projects,
    required this.owner,
    required this.contactLabel,
    required this.typingUsers,
    required this.onRefreshContacts,
    required this.onCreateGroup,
    required this.onAddContactToFamily,
    required this.onOpenDirectContact,
    required this.onOpenProjectContact,
    required this.onOpenBridgeSettings,
    required this.groupConversations,
    required this.groupLabel,
    required this.onOpenConversation,
    required this.onManageGroup,
    this.avatarForContact,
  });

  final List<ChatContact> contacts;
  final List<ProjectContact> projects;
  final String owner;
  final Map<String, Set<String>> typingUsers;
  final List<ChatConversation> groupConversations;
  final String Function(ChatContact contact) contactLabel;
  final String Function(ChatConversation conv, String owner) groupLabel;
  final VoidCallback onRefreshContacts;
  final VoidCallback onCreateGroup;
  final void Function(ChatContact contact) onAddContactToFamily;
  final void Function(ChatContact contact) onOpenDirectContact;
  final void Function(ProjectContact project) onOpenProjectContact;
  final VoidCallback onOpenBridgeSettings;
  final void Function(String conversationKey) onOpenConversation;
  final void Function(ChatConversation conv) onManageGroup;
  final String? Function(String profileKey)? avatarForContact;

  Widget _buildContactAvatar(ChatContact contact) {
    final url = avatarForContact?.call(contact.profileKey);
    if (url != null && url.isNotEmpty) {
      if (url.startsWith('http') || url.startsWith('/')) {
        return CircleAvatar(
          backgroundImage: NetworkImage(
              url.startsWith('/') ? 'http://31.129.97.211$url' : url),
          onBackgroundImageError: (_, __) {},
          child: const Icon(Icons.person),
        );
      }
      return CircleAvatar(
        backgroundImage: FileImage(File(url)),
        onBackgroundImageError: (_, __) {},
        child: const Icon(Icons.person),
      );
    }
    return const CircleAvatar(child: Icon(Icons.person));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Контакты',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Обновить контакты',
                icon: const Icon(Icons.refresh),
                onPressed: onRefreshContacts,
              ),
              IconButton.filled(
                tooltip: 'Создать группу',
                icon: const Icon(Icons.group_add_outlined),
                onPressed: onCreateGroup,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (groupConversations.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 8, 4),
                  child: Text(
                    'Группы',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ...groupConversations.map((conv) {
                  return ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.group),
                    ),
                    title: Text(groupLabel(conv, '')),
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
              if (projects.isNotEmpty) ...[
                const Divider(height: 24),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Проекты (терминалы)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Настроить сервер',
                        icon: const Icon(Icons.settings, size: 20),
                        onPressed: onOpenBridgeSettings,
                      ),
                    ],
                  ),
                ),
                ...projects.map((project) {
                  return ListTile(
                    leading: CircleAvatar(
                      child: Icon(projectIcon(project.icon)),
                    ),
                    title: Text(project.name),
                    subtitle: Text(
                      project.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.terminal),
                    onTap: () => onOpenProjectContact(project),
                  );
                }),
              ],
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
  });

  final String activeConversationKey;
  final List<ChatConversation> conversations;
  final String Function(ChatConversation conversation, String actor)
      conversationLabel;
  final String owner;
  final VoidCallback onBackToContacts;
  final VoidCallback? onCallTap;
  final VoidCallback? onVideoCallTap;

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Контакты',
            onPressed: onBackToContacts,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              conversationLabel(conv, owner),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onCallTap != null)
            IconButton(
              icon: const Icon(Icons.call),
              tooltip: 'Аудиозвонок',
              onPressed: onCallTap,
            ),
          if (onVideoCallTap != null)
            IconButton(
              icon: const Icon(Icons.videocam),
              tooltip: 'Видеозвонок',
              onPressed: onVideoCallTap,
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
                      'Ответ: ${chatMessageText(replyToMessage!)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: onClearReply,
                    child: const Text('Отмена'),
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
                  const Expanded(child: Text('Редактирование сообщения')),
                  TextButton(
                    onPressed: onCancelEdit,
                    child: const Text('Отмена'),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              IconButton(
                tooltip: 'Вложение',
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
                        ? 'Сообщение'
                        : 'Изменить сообщение',
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
                tooltip: 'Отправить',
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
