import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../models/chat_models.dart';
import '../../shared/utils/avatar_url_resolver.dart';
import 'chat_voice_bubble.dart';
import 'chat_media_bubble.dart';

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
        'РЎРѕРѕР±С‰РµРЅРёРµ СѓРґР°Р»РµРЅРѕ',
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
        return Text(text.isEmpty ? 'РР·РѕР±СЂР°Р¶РµРЅРёРµ' : text);
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
    return VoiceBubble(
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
                    builder: (_) => VideoPlayerScreen(url: url),
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
                      child: VideoThumbnail(
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
    final displayName = fileName.isNotEmpty ? fileName : 'Р”РѕРєСѓРјРµРЅС‚';
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
    if (bytes < 1024) return '$bytes Р‘';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} РљР‘';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} РњР‘';
  }

  /// Map progress to a user-friendly phase label.
  static String _uploadPhaseLabel(double progress, bool isVideo) {
    if (!isVideo) {
      if (progress < 0.5) return 'Р—Р°РіСЂСѓР·РєР°...';
      if (progress < 0.9) return 'РћС‚РїСЂР°РІРєР°...';
      return 'Р—Р°РІРµСЂС€РµРЅРёРµ...';
    }
    // Video has phases: compress в†’ read в†’ upload в†’ finalize
    if (progress < 0.01) return 'РџРѕРґРіРѕС‚РѕРІРєР°...';
    if (progress < 0.25) return 'РЎР¶Р°С‚РёРµ...';
    if (progress < 0.30) return 'Р§С‚РµРЅРёРµ...';
    if (progress < 0.98) return 'Р—Р°РіСЂСѓР·РєР°...';
    return 'Р—Р°РІРµСЂС€РµРЅРёРµ...';
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
                text.isNotEmpty ? text : 'РђСѓРґРёРѕ',
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
      return '$formatted В· РёР·РјРµРЅРµРЅРѕ';
    }
    // Show delivery status for own messages
    if (mine) {
      final status = _deliveryStatusIcon();
      return '$status $formatted';
    }
    return formatted;
  }

  /// РџСЂРµРѕР±СЂР°Р·СѓРµС‚ ISO-8601 СЃС‚СЂРѕРєСѓ РІ С‡РµР»РѕРІРµРєРѕС‡РёС‚Р°РµРјС‹Р№ С„РѕСЂРјР°С‚: В«21 РјР°СЏ 15:30В»
  static String _formatIsoDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const months = [
        'СЏРЅРІ',
        'С„РµРІ',
        'РјР°СЂ',
        'Р°РїСЂ',
        'РјР°СЏ',
        'РёСЋРЅ',
        'РёСЋР»',
        'Р°РІРі',
        'СЃРµРЅ',
        'РѕРєС‚',
        'РЅРѕСЏ',
        'РґРµРє',
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
        return 'вЏі';
      case 'sent':
        return 'вњ“';
      case 'delivered':
        return 'вњ“вњ“';
      case 'read':
        return 'вњ“вњ“';
      case 'failed':
        return 'вќЊ';
      default:
        return '';
    }
  }
}
