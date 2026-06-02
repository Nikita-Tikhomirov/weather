import 'package:flutter/material.dart';

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
      return _StickerUnavailable(size: size);
    }
    return Image.network(
      stickerAssetUrl,
      fit: BoxFit.contain,
      width: size,
      height: size,
      errorBuilder: (context, error, stackTrace) {
        return _StickerUnavailable(size: size);
      },
    );
  }
}

class _StickerUnavailable extends StatelessWidget {
  const _StickerUnavailable({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          size: 34,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
