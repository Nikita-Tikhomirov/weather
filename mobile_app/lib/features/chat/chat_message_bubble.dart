import 'dart:io';

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
    this.avatarUrl,
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
  final String? avatarUrl;

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
          constraints: BoxConstraints(maxWidth: compact ? 300 : 540),
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
              Row(
                mainAxisSize: MainAxisSize.min,
                textDirection: mine ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  _buildMiniAvatar(radius: 10),
                  const SizedBox(width: 6),
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
                ],
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

  Widget _buildMiniAvatar({double radius = 14}) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      final image = avatarUrl!.startsWith('http')
          ? NetworkImage(avatarUrl!) as ImageProvider
          : FileImage(File(avatarUrl!));
      return CircleAvatar(
        radius: radius,
        backgroundImage: image,
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: radius,
      child: Icon(Icons.person, size: radius + 2),
    );
  }

  Widget _buildContent(BuildContext context, bool deleted, String text) {
    if (message.isUploading) {
      return _buildUploadingContent(context);
    }
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
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.videocam,
                              size: 40,
                              color: Color(0xFF6B7280)),
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
                      child: Icon(Icons.audiotrack,
                          size: 24, color: Color(0xFF6B7280)),
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
    return _VoiceBubble(
      url: _bubbleAssetUrl(imageUrl),
      durationMs: (message.imageMeta['duration_ms'] as int?) ?? 0,
      mine: mine,
    );
  }

  List<String> _attachmentUrlsForKinds(List<String> kinds) {
    final attachments = message.attachments
        .where((item) =>
            kinds.contains(item.kind) && item.assetUrl.trim().isNotEmpty)
        .toList()
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    if (attachments.isNotEmpty) {
      return attachments.map((item) => item.assetUrl).toList();
    }
    return imageUrl.trim().isEmpty ? const [] : [imageUrl];
  }

  Widget _buildVideoBubble(BuildContext context) {
    final urls = _attachmentUrlsForKinds(['video']);
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < urls.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i < urls.length - 1 ? 8 : 0),
            child: GestureDetector(
              onTap: () async {
                final uri = Uri.tryParse(_bubbleAssetUrl(urls[i]));
                if (uri == null) return;
                try {
                  final ok = await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Не удалось открыть видео')),
                    );
                  }
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ошибка воспроизведения')),
                    );
                  }
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
                      child: Icon(Icons.videocam,
                          size: 56, color: Color(0xFF6B7280)),
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
    final urls = _attachmentUrlsForKinds(['audio']);
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

  Widget _buildUploadingContent(BuildContext context) {
    final progress = message.uploadProgress.clamp(0.0, 1.0);
    final pct = (progress * 100).round();
    final kind = message.messageType;
    final isImageUpload = kind == 'image' || kind == 'image_group';
    final label = kind == 'video'
        ? 'Видео'
        : isImageUpload
            ? 'Фото'
            : 'Файл';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isImageUpload) ...[
          _buildUploadPreviewGrid(context, progress),
          const SizedBox(height: 8),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text('Отправка $label... $pct%'),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: progress),
      ],
    );
  }

  Widget _buildUploadPreviewGrid(BuildContext context, double progress) {
    final cs = Theme.of(context).colorScheme;
    final previews = message.attachments
        .where(
            (item) => item.kind == 'image' && item.assetUrl.trim().isNotEmpty)
        .toList()
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    final width = previews.length <= 1 ? (compact ? 238.0 : 320.0) : 104.0;
    final height = previews.length <= 1 ? (compact ? 160.0 : 220.0) : 104.0;
    return Stack(
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final item in previews)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: _buildLocalPreview(item.assetUrl),
                ),
              ),
          ],
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.20),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  '${(progress * 100).round()}%',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLocalPreview(String path) {
    final file = File(path);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return Container(
      color: const Color(0xFFE5E7EB),
      child: const Center(
        child: Icon(Icons.image_outlined, color: Color(0xFF6B7280)),
      ),
    );
  }

  String _messageFooter() {
    if ((message.editedAt ?? '').isNotEmpty) {
      return '${message.createdAt} · изменено';
    }
    // Show delivery status for own messages
    if (mine) {
      final status = _deliveryStatusIcon();
      return '$status ${message.createdAt}';
    }
    return message.createdAt;
  }

  String _deliveryStatusIcon() {
    switch (message.deliveryStatus) {
      case 'sending':
        return '⏳';
      case 'sent':
        return '✓';
      case 'delivered':
        return '✓✓';
      case 'read':
        return '✓✓';
      case 'failed':
        return '❌';
      default:
        return '';
    }
  }
}

class _VoiceBubble extends StatefulWidget {
  const _VoiceBubble({
    required this.url,
    required this.durationMs,
    required this.mine,
  });

  final String url;
  final int durationMs;
  final bool mine;

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble>
    with SingleTickerProviderStateMixin {
  bool _playing = false;
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: Duration(
          milliseconds: widget.durationMs > 0 ? widget.durationMs : 3000),
    );
    _animCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _playing = false);
      }
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (widget.url.trim().isEmpty) {
      return;
    }
    final nextPlaying = !_playing;
    setState(() => _playing = nextPlaying);
    try {
      if (nextPlaying) {
        if (_animCtrl.value >= 1.0) {
          _animCtrl.value = 0.0;
        }
        _animCtrl.forward();
        await const MethodChannel('family_todo_mobile/voice')
            .invokeMethod('playVoice', {'url': widget.url});
      } else {
        _animCtrl.stop();
        await const MethodChannel('family_todo_mobile/voice')
            .invokeMethod('pauseVoice');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _playing = false);
      }
      _animCtrl.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = Duration(milliseconds: widget.durationMs);
    final timeStr = widget.durationMs > 0
        ? '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}'
        : '0:00';
    final fg = widget.mine ? cs.onPrimaryContainer : cs.onSurfaceVariant;

    return Container(
      width: MediaQuery.sizeOf(context).width < 380 ? 228 : 292,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: widget.mine ? cs.primaryContainer : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          IconButton.filled(
            visualDensity: VisualDensity.compact,
            tooltip: _playing ? 'Пауза' : 'Воспроизвести',
            onPressed: _togglePlay,
            icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedBuilder(
              animation: _animCtrl,
              builder: (context, child) {
                return CustomPaint(
                  size: const Size(double.infinity, 38),
                  painter: _WaveformPainter(
                    progress: _animCtrl.value,
                    active: _playing,
                    color: fg,
                    inactiveColor: fg.withValues(alpha: 0.28),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Text(
            timeStr,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: widget.mine ? cs.onPrimaryContainer : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.progress,
    required this.active,
    required this.color,
    required this.inactiveColor,
  });

  final double progress;
  final bool active;
  final Color color;
  final Color inactiveColor;

  @override
  void paint(Canvas canvas, Size size) {
    const count = 34;
    final slot = size.width / count;
    final activePaint = Paint()..color = color;
    final idlePaint = Paint()..color = inactiveColor;
    for (var i = 0; i < count; i++) {
      final seed = ((i * 37) % 13) / 12.0;
      final pulse = active ? ((progress * 2 + i / count) % 1.0) : 0.0;
      final wave = active ? (pulse < 0.5 ? pulse * 2 : (1 - pulse) * 2) : 0.0;
      final h = 7 + (size.height - 8) * (0.25 + seed * 0.45 + wave * 0.30);
      final x = i * slot + slot * 0.35;
      final top = (size.height - h) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top, slot * 0.42, h),
        const Radius.circular(3),
      );
      canvas.drawRRect(rect, i / count <= progress ? activePaint : idlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.active != active ||
        oldDelegate.color != color ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
