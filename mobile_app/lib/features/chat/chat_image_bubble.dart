import 'package:flutter/material.dart';

import 'chat_media_bubble.dart';

/// Renders an image grid for image/image_group messages.
class ChatImageBubble extends StatelessWidget {
  const ChatImageBubble({
    super.key,
    required this.urls,
    required this.compact,
    required this.onImageTap,
    required this.resolveUrl,
  });

  final List<String> urls;
  final bool compact;
  final void Function(int index) onImageTap;
  final String Function(String raw) resolveUrl;

  @override
  Widget build(BuildContext context) {
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
                resolveUrl(urls[i]),
                fit: BoxFit.cover,
                width: urls.length == 1
                    ? (compact ? 260 : 420)
                    : (compact ? 120 : 160),
                height: urls.length == 1 ? null : (compact ? 120 : 160),
                errorBuilder: (context, error, stackTrace) {
                  return SelectableText(
                    urls[i],
                    style: const TextStyle(
                      decoration: TextDecoration.underline,
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// Renders video previews for video/video_group messages.
class ChatVideoBubble extends StatelessWidget {
  const ChatVideoBubble({
    super.key,
    required this.urls,
    required this.compact,
    required this.text,
    required this.resolveUrl,
    this.thumbUrl,
  });

  final List<String> urls;
  final bool compact;
  final String text;
  final String Function(String raw) resolveUrl;
  final String? thumbUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < urls.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i < urls.length - 1 ? 8 : 0),
            child: GestureDetector(
              onTap: () {
                final url = resolveUrl(urls[i]);
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
                        url: resolveUrl(urls[i]),
                        thumbnailUrl:
                            thumbUrl != null ? resolveUrl(thumbUrl!) : null,
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
}
