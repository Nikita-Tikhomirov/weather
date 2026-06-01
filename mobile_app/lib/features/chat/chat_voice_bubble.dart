import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Voice message bubble with animated waveform.
class VoiceBubble extends StatefulWidget {
  const VoiceBubble({
    super.key,
    required this.url,
    required this.durationMs,
    required this.mine,
  });

  final String url;
  final int durationMs;
  final bool mine;

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble>
    with SingleTickerProviderStateMixin {
  bool _playing = false;
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: widget.durationMs > 0 ? widget.durationMs : 3000,
      ),
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
                  painter: WaveformPainter(
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

/// Paints the animated waveform for voice messages.
class WaveformPainter extends CustomPainter {
  const WaveformPainter({
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
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.active != active ||
        oldDelegate.color != color ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
