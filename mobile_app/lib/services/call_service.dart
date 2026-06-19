import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../app/app_config.dart';
import '../models/call_models.dart';
import 'api_client.dart';
import 'telecom_call_integration.dart';

enum CallState {
  idle,
  calling,
  ringing,
  connected,
  ended,
}

String callSignalingErrorMessage(Object error) =>
    'Call signaling error: $error';

bool isVideoCallType(String callType) =>
    callType.trim().toLowerCase() == 'video';

bool callSpeakerStateAfterTap({
  required bool isVideoCall,
  required bool isSpeakerOn,
}) {
  return isVideoCall ? true : !isSpeakerOn;
}

AndroidAudioConfiguration buildCallAndroidAudioConfiguration() {
  return AndroidAudioConfiguration(
    manageAudioFocus: true,
    androidAudioMode: AndroidAudioMode.inCommunication,
    androidAudioFocusMode: AndroidAudioFocusMode.gain,
    androidAudioStreamType: AndroidAudioStreamType.voiceCall,
    androidAudioAttributesUsageType:
        AndroidAudioAttributesUsageType.voiceCommunication,
    androidAudioAttributesContentType: AndroidAudioAttributesContentType.speech,
    forceHandleAudioRouting: true,
  );
}

Map<String, dynamic> buildCallMediaConstraints(String callType) {
  final wantsVideo = isVideoCallType(callType);
  return {
    'audio': true,
    'video': wantsVideo
        ? {
            'facingMode': 'user',
            'width': {'ideal': 640, 'max': 960},
            'height': {'ideal': 360, 'max': 540},
            'frameRate': {'ideal': 20, 'max': 24},
          }
        : false,
  };
}

abstract interface class CallAudioDevice {
  Future<void> configureForCall(AndroidAudioConfiguration configuration);
  Future<void> setMicrophoneMuted(bool muted, MediaStreamTrack track);
  Future<void> setSpeakerOn(bool enabled);
  Future<void> preferHeadsetOrBluetooth();
  Future<void> clearCommunicationDevice();
}

class WebRtcCallAudioDevice implements CallAudioDevice {
  const WebRtcCallAudioDevice();

  @override
  Future<void> configureForCall(AndroidAudioConfiguration configuration) {
    return Helper.setAndroidAudioConfiguration(configuration);
  }

  @override
  Future<void> setMicrophoneMuted(bool muted, MediaStreamTrack track) {
    return Helper.setMicrophoneMute(muted, track);
  }

  @override
  Future<void> setSpeakerOn(bool enabled) {
    return Helper.setSpeakerphoneOn(enabled);
  }

  @override
  Future<void> preferHeadsetOrBluetooth() {
    return Helper.setSpeakerphoneOnButPreferBluetooth();
  }

  @override
  Future<void> clearCommunicationDevice() {
    return Helper.clearAndroidCommunicationDevice();
  }
}

Future<void> resetCallAudioRoute(CallAudioDevice audioDevice) async {
  try {
    await audioDevice.setSpeakerOn(false);
  } catch (_) {
    // Best-effort cleanup: the call is already ending.
  }
  try {
    await audioDevice.clearCommunicationDevice();
  } catch (_) {
    // Best-effort cleanup: some platforms do not expose this route API.
  }
}

Future<void> stopAndDisposeCallMediaStream(MediaStream? stream) async {
  if (stream == null) return;

  final tracks = List<MediaStreamTrack>.from(stream.getTracks());
  for (final track in tracks) {
    try {
      track.enabled = false;
    } catch (_) {
      // Some native tracks can already be closed by the peer connection.
    }
    try {
      await track.stop();
    } catch (_) {
      // Continue disposing the rest of the stream even if one track is stale.
    }
  }

  try {
    await stream.dispose();
  } catch (_) {
    // Ignore stale native stream handles during teardown.
  }
}

