import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../models/chat_models.dart';
import '../../shared/utils/avatar_url_resolver.dart';

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
      final image = avatarUrl!.startsWith('http') || avatarUrl!.startsWith('/')
          ? NetworkImage(avatarUrl!.startsWith('/')
              ? AvatarUrlResolver.resolveUrl(avatarUrl!)
              : avatarUrl!) as ImageProvider
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
    if (message.messageType == 'file') {
      final fileAtt = message.attachments.isNotEmpty
          ? message.attachments.first
          : null;
      final fileName = (fileAtt?.imageMeta['original_name'] ?? '').toString();
      final fileUrl = fileAtt != null
          ? _bubbleAssetUrl(fileAtt.assetUrl)
          : _bubbleAssetUrl(imageUrl);
      return _buildDocumentBubble(context, fileName, fileUrl);
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
    final thumbUrl = message.imageUrl is String && (message.imageUrl as String).isNotEmpty
        ? message.imageUrl as String
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < urls.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i < urls.length - 1 ? 8 : 0),
            child: GestureDetector(
              onTap: () {
                final url = _bubbleAssetUrl(urls[i]);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _VideoPlayerScreen(url: url),
                  ),
                );
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: compact ? 260 : 420,
                      height: compact ? 180 : 280,
                      child: _VideoThumbnail(
                        url: _bubbleAssetUrl(urls[i]),
                        thumbnailUrl: thumbUrl != null ? _bubbleAssetUrl(thumbUrl) : null,
                      ),
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

  Widget _buildDocumentBubble(
      BuildContext context, String fileName, String fileUrl) {
    final cs = Theme.of(context).colorScheme;
    final ext = fileName.contains('.') ? fileName.split('.').last : '';
    final icon = _iconForExtension(ext);
    final displayName = fileName.isNotEmpty ? fileName : 'Документ';
    final sizeText = _formatFileSize(
      message.attachments.isNotEmpty
          ? (message.attachments.first.imageMeta['size_bytes'] as int?) ?? 0
          : 0,
    );
    return GestureDetector(
      onTap: () async {
        if (fileUrl.isEmpty) return;
        final uri = Uri.tryParse(fileUrl);
        if (uri == null) return;
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e) {
          debugPrint('[chat] launchUrl error: $e');
          // launchUrl may fail if no browser is available
        }
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
            Icon(icon, size: 36, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (sizeText.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      sizeText,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.download,
              size: 24,
              color: cs.primary,
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconForExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip;
      case 'mp3':
      case 'wav':
      case 'ogg':
      case 'm4a':
        return Icons.audiotrack;
      case 'mp4':
      case 'mov':
      case 'webm':
      case 'mkv':
        return Icons.videocam;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
      case 'gif':
        return Icons.image;
      case 'txt':
        return Icons.article;
      default:
        return Icons.insert_drive_file;
    }
  }

  static String _formatFileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  /// Map progress to a user-friendly phase label.
  static String _uploadPhaseLabel(double progress, bool isVideo) {
    if (!isVideo) {
      if (progress < 0.5) return 'Загрузка...';
      if (progress < 0.9) return 'Отправка...';
      return 'Завершение...';
    }
    // Video has phases: compress → read → upload → finalize
    if (progress < 0.01) return 'Подготовка...';
    if (progress < 0.25) return 'Сжатие...';
    if (progress < 0.30) return 'Чтение...';
    if (progress < 0.98) return 'Загрузка...';
    return 'Завершение...';
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
      return AvatarUrlResolver.resolveUrl(value);
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
    final isVideo = kind == 'video' || kind == 'video_group';
    final phaseLabel = _uploadPhaseLabel(progress, isVideo);
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
            Text('$phaseLabel $pct%'),
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
    final formatted = _formatIsoDate(message.createdAt);
    if ((message.editedAt ?? '').isNotEmpty) {
      return '$formatted · изменено';
    }
    // Show delivery status for own messages
    if (mine) {
      final status = _deliveryStatusIcon();
      return '$status $formatted';
    }
    return formatted;
  }

  /// Преобразует ISO-8601 строку в человекочитаемый формат: «21 мая 15:30»
  static String _formatIsoDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = [
        'янв',
        'фев',
        'мар',
        'апр',
        'мая',
        'июн',
        'июл',
        'авг',
        'сен',
        'окт',
        'ноя',
        'дек',
      ];
      final day = dt.day;
      final month = months[dt.month - 1];
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$day $month $hour:$minute';
    } catch (e, st) {
      debugPrint('[chat] date format error: $e\n$st');
      return iso;
    }
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
    } catch (e, st) {
      debugPrint('[chat] voice playback error: $e\n$st');
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

/// Full-screen video player for in-app playback.
class _VideoPlayerScreen extends StatefulWidget {
  const _VideoPlayerScreen({required this.url});

  final String url;

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  final _ctrlKey = GlobalKey<_VideoControlsState>();
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      setState(() => _hasError = true);
      return;
    }
    try {
      final ctrl = VideoPlayerController.networkUrl(uri);
      _controller = ctrl;
      await ctrl.initialize();
      if (mounted) {
        setState(() => _ready = true);
        ctrl.play();
      }
    } catch (e, st) {
      debugPrint('[chat] video init error: $e\n$st');
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_hasError) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.white, size: 48),
          SizedBox(height: 12),
          Text('Не удалось загрузить видео',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ],
      );
    }
    if (!_ready || _controller == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _ctrlKey.currentState?.toggleVisibility(),
            child: Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                VideoPlayer(_controller!),
                _VideoControls(key: _ctrlKey, controller: _controller!),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Loads the first frame of a video as thumbnail, falls back to videocam icon.
class _VideoThumbnail extends StatefulWidget {
  const _VideoThumbnail({required this.url, this.thumbnailUrl});

  final String url;
  final String? thumbnailUrl;

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  VideoPlayerController? _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Prefer dedicated thumbnail URL
    if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty) {
      setState(() => _ready = true);
      return;
    }
    // Otherwise seek to first frame
    final uri = Uri.tryParse(widget.url);
    if (uri == null) return;
    try {
      final ctrl = VideoPlayerController.networkUrl(uri);
      await ctrl.initialize();
      await ctrl.seekTo(const Duration(seconds: 1));
      await ctrl.play();
      // Wait one frame then pause
      await Future.delayed(const Duration(milliseconds: 300));
      await ctrl.pause();
      if (mounted) {
        _ctrl = ctrl;
        setState(() => _ready = true);
      }
    } catch (e, st) {
      debugPrint('[chat] video thumbnail error: $e\n$st');
      // keep showing placeholder
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Dedicated thumbnail URL
    if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty) {
      return Image.network(
        widget.thumbnailUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    // VideoPlayer thumbnail
    if (_ready && _ctrl != null && _ctrl!.value.isInitialized) {
      return ClipRRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _ctrl!.value.size.width,
            height: _ctrl!.value.size.height,
            child: VideoPlayer(_ctrl!),
          ),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFF374151),
      child: const Center(
        child: Icon(Icons.videocam, size: 56, color: Color(0xFF6B7280)),
      ),
    );
  }
}

