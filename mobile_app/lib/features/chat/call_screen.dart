import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/call_models.dart';
import '../../services/call_service.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({
    super.key,
    required this.callService,
    required this.session,
    required this.isIncoming,
    required this.peerLabel,
    required this.onCallFinished,
  });

  final CallService callService;
  final CallSession session;
  final bool isIncoming;
  final String peerLabel;
  final VoidCallback onCallFinished;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  StreamSubscription<CallState>? _stateSub;
  StreamSubscription<MediaStream?>? _remoteStreamSub;
  CallState _currentState = CallState.calling;
  MediaStream? _remoteStream;
  Duration _duration = Duration.zero;
  Timer? _durationTimer;
  bool _isMuted = false;
  bool _isSpeakerOn = true;

  @override
  void initState() {
    super.initState();
    _currentState = widget.isIncoming ? CallState.ringing : CallState.calling;

    _stateSub = widget.callService.onStateChange.listen((state) {
      if (!mounted) return;
      setState(() {
        _currentState = state;
        if (state == CallState.connected && !_durationTimer?.isActive == true) {
          _startDuration();
        }
        if (state == CallState.ended) {
          _durationTimer?.cancel();
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) widget.onCallFinished();
          });
        }
      });
    });

    _remoteStreamSub = widget.callService.onRemoteStream.listen((stream) {
      if (!mounted) return;
      setState(() => _remoteStream = stream);
    });

    if (widget.isIncoming) {
      // Wait a frame then show ringing
    } else {
      // Outgoing call — start now
      _startCall();
    }
  }

  Future<void> _startCall() async {
    await widget.callService.startCall(
      conversationKey: widget.session.conversationKey,
      callType: widget.session.callType,
    );
  }

  void _startDuration() {
    _duration = Duration.zero;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _duration = _duration + const Duration(seconds: 1));
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _remoteStreamSub?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote video (or placeholder)
          if (_remoteStream != null && widget.session.callType == 'video')
            Positioned.fill(
              child: RTCVideoView(
                _remoteStream!,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            )
          else
            Positioned.fill(
              child: _AudioCallBackground(
                label: widget.peerLabel,
                callType: widget.session.callType,
                state: _currentState,
              ),
            ),

          // Status text
          Positioned(
            top: 80,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  widget.peerLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _statusText,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_currentState == CallState.connected) ...[
                  const SizedBox(height: 8),
                  Text(
                    _formatDuration(_duration),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 18,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Action buttons
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: _buildActions(),
          ),
        ],
      ),
    );
  }

  String get _statusText {
    switch (_currentState) {
      case CallState.calling:
        return 'Вызов...';
      case CallState.ringing:
        return 'Входящий звонок...';
      case CallState.connected:
        return 'Разговор';
      case CallState.ended:
        return 'Звонок завершён';
      case CallState.idle:
        return '';
    }
  }

  Widget _buildActions() {
    if (_currentState == CallState.ended) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_currentState == CallState.ringing) ...[
          // Reject
          _CallButton(
            icon: Icons.call_end,
            color: Colors.red,
            label: 'Отклонить',
            onTap: () async {
              await widget.callService.rejectCall(widget.session.sessionId);
            },
          ),
          const SizedBox(width: 40),
          // Accept
          _CallButton(
            icon: Icons.call,
            color: Colors.green,
            label: 'Принять',
            onTap: () async {
              await widget.callService.acceptCall(
                widget.session.sessionId,
                callType: widget.session.callType,
              );
            },
          ),
        ] else ...[
          // Mute
          _CallButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            color: _isMuted ? Colors.white : Colors.white38,
            label: _isMuted ? 'Вкл. микро' : 'Микрофон',
            onTap: () {
              setState(() => _isMuted = !_isMuted);
              // Toggle audio track
              Helper.setVolume(
                trackId: 'audio',
                volume: _isMuted ? 0.0 : 1.0,
              );
            },
          ),
          const SizedBox(width: 24),
          // End call
          _CallButton(
            icon: Icons.call_end,
            color: Colors.red,
            label: 'Завершить',
            onTap: () async {
              await widget.callService.endCall();
            },
            size: 64,
          ),
          const SizedBox(width: 24),
          // Speaker
          _CallButton(
            icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
            color: Colors.white38,
            label: 'Динамик',
            onTap: () {
              setState(() => _isSpeakerOn = !_isSpeakerOn);
              Helper.setVolume(
                trackId: 'audio',
                volume: _isSpeakerOn ? 1.0 : 0.5,
              );
            },
          ),
        ],
      ],
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.size = 56,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: size * 0.5),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _AudioCallBackground extends StatelessWidget {
  const _AudioCallBackground({
    required this.label,
    required this.callType,
    required this.state,
  });

  final String label;
  final String callType;
  final CallState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1a237e), Color(0xFF0d47a1)],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                callType == 'video' ? Icons.videocam : Icons.call,
                color: Colors.white,
                size: 48,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
