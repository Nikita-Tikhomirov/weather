import 'package:flutter/material.dart';

import '../../models/chat_models.dart';
import 'chat_message_bubble.dart';

class ChatMessagesList extends StatefulWidget {
  const ChatMessagesList({
    super.key,
    required this.messages,
    required this.owner,
    required this.compact,
    required this.textFor,
    required this.senderLabelFor,
    required this.stickerAssetFor,
    required this.imageUrlFor,
    required this.onLongPress,
    required this.onImageTap,
    this.hasMoreOlder = false,
    this.loadingOlder = false,
    this.onLoadOlder,
    this.replyToMessageId,
    this.onQuoteTap,
    this.avatarForContact,
  });

  final List<ChatMessage> messages;
  final String owner;
  final bool compact;
  final String Function(ChatMessage message) textFor;
  final String Function(String profile) senderLabelFor;
  final String Function(ChatMessage message) stickerAssetFor;
  final String Function(ChatMessage message) imageUrlFor;
  final void Function(ChatMessage message) onLongPress;
  final void Function(ChatMessage message, int index) onImageTap;
  final bool hasMoreOlder;
  final bool loadingOlder;
  final Future<void> Function()? onLoadOlder;
  final String? replyToMessageId;
  final void Function(String quoteText)? onQuoteTap;
  final String? Function(String profileKey)? avatarForContact;

  @override
  State<ChatMessagesList> createState() => ChatMessagesListState();
}

class ChatMessagesListState extends State<ChatMessagesList> {
  final ScrollController _controller = ScrollController();
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};

  GlobalKey _keyFor(String id) =>
      _itemKeys.putIfAbsent(id, () => GlobalKey(debugLabel: 'msg-$id'));

  @override
  void initState() {
    super.initState();
    _controller.addListener(_maybeLoadOlder);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void didUpdateWidget(covariant ChatMessagesList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldLast =
        oldWidget.messages.isEmpty ? '' : oldWidget.messages.last.id;
    final newLast = widget.messages.isEmpty ? '' : widget.messages.last.id;
    if (oldLast != newLast) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      return;
    }

    if (oldWidget.messages.length != widget.messages.length &&
        _controller.hasClients) {
      final oldMax = _controller.position.maxScrollExtent;
      final oldOffset = _controller.offset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) {
          return;
        }
        final delta = _controller.position.maxScrollExtent - oldMax;
        final nextOffset = (oldOffset + delta).clamp(
          _controller.position.minScrollExtent,
          _controller.position.maxScrollExtent,
        );
        _controller.jumpTo(nextOffset.toDouble());
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_maybeLoadOlder);
    _controller.dispose();
    super.dispose();
  }

  void _maybeLoadOlder() {
    if (!widget.hasMoreOlder ||
        widget.loadingOlder ||
        widget.onLoadOlder == null ||
        !_controller.hasClients) {
      return;
    }
    if (_controller.position.pixels <= 160) {
      widget.onLoadOlder!();
    }
  }

  void _scrollToBottom() {
    if (!_controller.hasClients) {
      return;
    }
    void jump() {
      if (!_controller.hasClients) {
        return;
      }
      _controller.animateTo(
        _controller.position.maxScrollExtent + 96,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }

    jump();
    Future<void>.delayed(const Duration(milliseconds: 300), jump);
    Future<void>.delayed(const Duration(milliseconds: 900), jump);
  }

  void scrollToMessage(String messageId) {
    final key = _itemKeys[messageId];
    if (key?.currentContext == null) return;
    Scrollable.ensureVisible(
      key!.currentContext!,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
  }

  void _navigateToQuote(String quoteText, {String? excludeMessageId}) {
    // Clean media markers from the quote text
    final cleaned = quoteText
        .replaceAll(RegExp(r'\[photo:.+?\]\s*'), '')
        .replaceAll(RegExp(r'\[video:.+?\]\s*'), '')
        .replaceAll('[voice] ', '')
        .replaceAll('[audio] ', '')
        .trim();
    // Extract text after "Name: "
    final colonIdx = cleaned.indexOf(': ');
    final quotedCore =
        colonIdx >= 0 ? cleaned.substring(colonIdx + 2).trim() : cleaned;
    if (quotedCore.isEmpty) return;
    // Find first message whose text matches the quoted content
    for (final msg in widget.messages) {
      if (excludeMessageId != null && msg.id == excludeMessageId) continue;
      final msgText = widget.textFor(msg);
      // Skip messages that are themselves replies (they start with "> ")
      if (msg.messageType == 'text' && msgText.trimLeft().startsWith('> ')) {
        continue;
      }
      if (msgText == quotedCore ||
          msgText.startsWith(quotedCore) ||
          msgText.contains(quotedCore)) {
        scrollToMessage(msg.id);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: widget.messages.length + (widget.loadingOlder ? 1 : 0),
      itemBuilder: (context, index) {
        if (widget.loadingOlder && index == 0) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final messageIndex = widget.loadingOlder ? index - 1 : index;
        final message = widget.messages[messageIndex];
        final mine = message.senderProfile == widget.owner;
        return ChatMessageBubble(
          key: _keyFor(message.id),
          message: message,
          mine: mine,
          compact: widget.compact,
          text: widget.textFor(message),
          senderLabel: widget.senderLabelFor(message.senderProfile),
          stickerAssetUrl: widget.stickerAssetFor(message),
          imageUrl: widget.imageUrlFor(message),
          avatarUrl: widget.avatarForContact?.call(message.senderProfile),
          onLongPress: () => widget.onLongPress(message),
          onImageTap: (index) => widget.onImageTap(message, index),
          onQuoteTap: () {
            final t = widget.textFor(message);
            if (!(t.startsWith('> ') &&
                t.contains('\n') &&
                message.messageType == 'text')) {
              return;
            }

            // Try ID-based navigation first: extract quoted message ID from clientMessageId
            final cid = message.clientMessageId ?? '';
            if (cid.startsWith('reply-')) {
              final parts = cid.split('-');
              // Format: reply-{quotedId}-{timestamp}
              if (parts.length >= 3) {
                final quotedId = parts[1];
                // Validate it looks like a ULID or UUID (alphanumeric)
                if (quotedId.isNotEmpty &&
                    RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(quotedId)) {
                  scrollToMessage(quotedId);
                  return;
                }
              }
            }

            // Fallback: text-based search
            final parts = t.split('\n');
            final qLines = <String>[];
            var inReply = false;
            for (final line in parts) {
              if (!inReply && line.startsWith('> ')) {
                qLines.add(line.substring(2));
              } else {
                inReply = true;
              }
            }
            final quote = qLines.join('\n');
            if (quote.isNotEmpty) {
              _navigateToQuote(quote, excludeMessageId: message.id);
            }
          },
        );
      },
    );
  }
}
