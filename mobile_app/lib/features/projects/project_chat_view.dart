import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/project_contact.dart';
import '../../services/project_bridge_service.dart';
import 'project_icons.dart';

class ProjectChatView extends StatelessWidget {
  const ProjectChatView({
    super.key,
    required this.project,
    required this.bridge,
    required this.messages,
    required this.chatInputController,
    required this.onBack,
    required this.onRequestBridgeStart,
    required this.onStartNewSession,
    required this.onStopProjectPrompt,
    required this.onOpenBridgeSettings,
    required this.onOpenProjectFiles,
    required this.onReconnect,
    required this.onSendPhotos,
    required this.onSendMessage,
  });

  final ProjectContact project;
  final ProjectBridgeService? bridge;
  final List<BridgeMessage> messages;
  final TextEditingController chatInputController;
  final VoidCallback onBack;
  final VoidCallback onRequestBridgeStart;
  final VoidCallback onStartNewSession;
  final VoidCallback onStopProjectPrompt;
  final VoidCallback onOpenBridgeSettings;
  final VoidCallback onOpenProjectFiles;
  final VoidCallback onReconnect;
  final VoidCallback onSendPhotos;
  final VoidCallback onSendMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ProjectChatHeader(
          project: project,
          bridge: bridge,
          onBack: onBack,
          onRequestBridgeStart: onRequestBridgeStart,
          onStartNewSession: onStartNewSession,
          onStopProjectPrompt: onStopProjectPrompt,
          onOpenBridgeSettings: onOpenBridgeSettings,
          onOpenProjectFiles: onOpenProjectFiles,
        ),
        Expanded(
          child: messages.isEmpty
              ? _EmptyProjectChat(onReconnect: onReconnect)
              : _ProjectMessageList(project: project, messages: messages),
        ),
        _ProjectChatInput(
          controller: chatInputController,
          onSendPhotos: onSendPhotos,
          onOpenProjectFiles: onOpenProjectFiles,
          onSendMessage: onSendMessage,
        ),
      ],
    );
  }
}

class _ProjectChatHeader extends StatelessWidget {
  const _ProjectChatHeader({
    required this.project,
    required this.bridge,
    required this.onBack,
    required this.onRequestBridgeStart,
    required this.onStartNewSession,
    required this.onStopProjectPrompt,
    required this.onOpenBridgeSettings,
    required this.onOpenProjectFiles,
  });

  final ProjectContact project;
  final ProjectBridgeService? bridge;
  final VoidCallback onBack;
  final VoidCallback onRequestBridgeStart;
  final VoidCallback onStartNewSession;
  final VoidCallback onStopProjectPrompt;
  final VoidCallback onOpenBridgeSettings;
  final VoidCallback onOpenProjectFiles;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                onPressed: onBack,
              ),
              const SizedBox(width: 4),
              CircleAvatar(
                radius: 18,
                child: Icon(projectIcon(project.icon), size: 20),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Запустить bridge',
                icon: const Icon(Icons.power_settings_new),
                onPressed: onRequestBridgeStart,
              ),
              IconButton(
                tooltip: 'Новая сессия',
                icon: const Icon(Icons.add_to_queue),
                onPressed: onStartNewSession,
              ),
              IconButton(
                tooltip: 'Остановить DeepSeek',
                icon: const Icon(Icons.stop_circle_outlined),
                onPressed: onStopProjectPrompt,
              ),
              IconButton(
                tooltip: 'Настроить сервер',
                icon: const Icon(Icons.settings),
                onPressed: onOpenBridgeSettings,
              ),
              IconButton(
                tooltip: 'Файлы проекта',
                icon: const Icon(Icons.folder_open),
                onPressed: onOpenProjectFiles,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 48, bottom: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      FutureBuilder<String>(
                        future: ProjectBridgeService.getServerAddress(),
                        builder: (context, snapshot) {
                          final addr = snapshot.data ?? '...';
                          return Text(
                            bridge?.isConnected == true
                                ? 'Подключено • $addr'
                                : 'Подключение к $addr...',
                            style: TextStyle(
                              fontSize: 11,
                              color: bridge?.isConnected == true
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyProjectChat extends StatelessWidget {
  const _EmptyProjectChat({required this.onReconnect});

  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.terminal,
            size: 48,
            color: Theme.of(context).disabledColor,
          ),
          const SizedBox(height: 8),
          const Text('Терминал проекта', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            'Напишите сообщение для взаимодействия\nс AI-ассистентом в проекте',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).disabledColor),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: onReconnect,
            icon: const Icon(Icons.refresh),
            label: const Text('Переподключиться'),
          ),
        ],
      ),
    );
  }
}

class _ProjectMessageList extends StatelessWidget {
  const _ProjectMessageList({
    required this.project,
    required this.messages,
  });

  final ProjectContact project;
  final List<BridgeMessage> messages;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[messages.length - 1 - index];
        final isMe = msg.isSent || msg.type == 'send';
        final isStatus = msg.isStatus || msg.isPong;

        if (isStatus) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              msg.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).disabledColor,
              ),
            ),
          );
        }

        if (msg.isImage && msg.imageBase64.isNotEmpty) {
          return _ProjectImageMessage(message: msg, isMe: isMe);
        }

        return _ProjectTextMessage(
          project: project,
          message: msg,
          isMe: isMe,
        );
      },
    );
  }
}

class _ProjectImageMessage extends StatelessWidget {
  const _ProjectImageMessage({
    required this.message,
    required this.isMe,
  });

  final BridgeMessage message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: isMe ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'DeepSeek',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ),
            GestureDetector(
              onTap: () => _showFullScreen(context),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  base64Decode(message.imageBase64),
                  width: 248,
                  height: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.broken_image, size: 48),
                ),
              ),
            ),
            if (message.imageFilename.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                  message.imageFilename,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).disabledColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showFullScreen(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.memory(
                base64Decode(message.imageBase64),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.broken_image,
                    size: 48,
                    color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectTextMessage extends StatelessWidget {
  const _ProjectTextMessage({
    required this.project,
    required this.message,
    required this.isMe,
  });

  final ProjectContact project;
  final BridgeMessage message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMe
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  project.name,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            SelectableText(
              message.text,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectChatInput extends StatelessWidget {
  const _ProjectChatInput({
    required this.controller,
    required this.onSendPhotos,
    required this.onOpenProjectFiles,
    required this.onSendMessage,
  });

  final TextEditingController controller;
  final VoidCallback onSendPhotos;
  final VoidCallback onOpenProjectFiles;
  final VoidCallback onSendMessage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Фото в vision',
            onPressed: onSendPhotos,
            icon: const Icon(Icons.image_outlined),
          ),
          IconButton(
            tooltip: 'Файлы проекта',
            onPressed: onOpenProjectFiles,
            icon: const Icon(Icons.folder_open),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSendMessage(),
              decoration: const InputDecoration(
                hintText: 'Сообщение',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                ),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Отправить',
            onPressed: onSendMessage,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
