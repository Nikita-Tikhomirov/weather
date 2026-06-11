import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../../l10n/app_localizations.dart';
import '../../models/chat_models.dart';
import '../../shared/utils/avatar_url_resolver.dart';
import 'chat_attachment_bubble.dart';
import 'chat_audio_bubble.dart';
import 'chat_image_bubble.dart';
import 'chat_sticker_bubble.dart';
import 'chat_text_bubble.dart';
import 'chat_voice_bubble.dart';

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
                _messageFooter(context),
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -- Mini avatar ---------------------------------------------------------

  Widget _buildMiniAvatar({double radius = 14}) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      final image = avatarUrl!.startsWith('http') || avatarUrl!.startsWith('/')
          ? NetworkImage(
              avatarUrl!.startsWith('/')
                  ? AvatarUrlResolver.resolveUrl(avatarUrl!)
                  : avatarUrl!,
            ) as ImageProvider
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

  // -- Content dispatcher --------------------------------------------------

  Widget _buildContent(BuildContext context, bool deleted, String text) {
    if (message.isUploading) {
      return _buildUploadingContent(context);
    }
    if (deleted) {
      return Text(
        AppLocalizations.of(context)?.messageDeleted ?? 'Сообщение удалено',
        style: const TextStyle(
          fontStyle: FontStyle.italic,
          color: Color(0xFF9CA3AF),
        ),
      );
    }
    // Reply quote
    if (text.startsWith('> ') &&
        text.contains('\n') &&
        message.messageType == 'text') {
      return _buildReplyQuote(context, text);
    }
    if (message.messageType == 'voice') {
      return VoiceBubble(
        url: _bubbleAssetUrl(imageUrl),
        durationMs: (message.imageMeta['duration_ms'] as int?) ?? 0,
        mine: mine,
      );
    }
    if (message.messageType == 'video' ||
        message.messageType == 'video_group') {
      final urls = _attachmentUrlsForKinds(['video']);
      final thumbUrl =
          message.imageUrl is String && (message.imageUrl as String).isNotEmpty
              ? message.imageUrl as String
              : null;
      return ChatVideoBubble(
        urls: urls,
        compact: compact,
        text: text,
        resolveUrl: _bubbleAssetUrl,
        thumbUrl: thumbUrl,
      );
    }
    if (message.messageType == 'audio') {
      final urls = _attachmentUrlsForKinds(['audio']);
      final audioUrl = urls.isNotEmpty ? urls.first : _bubbleAssetUrl(imageUrl);
      return ChatAudioBubble(
        audioUrl: audioUrl,
        text: text,
        mine: mine,
      );
    }
    if (message.messageType == 'sticker') {
      return ChatStickerBubble(
        stickerAssetUrl: stickerAssetUrl,
        text: text,
        compact: compact,
      );
    }
    if (message.messageType == 'image' ||
        message.messageType == 'image_group') {
      final urls = _messageImageUrls();
      if (urls.isEmpty) {
        return Text(
          text.isEmpty
              ? AppLocalizations.of(context)?.imageMessage ?? 'Изображение'
              : text,
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChatImageBubble(
            urls: urls,
            compact: compact,
            onImageTap: onImageTap,
            resolveUrl: _bubbleAssetUrl,
          ),
          if (text.trim().isNotEmpty) const SizedBox(height: 6),
          if (text.trim().isNotEmpty) Text(text),
        ],
      );
    }
    if (message.messageType == 'file') {
      final fileAtt =
          message.attachments.isNotEmpty ? message.attachments.first : null;
      final fileName = (fileAtt?.imageMeta['original_name'] ?? '').toString();
      final fileUrl = fileAtt != null
          ? _bubbleAssetUrl(fileAtt.assetUrl)
          : _bubbleAssetUrl(imageUrl);
      final sizeBytes =
          fileAtt != null ? (fileAtt.imageMeta['size_bytes'] as int?) ?? 0 : 0;
      return ChatAttachmentBubble(
        fileName: fileName,
        fileUrl: fileUrl,
        mine: mine,
        sizeBytes: sizeBytes,
      );
    }
    if (message.messageType == 'text') {
      return ChatTextBubble(text: text);
    }
    return Text(text);
  }

  // -- Reply quote ---------------------------------------------------------

  Widget _buildReplyQuote(BuildContext context, String text) {
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
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ),
                if (hasVoice)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.mic, size: 24, color: Color(0xFF6B7280)),
                  ),
                if (hasAudio)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.audiotrack,
                      size: 24,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                Expanded(
                  child: Text(
                    cleanQuote,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (replyText.isNotEmpty) ...[
          const SizedBox(height: 4),
          ChatTextBubble(text: replyText),
        ],
      ],
    );
  }

  // -- Helper: image URLs --------------------------------------------------

  List<String> _messageImageUrls() {
    final attachments = message.attachments
        .where(
          (item) => item.kind == 'image' && item.assetUrl.trim().isNotEmpty,
        )
        .toList()
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    if (attachments.isNotEmpty) {
      return attachments.map((item) => item.assetUrl).toList();
    }
    return imageUrl.trim().isEmpty ? const [] : [imageUrl];
  }

  List<String> _attachmentUrlsForKinds(List<String> kinds) {
    final attachments = message.attachments
        .where(
          (item) =>
              kinds.contains(item.kind) && item.assetUrl.trim().isNotEmpty,
        )
        .toList()
      ..sort((left, right) => left.sortOrder.compareTo(right.sortOrder));
    if (attachments.isNotEmpty) {
      return attachments.map((item) => item.assetUrl).toList();
    }
    return imageUrl.trim().isEmpty ? const [] : [imageUrl];
  }

  // -- URL resolution ------------------------------------------------------

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

  // -- Reactions row -------------------------------------------------------

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

  // -- Uploading content ---------------------------------------------------

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
          (item) => item.kind == 'image' && item.assetUrl.trim().isNotEmpty,
        )
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

  // -- Footer / date formatting --------------------------------------------

  String _messageFooter(BuildContext context) {
    final localeName = Localizations.localeOf(context).toLanguageTag();
    final formatted = _formatIsoDate(message.createdAt, localeName);
    if ((message.editedAt ?? '').isNotEmpty) {
      final edited = AppLocalizations.of(context)?.edited ?? 'изменено';
      return '$formatted · $edited';
    }
    if (mine) {
      final status = _deliveryStatusIcon();
      return '$status $formatted';
    }
    return formatted;
  }

  static String _formatIsoDate(String iso, String localeName) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final date = intl.DateFormat.MMMd(localeName).format(dt);
      final time = intl.DateFormat.Hm(localeName).format(dt);
      return '$date $time';
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

  // -- Upload phase label --------------------------------------------------

  static String _uploadPhaseLabel(double progress, bool isVideo) {
    if (!isVideo) {
      if (progress < 0.5) return 'Загрузка...';
      if (progress < 0.9) return 'Отправка...';
      return 'Завершение...';
    }
    if (progress < 0.01) return 'Подготовка...';
    if (progress < 0.25) return 'Сжатие...';
    if (progress < 0.30) return 'Чтение...';
    if (progress < 0.98) return 'Загрузка...';
    return 'Завершение...';
  }
}
