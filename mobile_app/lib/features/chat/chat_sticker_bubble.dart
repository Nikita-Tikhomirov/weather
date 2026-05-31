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
}
