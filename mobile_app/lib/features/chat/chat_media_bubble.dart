import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Full-screen video player for in-app playback.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.url});

  final String url;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
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
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(controller.pause());
      unawaited(controller.dispose());
    }
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
          Text(
            'Не удалось загрузить видео',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      );
    }
    if (!_ready || _controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
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
                VideoControls(key: _ctrlKey, controller: _controller!),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Loads the first frame of a video as thumbnail, falls back to videocam icon.
class VideoThumbnail extends StatefulWidget {
  const VideoThumbnail({super.key, required this.url, this.thumbnailUrl});

  final String url;
  final String? thumbnailUrl;

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty) {
      setState(() => _ready = true);
      return;
    }
    final uri = Uri.tryParse(widget.url);
    if (uri == null) return;
    VideoPlayerController? ctrl;
    try {
      ctrl = VideoPlayerController.networkUrl(uri);
      _ctrl = ctrl;
      await ctrl.initialize();
      await ctrl.setVolume(0);
      await ctrl.seekTo(const Duration(seconds: 1));
      await ctrl.pause();
      if (mounted && !_disposed) {
        setState(() => _ready = true);
        return;
      }
      await ctrl.dispose();
    } catch (e, st) {
      debugPrint('[chat] video thumbnail error: $e\n$st');
      if (_ctrl == ctrl) {
        _ctrl = null;
      }
      if (!_disposed) {
        await ctrl?.dispose();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final ctrl = _ctrl;
    _ctrl = null;
    if (ctrl != null) {
      unawaited(ctrl.pause());
      unawaited(ctrl.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty) {
      return Image.network(
        widget.thumbnailUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
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
class VideoControls extends StatefulWidget {
  const VideoControls({super.key, required this.controller});

  final VideoPlayerController controller;

  @override
  State<VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<VideoControls> {
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
                          final ms = (v * duration.inMilliseconds).round();
                          widget.controller.seekTo(Duration(milliseconds: ms));
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            posStr,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            durStr,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
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