/// Play/pause + progress controls at bottom, full width.
class _VideoControls extends StatefulWidget {
  const _VideoControls({super.key, required this.controller});

  final VideoPlayerController controller;

  @override
  State<_VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<_VideoControls> {
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onPlaybackUpdate);
  }

  void _onPlaybackUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPlaybackUpdate);
    super.dispose();
  }

  void toggleVisibility() {
    setState(() => _showControls = !_showControls);
  }

  void _togglePlay() {
    setState(() {
      if (widget.controller.value.isPlaying) {
        widget.controller.pause();
      } else {
        widget.controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final isPlaying = value.isPlaying;
    final position = value.position;
    final duration = value.duration;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    final posStr =
        '${position.inMinutes}:${(position.inSeconds % 60).toString().padLeft(2, '0')}';
    final durStr =
        '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

    return Stack(
      fit: StackFit.expand,
      children: [
        // Center play/pause
        Center(
          child: AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: IconButton(
              icon: Icon(
                isPlaying ? Icons.pause_circle : Icons.play_circle,
                color: Colors.white,
                size: 64,
              ),
              onPressed: _togglePlay,
            ),
          ),
        ),
        // Bottom bar
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              color: Colors.black54,
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SliderTheme(
                      data: const SliderThemeData(
                        trackHeight: 4,
                        thumbShape:
                            RoundSliderThumbShape(enabledThumbRadius: 8),
                        overlayShape:
                            RoundSliderOverlayShape(overlayRadius: 16),
                      ),
                      child: Slider(
                        value: progress.clamp(0.0, 1.0),
                        activeColor: Colors.white,
                        inactiveColor: Colors.white30,
                        onChanged: (v) {
                          final ms =
                              (v * duration.inMilliseconds).round();
                          widget.controller
                              .seekTo(Duration(milliseconds: ms));
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(posStr,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                          Text(durStr,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}