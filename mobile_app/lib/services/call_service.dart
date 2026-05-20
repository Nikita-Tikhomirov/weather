import 'dart:async';
import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/call_models.dart';
import 'api_client.dart';

enum CallState {
  idle,
  calling,
  ringing,
  connected,
  ended,
}

class CallService {
  CallService({required this.api, required this.actorProfile});

  final ApiClient api;
  final String actorProfile;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _sessionId;
  String _signalCursor = '0';
  Timer? _signalPoller;
  Timer? _ringingTimer;

  CallState _state = CallState.idle;
  CallState get state => _state;
  String? get sessionId => _sessionId;

  final _stateController = StreamController<CallState>.broadcast();
  Stream<CallState> get onStateChange => _stateController.stream;

  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get onRemoteStream => _remoteStreamController.stream;

  final _errorController = StreamController<String>.broadcast();
  Stream<String> get onError => _errorController.stream;

  // Callbacks for UI
  void Function(CallSession session)? onIncomingCall;
  void Function()? onCallEnded;

  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  /// Start an outgoing call
  Future<void> startCall({
    required String conversationKey,
    String callType = 'audio',
    String? calleeProfile,
  }) async {
    if (_state != CallState.idle) return;

    _state = CallState.calling;
    _stateController.add(_state);

    try {
      final session = await api.callInitiate(
        actorProfile: actorProfile,
        conversationKey: conversationKey,
        callType: callType,
        calleeProfile: calleeProfile,
      );

      _sessionId = session.sessionId;

      // Create peer connection and local stream
      await _createPeerConnection();
      await _openLocalMedia(callType: callType);

      // Create and send offer
      final offer = await _pc!.createOffer();
      await _pc!.setLocalDescription(offer);

      // Send offer via signaling
      await api.callSignal(
        actorProfile: actorProfile,
        sessionId: _sessionId!,
        signalType: 'offer',
        sdp: offer.toMap(),
      );

      // Start polling for answer + ICE
      _startSignalPolling();
    } catch (e) {
      _setState(CallState.ended);
      _errorController.add('Failed to start call: $e');
      await _cleanup();
    }
  }

  /// Accept an incoming call
  Future<void> acceptCall(String sessionId, {String callType = 'audio'}) async {
    if (_state != CallState.ringing && _state != CallState.idle) return;

    _state = CallState.connected;
    _stateController.add(_state);
    _sessionId = sessionId;

    try {
      await api.callAccept(
        actorProfile: actorProfile,
        sessionId: sessionId,
      );

      await _createPeerConnection();
      await _openLocalMedia(callType: callType);

      // Start polling for offer
      _startSignalPolling();
    } catch (e) {
      _setState(CallState.ended);
      _errorController.add('Failed to accept call: $e');
      await _cleanup();
    }
  }

  /// Reject incoming call
  Future<void> rejectCall(String sessionId) async {
    try {
      await api.callReject(
        actorProfile: actorProfile,
        sessionId: sessionId,
      );
    } catch (_) {
      // Best-effort
    }
    _setState(CallState.ended);
    await _cleanup();
  }

  /// End active call
  Future<void> endCall() async {
    final sid = _sessionId;
    if (sid != null) {
      try {
        await api.callEnd(
          actorProfile: actorProfile,
          sessionId: sid,
        );
      } catch (_) {
        // Best-effort
      }
    }
    _setState(CallState.ended);
    await _cleanup();
  }

  /// Called when FCM push indicates incoming call
  void notifyIncomingCall(CallSession session) {
    if (_state != CallState.idle) return;
    _sessionId = session.sessionId;
    _state = CallState.ringing;
    _stateController.add(_state);
    onIncomingCall?.call(session);

    // Auto-reject after 60 seconds if not answered
    _ringingTimer?.cancel();
    _ringingTimer = Timer(const Duration(seconds: 60), () async {
      if (_state == CallState.ringing) {
        await rejectCall(session.sessionId);
      }
    });
  }

  void dispose() {
    _cleanup();
    _stateController.close();
    _remoteStreamController.close();
    _errorController.close();
  }

