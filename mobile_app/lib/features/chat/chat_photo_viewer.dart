import 'dart:async';

import 'package:flutter/material.dart';

void showChatPhotoViewer({
  required BuildContext context,
  required List<String> urls,
  required int initialIndex,
  required Future<bool> Function(String url) onSaveImage,
  VoidCallback? onImageSaved,
  VoidCallback? onImageSaveFailed,
}) {
  if (urls.isEmpty) {
    return;
  }

  var notifySavedAfterClose = false;
  unawaited(
    showDialog<void>(
      context: context,
      builder: (_) {
        return _ChatPhotoViewerDialog(
          urls: urls,
          initialIndex: initialIndex,
          onSaveImage: onSaveImage,
          onImageSaveFailed: onImageSaveFailed,
          onImageSavedAfterClose: () {
            notifySavedAfterClose = true;
          },
        );
      },
    ).then((_) {
      if (notifySavedAfterClose) {
        onImageSaved?.call();
      }
    }),
  );
}

class _ChatPhotoViewerDialog extends StatefulWidget {
  const _ChatPhotoViewerDialog({
    required this.urls,
    required this.initialIndex,
    required this.onSaveImage,
    required this.onImageSavedAfterClose,
    this.onImageSaveFailed,
  });

  final List<String> urls;
  final int initialIndex;
  final Future<bool> Function(String url) onSaveImage;
  final VoidCallback onImageSavedAfterClose;
  final VoidCallback? onImageSaveFailed;

  @override
  State<_ChatPhotoViewerDialog> createState() => _ChatPhotoViewerDialogState();
}

class _ChatPhotoViewerDialogState extends State<_ChatPhotoViewerDialog> {
  late final PageController _controller;
  late int _currentIndex;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final maxIndex = widget.urls.length - 1;
    _currentIndex = widget.initialIndex.clamp(0, maxIndex);
    _controller = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _saveCurrentImage() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final success = await widget.onSaveImage(widget.urls[_currentIndex]);
      if (!mounted) return;
      if (success) {
        widget.onImageSavedAfterClose();
        Navigator.of(context).pop();
        return;
      }
      widget.onImageSaveFailed?.call();
      setState(() => _saving = false);
    } catch (_) {
      if (!mounted) return;
      widget.onImageSaveFailed?.call();
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.urls.length,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              return InteractiveViewer(
                child: Center(
                  child: Image.network(
                    widget.urls[index],
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image,
                      color: Colors.white70,
                      size: 48,
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            top: 24,
            right: 12,
            child: Theme(
              data: Theme.of(context).copyWith(
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
              ),
              child: Row(
                children: [
                  IconButton.filled(
                    onPressed: _saving ? null : _saveCurrentImage,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
