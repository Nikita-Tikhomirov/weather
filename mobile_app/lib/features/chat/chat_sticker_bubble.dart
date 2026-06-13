import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Renders sticker content for sticker messages.
class ChatStickerBubble extends StatelessWidget {
  const ChatStickerBubble({
    super.key,
    required this.stickerAssetUrl,
    required this.text,
    required this.compact,
  });

  final String stickerAssetUrl;
  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 160.0 : 220.0;
    if (stickerAssetUrl.isEmpty || stickerAssetUrl.startsWith('emoji://')) {
      return _StickerUnavailable(size: size, text: text);
    }
    return Image.network(
      stickerAssetUrl,
      fit: BoxFit.contain,
      width: size,
      height: size,
      errorBuilder: (context, error, stackTrace) {
        return _StickerUnavailable(size: size, text: text);
      },
    );
  }
}

class _StickerUnavailable extends StatelessWidget {
  const _StickerUnavailable({required this.size, required this.text});

  final double size;
  final String text;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final label = text.trim().isEmpty
        ? l10n?.stickerUnavailable ?? 'Sticker unavailable'
        : text.trim();
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