  Future<void> _createPeerConnection() async {
    _pc = await createPeerConnection(_iceServers);

    _pc!.onIceCandidate = (candidate) {
      if (_sessionId == null) return;
      api.callSignal(
        actorProfile: actorProfile,
        sessionId: _sessionId!,
        signalType: 'ice_candidate',
        candidate: candidate.toMap(),
      );
    };

    _pc!.onAddStream = (stream) {
      _remoteStream = stream;
      _remoteStreamController.add(stream);
    };

    _pc!.onTrack = (track) {
      // Handled by onAddStream
    };

    _pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _setState(CallState.ended);
        onCallEnded?.call();
        _cleanup();
      }
    };
  }

  Future<void> _openLocalMedia({required String callType}) async {
    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': callType == 'video',
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      if (_localStream != null && _pc != null) {
        _pc!.addStream(_localStream!);
      }
    } catch (e) {
      // Audio-only fallback
      if (callType == 'video') {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
        if (_localStream != null && _pc != null) {
          _pc!.addStream(_localStream!);
        }
      }
    }
  }

  void _startSignalPolling() {
    _signalPoller?.cancel();
    _signalPoller = Timer.periodic(const Duration(milliseconds: 800), (_) {
      _pollSignals();
    });
  }

  Future<void> _pollSignals() async {
    if (_sessionId == null || _pc == null) return;

    try {
      final result = await api.callPollSignals(
        actorProfile: actorProfile,
        sessionId: _sessionId!,
        cursor: _signalCursor,
      );

      _signalCursor = result.cursor;

      if (result.sessionStatus == 'ended' ||
          result.sessionStatus == 'rejected') {
        _setState(CallState.ended);
        onCallEnded?.call();
        await _cleanup();
        return;
      }

      for (final signal in result.signals) {
        await _handleSignal(signal);
      }
    } catch (_) {
      // Silently retry on next poll
    }
  }

  Future<void> _handleSignal(CallSignal signal) async {
    if (_pc == null) return;

    try {
      switch (signal.signalType) {
        case 'offer':
          await _handleOffer(signal);
          break;
        case 'answer':
          await _handleAnswer(signal);
          break;
        case 'ice_candidate':
          await _handleIceCandidate(signal);
          break;
        case 'hangup':
          _setState(CallState.ended);
          onCallEnded?.call();
          await _cleanup();
          break;
      }
    } catch (_) {
      // Skip bad signals
    }
  }

  Future<void> _handleOffer(CallSignal signal) async {
    final sdp = signal.sdp;
    if (sdp == null) return;

    final sdpMap = sdp is Map ? Map<String, dynamic>.from(sdp) : sdp;
    await _pc!.setRemoteDescription(
      RTCSessionDescription(sdpMap['sdp'], sdpMap['type']),
    );

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);

    await api.callSignal(
      actorProfile: actorProfile,
      sessionId: _sessionId!,
      signalType: 'answer',
      sdp: answer.toMap(),
    );

    _setState(CallState.connected);
  }

  Future<void> _handleAnswer(CallSignal signal) async {
    final sdp = signal.sdp;
    if (sdp == null) return;

    final sdpMap = sdp is Map ? Map<String, dynamic>.from(sdp) : sdp;
    await _pc!.setRemoteDescription(
      RTCSessionDescription(sdpMap['sdp'], sdpMap['type']),
    );

    _setState(CallState.connected);
  }

  Future<void> _handleIceCandidate(CallSignal signal) async {
    final candidate = signal.candidate;
    if (candidate == null) return;

    final candMap =
        candidate is Map ? Map<String, dynamic>.from(candidate) : candidate;
    await _pc!.addCandidate(
      RTCIceCandidate(
        candMap['candidate'],
        candMap['sdpMid'],
        candMap['sdpMLineIndex'],
      ),
    );
  }

  void _setState(CallState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(newState);
  }

  Future<void> _cleanup() async {
    _signalPoller?.cancel();
    _signalPoller = null;
    _ringingTimer?.cancel();
    _ringingTimer = null;

    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) => track.stop());
      _localStream!.dispose();
      _localStream = null;
    }

    if (_pc != null) {
      await _pc!.close();
      _pc = null;
    }

    _remoteStream = null;
    _remoteStreamController.add(null);
    _sessionId = null;
    _signalCursor = '0';
  }
}
