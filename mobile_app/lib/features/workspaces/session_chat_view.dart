import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../chat/chat_scroll_policy.dart';
import '../../models/workspace_item.dart';
import '../../models/workspace_session.dart';

class _SessionChatText {
  const _SessionChatText(this.l10n);

  final AppLocalizations? l10n;

  String get back => l10n?.back ?? 'Назад';
  String get manageSession => l10n?.manageSession ?? 'Управление сессией';
  String get sessionHistoryEmpty =>
      l10n?.sessionHistoryEmpty ?? 'История сессии пуста';
  String get attachPhoto => l10n?.attachPhoto ?? 'Прикрепить фото';
  String get attachDocument =>
      l10n?.attachDocument ?? 'Прикрепить документ';
  String get message => l10n?.message ?? 'Сообщение';
  String get send => l10n?.send ?? 'Отправить';
  String get copyText => l10n?.copyText ?? 'Копировать текст';
  String get copied => l10n?.copied ?? 'Скопировано';
  String get workProgress => l10n?.workProgress ?? 'Ход работы';
}

class SessionChatView extends StatefulWidget {
  const SessionChatView({
    super.key,
    required this.workspace,
    required this.session,
    required this.events,
    required this.inputController,
    required this.onBack,
    required this.onOpenManagement,
    required this.onSend,
    this.onSendPhoto,
    this.onSendDocument,
  });

  final WorkspaceItem workspace;
  final WorkspaceSession session;
  final List<Map<String, dynamic>> events;
  final TextEditingController inputController;
  final VoidCallback onBack;
  final VoidCallback onOpenManagement;
  final void Function(String text) onSend;
  final VoidCallback? onSendPhoto;
  final VoidCallback? onSendDocument;

  @override
  State<SessionChatView> createState() => _SessionChatViewState();
}

class _SessionChatViewState extends State<SessionChatView> {
  final ScrollController _scrollController = ScrollController();
  int _bottomScrollRequest = 0;

  @override
  void initState() {
    super.initState();
    _scheduleScrollToLatest();
  }

  @override
  void didUpdateWidget(SessionChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_eventTailSignature(oldWidget.events) !=
        _eventTailSignature(widget.events)) {
      _scheduleScrollToLatest();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _SessionChatText(AppLocalizations.of(context));
    final visibleEvents = _mergeAssistantDeltas(widget.events);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: text.back,
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.session.title),
            Text(
              widget.workspace.name,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: text.manageSession,
            icon: const Icon(Icons.tune),
            onPressed: widget.onOpenManagement,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: visibleEvents.isEmpty
                ? Center(child: Text(text.sessionHistoryEmpty))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: visibleEvents.length,
                    itemBuilder: (context, index) {
                      final event = visibleEvents[index];
                      if (_isProcessEvent(event)) {
                        return _ProcessEventRow(event: event);
                      }
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
                  if (widget.onSendPhoto != null)
                    IconButton(
                      tooltip: text.attachPhoto,
                      icon: const Icon(Icons.image_outlined),
                      onPressed: widget.onSendPhoto,
                    ),
                  if (widget.onSendDocument != null)
                    IconButton(
                      tooltip: text.attachDocument,
                      icon: const Icon(Icons.attach_file),
                      onPressed: widget.onSendDocument,
                    ),
                  Expanded(
                    child: TextField(
                      controller: widget.inputController,
                      minLines: 1,
                      maxLines: 4,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: text.message,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: text.send,
                    icon: const Icon(Icons.send),
                    onPressed: () {
                      final text = widget.inputController.text.trim();
                      if (text.isEmpty) {
                        return;
                      }
                      widget.inputController.clear();
                      widget.onSend(text);
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

  void _scheduleScrollToLatest() {
    final request = ++_bottomScrollRequest;
    ChatScrollPolicy.scheduleBottomSnap(
      controller: _scrollController,
      isActive: () => mounted && request == _bottomScrollRequest,
      animated: false,
    );
  }

  static String _eventTailSignature(List<Map<String, dynamic>> events) {
    if (events.isEmpty) {
      return 'empty';
    }
    final last = events.last;
    return '${events.length}|${last['type']}|${last['text']}|${last['status']}';
  }

  static bool _isProcessEvent(Map<String, dynamic> event) {
    final type = (event['type'] ?? '').toString();
    return type == 'session_process_event' || type == 'runtime_task';
  }

  static List<Map<String, dynamic>> _mergeAssistantDeltas(
    List<Map<String, dynamic>> source,
  ) {
    final merged = <Map<String, dynamic>>[];
    for (final event in source) {
      final type = (event['type'] ?? '').toString();
      final text = (event['text'] ?? event['status'] ?? '').toString();
      if (text.trim().isEmpty) {
        continue;
      }
      if (type == 'assistant_delta' &&
          merged.isNotEmpty &&
          merged.last['type'] == 'assistant_delta') {
        final previous = merged.removeLast();
        merged.add({
          ...previous,
          'text': '${previous['text'] ?? ''}${event['text'] ?? ''}',
          'final': event['final'] == true,
        });
        continue;
      }
      merged.add(event);
    }
    return merged;
  }
}

class _EventBubble extends StatelessWidget {
  const _EventBubble({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final textLabels = _SessionChatText(AppLocalizations.of(context));
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: SelectableText(text.isEmpty ? type : text),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: textLabels.copyText,
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: text.isEmpty ? type : text),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(textLabels.copied)),
                  );
                },
                icon: const Icon(Icons.copy),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProcessEventRow extends StatelessWidget {
  const _ProcessEventRow({required this.event});

  final Map<String, dynamic> event;

  @override
  Widget build(BuildContext context) {
    final textLabels = _SessionChatText(AppLocalizations.of(context));
    final text = (event['text'] ?? event['status'] ?? '').toString().trim();
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.terminal,
            size: 14,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SelectableText(
              '${textLabels.workProgress}: $text',
              style: TextStyle(
                fontSize: 12,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
