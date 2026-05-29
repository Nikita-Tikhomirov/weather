import 'package:flutter/material.dart';

import '../../models/workspace_item.dart';
import '../../models/workspace_session.dart';

class SessionChatView extends StatelessWidget {
  const SessionChatView({
    super.key,
    required this.workspace,
    required this.session,
    required this.events,
    required this.inputController,
    required this.onBack,
    required this.onOpenManagement,
    required this.onSend,
  });

  final WorkspaceItem workspace;
  final WorkspaceSession session;
  final List<Map<String, dynamic>> events;
  final TextEditingController inputController;
  final VoidCallback onBack;
  final VoidCallback onOpenManagement;
  final void Function(String text) onSend;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.title),
            Text(
              workspace.name,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Управление сессией',
            icon: const Icon(Icons.tune),
            onPressed: onOpenManagement,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: events.isEmpty
                ? const Center(child: Text('История сессии пуста'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return _EventBubble(event: event);
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: inputController,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Сообщение',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Отправить',
                    icon: const Icon(Icons.send),
                    onPressed: () {
                      final text = inputController.text.trim();
                      if (text.isEmpty) {
                        return;
                      }
                      inputController.clear();
                      onSend(text);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventBubble extends StatelessWidget {
  const _EventBubble({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final type = (event['type'] ?? '').toString();
    final text = (event['text'] ?? event['status'] ?? '').toString();
    final isUser = type == 'user_message' || type == 'send';
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isUser
                ? colors.primaryContainer
                : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(text.isEmpty ? type : text),
        ),
      ),
    );
  }
}
