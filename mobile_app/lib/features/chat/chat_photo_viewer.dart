import 'package:flutter/material.dart';

void showChatPhotoViewer({
  required BuildContext context,
  required List<String> urls,
  required int initialIndex,
  required void Function(String url) onSaveImage,
}) {
  if (urls.isEmpty) {
    return;
  }
  final controller = PageController(initialPage: initialIndex);
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            PageView.builder(
              controller: controller,
              itemCount: urls.length,
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  child: Center(
                    child: Image.network(urls[index], fit: BoxFit.contain),
                  ),
                );
              },
            ),
            Positioned(
              top: 24,
              right: 12,
              child: Row(
                children: [
                  IconButton.filled(
                    onPressed: () => onSaveImage(urls[0]),
                    icon: const Icon(Icons.download),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}