class CallIceServerConfig {
  static Map<String, dynamic> build({
    String turnUrls = AppConfig.turnUrls,
    String turnUsername = AppConfig.turnUsername,
    String turnCredential = AppConfig.turnCredential,
  }) {
    final iceServers = <Map<String, dynamic>>[
      {
        'urls': AppConfig.stunUrls,
      },
    ];
    final urls = turnUrls
        .split(',')
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    if (urls.isNotEmpty &&
        turnUsername.trim().isNotEmpty &&
        turnCredential.trim().isNotEmpty) {
      iceServers.add({
        'urls': urls,
        'username': turnUsername.trim(),
        'credential': turnCredential.trim(),
      });
    }
    return {'iceServers': iceServers};
  }
}

class CallService {
  CallService({
    required this.api,
    required this.actorProfile,
    CallAudioDevice? audioDevice,
    TelecomCallIntegration telecom = const TelecomCallIntegration(),
  })  : _audioDevice = audioDevice ?? const WebRtcCallAudioDevice(),
        _telecom = telecom;

  final ApiClient api;
  final String actorProfile;
  final CallAudioDevice _audioDevice;
  final TelecomCallIntegration _telecom;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  CallSession? _currentSession;
  String? _sessionId;
  String _signalCursor = '0';
  Timer? _signalPoller;
  Timer? _ringingTimer;
  Timer? _disconnectTimer;
  final List<RTCIceCandidate> _pendingRemoteCandidates = <RTCIceCandidate>[];
  bool _hasRemoteDescription = false;
  bool _disposed = false;
  String _currentCallType = 'audio';
  bool _speakerOn = false;
  bool _headsetPreferred = false;

  CallState _state = CallState.idle;
  CallState get state => _state;
  String? get sessionId => _sessionId;
  CallSession? get currentSession => _currentSession;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  final _stateController = StreamController<CallState>.broadcast();
  Stream<CallState> get onStateChange => _stateController.stream;

  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get onRemoteStream => _remoteStreamController.stream;

  final _localStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get onLocalStream => _localStreamController.stream;

  final _errorController = StreamController<String>.broadcast();
  Stream<String> get onError => _errorController.stream;

  // Callbacks for UI
  void Function(CallSession session)? onIncomingCall;
  void Function()? onCallEnded;

  /// Start an outgoing call
  Future<void> startCall({
    required String conversationKey,
    String callType = 'audio',
    String? calleeProfile,
  }) async {
    if (_state != CallState.idle && _state != CallState.ended) return;

    _state = CallState.calling;
    _stateController.add(_state);
    CallSession? session;

    try {
      session = await api.callInitiate(
        actorProfile: actorProfile,
        conversationKey: conversationKey,
        callType: callType,
        calleeProfile: calleeProfile,
      );

      _sessionId = session.sessionId;
      _currentSession = session;
      if (!_stateController.isClosed) {
        _stateController.add(_state);
      }

      _resetAudioRoutePreference(callType);
      await _prepareAudioSession();
      await _applyCurrentAudioRoute();

      // Create peer connection and local stream
      await _createPeerConnection();
      await _openLocalMedia(callType: callType);
      await _applyCurrentAudioRoute();

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
      final sid = session?.sessionId;
      if (sid != null && sid.isNotEmpty) {
        try {
          await api.callEnd(actorProfile: actorProfile, sessionId: sid);
        } catch (_) {
          // best-effort cleanup — server will time out anyway
        }
      }
      _setState(CallState.ended);
      _errorController.add('Failed to start call: $e');
      await _cleanup();
    }
  }

  /// Accept an incoming call
  Future<void> acceptCall(String sessionId, {String callType = 'audio'}) async {
    if (_state != CallState.ringing && _state != CallState.idle) return;

    _setState(CallState.calling);
    _sessionId = sessionId;
    unawaited(_telecom.answerIncomingConnection(sessionId));

    try {
      final session = await api.callAccept(
        actorProfile: actorProfile,
        sessionId: sessionId,
      );
      _currentSession = session;
      if (!_stateController.isClosed) {
        _stateController.add(_state);
      }

      _resetAudioRoutePreference(callType);
      await _prepareAudioSession();
      await _applyCurrentAudioRoute();
      await _createPeerConnection();
      await _openLocalMedia(callType: callType);
      await _applyCurrentAudioRoute();

      // Start polling for offer
      _startSignalPolling();
    } catch (e) {
      try {
        await api.callEnd(actorProfile: actorProfile, sessionId: sessionId);
      } catch (_) {
        // best-effort cleanup — server will time out anyway
      }
      _setState(CallState.ended);
      _errorController.add('Failed to accept call: $e');
      await _cleanup();
    }
  }

