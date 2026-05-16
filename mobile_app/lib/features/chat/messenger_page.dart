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

  @override
  Widget build(BuildContext context) {
    if (activeConversationKey.isEmpty) {
      return _ContactList(
        contacts: contacts,
        projects: projects,
        contactLabel: contactLabel,
        onRefreshContacts: onRefreshContacts,
        onCreateGroup: onCreateGroup,
        onAddContactToFamily: onAddContactToFamily,
        onOpenDirectContact: onOpenDirectContact,
        onOpenProjectContact: onOpenProjectContact,
        onOpenBridgeSettings: onOpenBridgeSettings,
      );
    }

    return Column(
      children: [
        _ConversationChooser(
          conversations: conversations,
          activeConversationKey: activeConversationKey,
          owner: owner,
          conversationLabel: conversationLabel,
          onBackToContacts: onBackToContacts,
          onOpenConversation: onOpenConversation,
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
            onLongPress: onOpenMessageActions,
            onImageTap: onImageTap,
          ),
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
    required this.contactLabel,
    required this.onRefreshContacts,
    required this.onCreateGroup,
    required this.onAddContactToFamily,
    required this.onOpenDirectContact,
    required this.onOpenProjectContact,
    required this.onOpenBridgeSettings,
  });

  final List<ChatContact> contacts;
  final List<ProjectContact> projects;
  final String Function(ChatContact contact) contactLabel;
  final VoidCallback onRefreshContacts;
  final VoidCallback onCreateGroup;
  final void Function(ChatContact contact) onAddContactToFamily;
  final void Function(ChatContact contact) onOpenDirectContact;
  final void Function(ProjectContact project) onOpenProjectContact;
  final VoidCallback onOpenBridgeSettings;

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
              if (contacts.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Нет зарегистрированных контактов из телефона'),
                )
              else
                ...List.generate(contacts.length, (index) {
                  final contact = contacts[index];
                  return ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(contactLabel(contact)),
                    subtitle: Text(contact.phone),
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

class _ConversationChooser extends StatelessWidget {
  const _ConversationChooser({
    required this.conversations,
    required this.activeConversationKey,
    required this.owner,
    required this.conversationLabel,
    required this.onBackToContacts,
    required this.onOpenConversation,
  });

  final List<ChatConversation> conversations;
  final String activeConversationKey;
  final String owner;
  final String Function(ChatConversation conversation, String actor)
      conversationLabel;
  final VoidCallback onBackToContacts;
  final void Function(String conversationKey) onOpenConversation;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Контакты'),
              onPressed: onBackToContacts,
            ),
          ),
          for (final conversation in conversations)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(conversationLabel(conversation, owner)),
                selected: activeConversationKey == conversation.conversationKey,
                onSelected: (_) =>
                    onOpenConversation(conversation.conversationKey),
              ),
            ),
        ],
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
