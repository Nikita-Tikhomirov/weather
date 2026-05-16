import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/chat_models.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.mine,
    required this.compact,
    required this.text,
    required this.senderLabel,
    required this.stickerAssetUrl,
    required this.imageUrl,
    required this.onLongPress,
    required this.onImageTap,
    this.onQuoteTap,
  });

  final ChatMessage message;
  final bool mine;
  final bool compact;
  final String text;
  final String senderLabel;
  final String stickerAssetUrl;
  final String imageUrl;
  final VoidCallback onLongPress;
  final void Function(int index) onImageTap;
  final VoidCallback? onQuoteTap;

  @override
  Widget build(BuildContext context) {
    final deleted = message.isDeleted;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          constraints: BoxConstraints(maxWidth: compact ? 320 : 560),
          decoration: BoxDecoration(
            color: deleted
                ? Theme.of(context).colorScheme.surfaceContainerHighest
                : mine
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                senderLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 4),
              _buildContent(context, deleted, text),
              const SizedBox(height: 4),
              if (message.reactions.isNotEmpty) _buildReactionsRow(context),
              if (message.reactions.isNotEmpty) const SizedBox(height: 4),
              Text(
                _messageFooter(),
                style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool deleted, String text) {
    if (deleted) {
      return const Text(
        'Сообщение удалено',
        style: TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF9CA3AF)),
      );
    }
    // Reply quote
    if (text.startsWith('> ') &&
        text.contains('\n') &&
        message.messageType == 'text') {
      final parts = text.split('\n');
      final quoteLines = <String>[];
      final replyLines = <String>[];
      bool inReply = false;
      for (final line in parts) {
        if (!inReply && line.startsWith('> ')) {
          quoteLines.add(line.substring(2));
        } else {
          inReply = true;
          replyLines.add(line);
        }
      }
      final quoteText = quoteLines.join('\n');
      final replyText = replyLines.join('\n');
      // Check for media preview markers
      final photoMatch = RegExp(r'\[photo:(.+?)\]').firstMatch(quoteText);
      final videoMatch = RegExp(r'\[video:(.+?)\]').firstMatch(quoteText);
      final hasVoice = quoteText.contains('[voice]');
      final hasAudio = quoteText.contains('[audio]');
      final cleanQuote = quoteText
          .replaceAll(RegExp(r'\[photo:.+?\]\s*'), '')
          .replaceAll(RegExp(r'\[video:.+?\]\s*'), '')
          .replaceAll('[voice] ', '')
          .replaceAll('[audio] ', '');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.only(left: 8),
            decoration: const BoxDecoration(
              border:
                  Border(left: BorderSide(color: Color(0xFF3B82F6), width: 3)),
            ),
            child: GestureDetector(
              onTap: onQuoteTap,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (photoMatch != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          _bubbleAssetUrl(photoMatch.group(1)!),
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image, size: 40),
                        ),
                      ),
                    ),
                  if (videoMatch != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          _bubbleAssetUrl(videoMatch.group(1)!),
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.videocam, size: 40, color: Color(0xFF6B7280)),
                        ),
                      ),
                    ),
                  if (hasVoice)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child:
                          Icon(Icons.mic, size: 24, color: Color(0xFF6B7280)),
                    ),
                  if (hasAudio)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child:
                          Icon(Icons.audiotrack, size: 24, color: Color(0xFF6B7280)),
                    ),
                  Expanded(
                    child: Text(
                      cleanQuote,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF6B7280)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (replyText.isNotEmpty) ...[
            const SizedBox(height: 4),
            _buildTextWithLinks(replyText, context),
          ],
        ],
      );
    }
    if (message.messageType == 'voice') {
      return _buildVoiceBubble(context);
    }
    if (message.messageType == 'video' ||
        message.messageType == 'video_group') {
      return _buildVideoBubble(context);
    }
    if (message.messageType == 'audio') {
      return _buildAudioBubble(context);
    }
    if (message.messageType == 'sticker') {
      if (stickerAssetUrl.isNotEmpty &&
          !stickerAssetUrl.startsWith('emoji://')) {
        return Image.network(
          stickerAssetUrl,
          fit: BoxFit.contain,
          width: compact ? 160 : 220,
          height: compact ? 160 : 220,
          errorBuilder: (context, error, stackTrace) {
            return Text(text, style: const TextStyle(fontSize: 34));
          },
        );
      }
      return Text(text, style: const TextStyle(fontSize: 34));
    }
    if (message.messageType == 'image' ||
        message.messageType == 'image_group') {
      final urls = _messageImageUrls();
      if (urls.isEmpty) {
        return Text(text.isEmpty ? 'Изображение' : text);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildImageGrid(urls),
          if (text.trim().isNotEmpty) const SizedBox(height: 6),
          if (text.trim().isNotEmpty) Text(text),
        ],
      );
    }
    if (message.messageType == 'text') {
      return _buildTextWithLinks(text, context);
    }
    return Text(text);
  }

  static final RegExp _urlRegex =
      RegExp(r'(https?://[^\s]+|www\.[^\s]+\.[^\s]+)');

  Widget _buildTextWithLinks(String text, BuildContext context) {
    final matches = _urlRegex.allMatches(text);
    if (matches.isEmpty) {
      return Text(text);
    }
    final spans = <InlineSpan>[];
    int lastEnd = 0;
    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final url = match.group(0)!;
      final uri = Uri.tryParse(url.startsWith('www.') ? 'https://$url' : url);
      spans.add(
        TextSpan(
          text: url,
          style: const TextStyle(
            color: Colors.blue,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              if (uri != null) {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }
    return Text.rich(TextSpan(children: spans));
  }

  List<String> _messageImageUrls() {
    final attachments = message.attachments
        .where(
            (item) => item.kind == 'image' && item.assetUrl.trim().isNotEmpty)
        .toList()
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    if (attachments.isNotEmpty) {
      return attachments.map((item) => item.assetUrl).toList();
    }
    return imageUrl.trim().isEmpty ? const [] : [imageUrl];
  }

  Widget _buildImageGrid(List<String> urls) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < urls.length; i++)
          GestureDetector(
            onTap: () => onImageTap(i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                _bubbleAssetUrl(urls[i]),
                fit: BoxFit.cover,
                width: urls.length == 1
                    ? (compact ? 260 : 420)
                    : (compact ? 120 : 160),
                height: urls.length == 1 ? null : (compact ? 120 : 160),
                errorBuilder: (context, error, stackTrace) {
                  return SelectableText(
                    urls[i],
                    style:
                        const TextStyle(decoration: TextDecoration.underline),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVoiceBubble(BuildContext context) {
    final ms = (message.imageMeta['duration_ms'] as int?) ?? 0;
    final d = Duration(milliseconds: ms);
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        const ch = MethodChannel('family_todo_mobile/voice');
        ch.invokeMethod('playVoice', {'url': _bubbleAssetUrl(imageUrl)});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mine ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow,
                size: 24,
                color: mine ? cs.onPrimaryContainer : cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: mine ? cs.onPrimaryContainer : cs.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoBubble(BuildContext context) {
    final urls = _messageImageUrls();
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < urls.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i < urls.length - 1 ? 8 : 0),
            child: GestureDetector(
              onTap: () {
                final uri = Uri.tryParse(_bubbleAssetUrl(urls[i]));
                if (uri != null) {
                  launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: compact ? 260 : 420,
                    height: compact ? 180 : 280,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Icon(Icons.videocam, size: 56, color: Color(0xFF6B7280)),
                    ),
                  ),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (text.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(text),
        ],
      ],
    );
  }

  Widget _buildAudioBubble(BuildContext context) {
    final urls = _messageImageUrls();
    final audioUrl = urls.isNotEmpty ? urls.first : _bubbleAssetUrl(imageUrl);
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        const ch = MethodChannel('family_todo_mobile/voice');
        ch.invokeMethod('playVoice', {'url': audioUrl});
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.audiotrack,
                size: 28,
                color: mine ? cs.onPrimaryContainer : cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text.isNotEmpty ? text : 'Аудио',
                style: TextStyle(
                  fontSize: 14,
                  color: mine ? cs.onPrimaryContainer : cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _bubbleAssetUrl(String raw) {
    final value = raw.trim();
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) {
      return 'http://31.129.97.211$value';
    }
    return value;
  }

  Widget _buildReactionsRow(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: message.reactions.map((reaction) {
        final isMyReaction = message.myReaction == reaction.reaction;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isMyReaction
                ? cs.primaryContainer.withValues(alpha: 0.5)
                : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border:
                isMyReaction ? Border.all(color: cs.primary, width: 1) : null,
          ),
          child: Text(
            '${reaction.reaction} ${reaction.count}',
            style: TextStyle(
              fontSize: 13,
              color: isMyReaction
                  ? const Color(0xFF1D4ED8)
                  : const Color(0xFF475569),
            ),
          ),
        );
      }).toList(),
    );
  }

  String _messageFooter() {
    if ((message.editedAt ?? '').isNotEmpty) {
      return '${message.createdAt} · изменено';
    }
    return message.createdAt;
  }
}