  /// Reject incoming call
  Future<void> rejectCall(String sessionId) async {
    unawaited(_telecom.rejectIncomingConnection(sessionId));
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
      unawaited(_telecom.endIncomingConnection(sid));
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
    if (_state != CallState.idle && _state != CallState.ended) return;
    _sessionId = session.sessionId;
    _currentSession = session;
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
    _disposed = true;
    unawaited(_cleanup(notifyStreams: false));
    _stateController.close();
    _remoteStreamController.close();
    _localStreamController.close();
    _errorController.close();
  }

  Future<void> _createPeerConnection() async {
    _pc = await createPeerConnection(CallIceServerConfig.build());

    _pc!.onIceCandidate = (candidate) {
      if (_sessionId == null) return;
      api.callSignal(
        actorProfile: actorProfile,
        sessionId: _sessionId!,
        signalType: 'ice_candidate',
        candidate: candidate.toMap(),
      );
    };

    _pc!.onTrack = (event) {
      if (event.streams.isEmpty) return;
      _remoteStream = event.streams.first;
      if (!_disposed && !_remoteStreamController.isClosed) {
        _remoteStreamController.add(_remoteStream);
      }
    };

    _pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _disconnectTimer?.cancel();
        _disconnectTimer = null;
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _setState(CallState.ended);
        onCallEnded?.call();
        _cleanup();
        return;
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _disconnectTimer?.cancel();
        _disconnectTimer = Timer(const Duration(seconds: 8), () {
          if (_pc == null || _state == CallState.ended) return;
          _setState(CallState.ended);
          onCallEnded?.call();
          _cleanup();
        });
      }
    };
  }

  Future<void> _openLocalMedia({required String callType}) async {
    final wantsVideo = isVideoCallType(callType);

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(
        buildCallMediaConstraints(callType),
      );
    } catch (e) {
      if (wantsVideo) {
        _errorController.add('Camera unavailable, continuing with audio');
        _localStream = await navigator.mediaDevices.getUserMedia(
          buildCallMediaConstraints('audio'),
        );
      } else {
        rethrow;
      }
    }
    if (_disposed) {
      _localStream?.getTracks().forEach((track) => track.stop());
      _localStream?.dispose();
      _localStream = null;
      return;
    }
    if (!_localStreamController.isClosed) {
      _localStreamController.add(_localStream);
    }
    await _addLocalTracks();
  }

  Future<void> _prepareAudioSession() async {
    try {
      await _audioDevice.configureForCall(
        buildCallAndroidAudioConfiguration(),
      );
    } catch (_) {
      // The call can still proceed; route buttons remain available in the UI.
    }
  }

  void _resetAudioRoutePreference(String callType) {
    _currentCallType = callType;
    _speakerOn = isVideoCallType(callType);
    _headsetPreferred = false;
  }

  Future<void> _applyCurrentAudioRoute() async {
    try {
      if (_headsetPreferred) {
        await _audioDevice.preferHeadsetOrBluetooth();
        return;
      }
      await _audioDevice.setSpeakerOn(_speakerOn);
    } catch (_) {
      // Route changes are best effort; the call itself should keep going.
    }
  }

  Future<void> _addLocalTracks() async {
    final stream = _localStream;
    final pc = _pc;
    if (stream == null || pc == null) return;

    for (final track in stream.getTracks()) {
      await pc.addTrack(track, stream);
    }
  }

  Future<void> setMicrophoneMuted(bool muted) async {
    final tracks = _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[];
    for (final track in tracks) {
      track.enabled = !muted;
      await _audioDevice.setMicrophoneMuted(muted, track);
    }
  }

  Future<void> setSpeakerOn(bool enabled) async {
    final nextSpeakerOn = isVideoCallType(_currentCallType) ? true : enabled;
    _headsetPreferred = false;
    _speakerOn = nextSpeakerOn;
    await _applyCurrentAudioRoute();
  }

  Future<void> preferHeadsetOrBluetooth() async {
    _headsetPreferred = true;
    _speakerOn = false;
    await _applyCurrentAudioRoute();
  }

  void _startSignalPolling() {
    _signalPoller?.cancel();
    unawaited(_pollSignals());
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
    } catch (e) {
      _errorController.add(callSignalingErrorMessage(e));
    }
  }

  Future<void> _handleOffer(CallSignal signal) async {
    final sdp = signal.sdp;
    if (sdp == null) return;

    final sdpMap = sdp is Map ? Map<String, dynamic>.from(sdp) : sdp;
    await _pc!.setRemoteDescription(
      RTCSessionDescription(sdpMap['sdp'], sdpMap['type']),
    );
    _hasRemoteDescription = true;
    await _flushPendingRemoteCandidates();

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);

    await api.callSignal(
      actorProfile: actorProfile,
      sessionId: _sessionId!,
      signalType: 'answer',
      sdp: answer.toMap(),
    );

    _setState(CallState.connected);
    await _applyCurrentAudioRoute();
  }

  Future<void> _handleAnswer(CallSignal signal) async {
    final sdp = signal.sdp;
    if (sdp == null) return;

    final sdpMap = sdp is Map ? Map<String, dynamic>.from(sdp) : sdp;
    await _pc!.setRemoteDescription(
      RTCSessionDescription(sdpMap['sdp'], sdpMap['type']),
    );
    _hasRemoteDescription = true;
    await _flushPendingRemoteCandidates();

    _setState(CallState.connected);
    await _applyCurrentAudioRoute();
  }

  Future<void> _handleIceCandidate(CallSignal signal) async {
    final candidate = signal.candidate;
    if (candidate == null) return;

    final candMap =
        candidate is Map ? Map<String, dynamic>.from(candidate) : candidate;
    final remoteCandidate = RTCIceCandidate(
      candMap['candidate'],
      candMap['sdpMid'],
      candMap['sdpMLineIndex'],
    );
    if (!_hasRemoteDescription) {
      _pendingRemoteCandidates.add(remoteCandidate);
      return;
    }

    await _pc!.addCandidate(remoteCandidate);
  }

  Future<void> _flushPendingRemoteCandidates() async {
    if (_pc == null || !_hasRemoteDescription) return;
    final pending = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      try {
        await _pc!.addCandidate(candidate);
      } catch (_) {
        // Ignore stale or malformed ICE from older attempts.
      }
    }
  }

  void _setState(CallState newState) {
    if (_state == newState) return;
    _state = newState;
    if (_stateController.isClosed) return;
    _stateController.add(newState);
  }

  Future<void> _cleanup({bool notifyStreams = true}) async {
    _signalPoller?.cancel();
    _signalPoller = null;
    _ringingTimer?.cancel();
    _ringingTimer = null;
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
    _pendingRemoteCandidates.clear();
    _hasRemoteDescription = false;

    final localStream = _localStream;
    final remoteStream = _remoteStream;
    final pc = _pc;
    _localStream = null;
    _remoteStream = null;
    _pc = null;

    if (pc != null) {
      try {
        await pc.close();
      } catch (_) {
        // The media tracks are still stopped below.
      }
    }

    await stopAndDisposeCallMediaStream(localStream);
    if (!identical(remoteStream, localStream)) {
      await stopAndDisposeCallMediaStream(remoteStream);
    }
    await resetCallAudioRoute(_audioDevice);

    if (notifyStreams && !_disposed) {
      if (!_remoteStreamController.isClosed) {
        _remoteStreamController.add(null);
      }
      if (!_localStreamController.isClosed) {
        _localStreamController.add(null);
      }
    }
    _sessionId = null;
    _currentSession = null;
    _remoteStream = null;
    _signalCursor = '0';
    _currentCallType = 'audio';
    _speakerOn = false;
    _headsetPreferred = false;
  }
}
