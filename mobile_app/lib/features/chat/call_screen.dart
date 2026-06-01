import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/call_models.dart';
import '../../services/call_service.dart';

Color callScreenBaseColor(String callType) {
  return callType.trim().toLowerCase() == 'video'
      ? Colors.black
      : const Color(0xFF0D47A1);
}

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
  StreamSubscription<MediaStream?>? _localStreamSub;
  StreamSubscription<String>? _errorSub;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  CallState _currentState = CallState.calling;
  MediaStream? _remoteStream;
  MediaStream? _localStream;
  String _errorText = '';
  Duration _duration = Duration.zero;
  Timer? _durationTimer;
  bool _remoteRendererReady = false;
  bool _localRendererReady = false;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isHeadsetPreferred = false;
  bool _speakerPreferenceApplied = false;
  Offset? _localPreviewOffset;

  static const Size _localPreviewSize = Size(118, 158);
  static const double _localPreviewMargin = 16;
  static const double _controlsReservedHeight = 164;

  bool get _isVideoCall =>
      widget.session.callType.trim().toLowerCase() == 'video';

  @override
  void initState() {
    super.initState();
    final serviceState = widget.callService.state;
    _currentState = serviceState == CallState.idle
        ? (widget.isIncoming ? CallState.ringing : CallState.calling)
        : serviceState;
    _remoteStream = widget.callService.remoteStream;
    _localStream = widget.callService.localStream;
    _isSpeakerOn = _isVideoCall;
    if (_isVideoCall) {
      _initializeRemoteRenderer();
      _initializeLocalRenderer();
    }
    if (_currentState == CallState.connected) {
      _startDuration();
      _speakerPreferenceApplied = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_applyAudioRoute());
        }
      });
    }

    _stateSub = widget.callService.onStateChange.listen((state) {
      if (!mounted) return;
      var shouldApplySpeakerPreference = false;
      setState(() {
        _currentState = state;
        if (state == CallState.connected && _durationTimer?.isActive != true) {
          _startDuration();
        }
        if (state == CallState.connected && !_speakerPreferenceApplied) {
          _speakerPreferenceApplied = true;
          shouldApplySpeakerPreference = true;
        }
        if (state == CallState.ended) {
          _durationTimer?.cancel();
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted) widget.onCallFinished();
          });
        }
      });
      if (shouldApplySpeakerPreference) {
        unawaited(_applyAudioRoute());
      }
    });

    _remoteStreamSub = widget.callService.onRemoteStream.listen((stream) {
      if (!mounted) return;
      if (_remoteRendererReady) {
        _remoteRenderer.srcObject = stream;
      }
      setState(() => _remoteStream = stream);
    });

    _localStreamSub = widget.callService.onLocalStream.listen((stream) {
      if (!mounted) return;
      if (_localRendererReady) {
        _localRenderer.srcObject = stream;
      }
      setState(() => _localStream = stream);
    });

    _errorSub = widget.callService.onError.listen((message) {
      if (!mounted) return;
      setState(() => _errorText = message);
    });

    if (!widget.isIncoming && widget.callService.sessionId == null) {
      // Outgoing call — start now
      _startCall();
    }
  }

  Future<void> _startCall() async {
    await widget.callService.startCall(
      conversationKey: widget.session.conversationKey,
      callType: widget.session.callType,
      calleeProfile: widget.session.calleeProfile.isNotEmpty
          ? widget.session.calleeProfile
          : null,
    );
  }

  Future<void> _initializeRemoteRenderer() async {
    await _remoteRenderer.initialize();
    if (!mounted) {
      await _remoteRenderer.dispose();
      return;
    }
    _remoteRenderer.srcObject = _remoteStream;
    setState(() => _remoteRendererReady = true);
  }

  Future<void> _initializeLocalRenderer() async {
    await _localRenderer.initialize();
    if (!mounted) {
      await _localRenderer.dispose();
      return;
    }
    _localRenderer.srcObject = _localStream;
    setState(() => _localRendererReady = true);
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
    _localStreamSub?.cancel();
    _errorSub?.cancel();
    _durationTimer?.cancel();
    _remoteRenderer.dispose();
    _localRenderer.dispose();
    super.dispose();
  }

  Future<void> _applyAudioRoute() {
    if (_isHeadsetPreferred) {
      return widget.callService.preferHeadsetOrBluetooth();
    }
    return widget.callService.setSpeakerOn(_isSpeakerOn);
  }

  Offset _clampLocalPreviewOffset(
    Offset raw,
    BoxConstraints constraints,
  ) {
    final maxX =
        (constraints.maxWidth - _localPreviewSize.width - _localPreviewMargin)
            .clamp(_localPreviewMargin, double.infinity)
            .toDouble();
    final maxY = (constraints.maxHeight -
            _localPreviewSize.height -
            _controlsReservedHeight)
        .clamp(_localPreviewMargin, double.infinity)
        .toDouble();
    return Offset(
      raw.dx.clamp(_localPreviewMargin, maxX).toDouble(),
      raw.dy.clamp(_localPreviewMargin, maxY).toDouble(),
    );
  }

  Widget _buildLocalPreviewOverlay() {
    if (!_isVideoCall || !_localRendererReady || _localStream == null) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fallback = Offset(
            constraints.maxWidth -
                _localPreviewSize.width -
                _localPreviewMargin,
            constraints.maxHeight -
                _localPreviewSize.height -
                _controlsReservedHeight,
          );
          final offset = _clampLocalPreviewOffset(
            _localPreviewOffset ?? fallback,
            constraints,
          );
          return Stack(
            children: [
              Positioned(
                left: offset.dx,
                top: offset.dy,
                width: _localPreviewSize.width,
                height: _localPreviewSize.height,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _localPreviewOffset = _clampLocalPreviewOffset(
                        offset + details.delta,
                        constraints,
                      );
                    });
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white70, width: 1),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: RTCVideoView(
                        _localRenderer,
                        mirror: true,
                        objectFit:
                            RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: callScreenBaseColor(widget.session.callType),
      body: Stack(
        children: [
          // Remote video (or placeholder)
          if (_remoteStream != null && _isVideoCall)
            Positioned.fill(
              child: RTCVideoView(
                _remoteRenderer,
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
                if (_errorText.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _errorText,
                      style: const TextStyle(
                        color: Color(0xFFFFC4C4),
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ],
            ),
          ),

          _buildLocalPreviewOverlay(),

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
              unawaited(widget.callService.setMicrophoneMuted(_isMuted));
            },
          ),
          const SizedBox(width: 16),
          // Headset / Bluetooth
          _CallButton(
            icon: Icons.headset_mic,
            color: _isHeadsetPreferred ? Colors.white : Colors.white38,
            label: 'Гарнитура',
            onTap: () {
              setState(() {
                _isHeadsetPreferred = true;
                _isSpeakerOn = false;
              });
              unawaited(widget.callService.preferHeadsetOrBluetooth());
            },
          ),
          const SizedBox(width: 16),
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
          const SizedBox(width: 16),
          // Speaker
          _CallButton(
            icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
            color: _isSpeakerOn ? Colors.white : Colors.white38,
            label: 'Динамик',
            onTap: () {
              setState(() {
                _isSpeakerOn = !_isSpeakerOn;
                if (_isSpeakerOn) {
                  _isHeadsetPreferred = false;
                }
              });
              unawaited(widget.callService.setSpeakerOn(_isSpeakerOn));
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
    return SizedBox(
      width: size < 68 ? 68 : size,
      child: Column(
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
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
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
