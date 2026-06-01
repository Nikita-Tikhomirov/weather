import 'package:family_todo_mobile/services/api_client.dart';
import 'package:family_todo_mobile/services/call_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class _NoopApi extends ApiClient {
  _NoopApi() : super(baseUrl: 'http://localhost', apiKey: 'test');
}

class _RecordingCallAudioDevice implements CallAudioDevice {
  final speakerValues = <bool>[];
  var clearCommunicationDeviceCount = 0;
  var configureCount = 0;

  @override
  Future<void> clearCommunicationDevice() async {
    clearCommunicationDeviceCount += 1;
  }

  @override
  Future<void> configureForCall(AndroidAudioConfiguration configuration) async {
    configureCount += 1;
  }

  @override
  Future<void> preferHeadsetOrBluetooth() async {}

  @override
  Future<void> setMicrophoneMuted(
    bool muted,
    MediaStreamTrack track,
  ) async {}

  @override
  Future<void> setSpeakerOn(bool enabled) async {
    speakerValues.add(enabled);
  }
}

class _FakeMediaStream extends MediaStream {
  _FakeMediaStream(this.tracks) : super('stream-1', 'test');

  final List<MediaStreamTrack> tracks;
  var disposed = false;

  @override
  bool? get active => !disposed;

  @override
  Future<void> addTrack(
    MediaStreamTrack track, {
    bool addToNative = true,
  }) async {
    tracks.add(track);
  }

  @override
  Future<MediaStream> clone() async => _FakeMediaStream(List.of(tracks));

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  List<MediaStreamTrack> getAudioTracks() =>
      tracks.where((track) => track.kind == 'audio').toList();

  @override
  Future<void> getMediaTracks() async {}

  @override
  List<MediaStreamTrack> getTracks() => List.of(tracks);

  @override
  List<MediaStreamTrack> getVideoTracks() =>
      tracks.where((track) => track.kind == 'video').toList();

  @override
  Future<void> removeTrack(
    MediaStreamTrack track, {
    bool removeFromNative = true,
  }) async {
    tracks.remove(track);
  }
}

class _FakeMediaStreamTrack extends MediaStreamTrack {
  _FakeMediaStreamTrack(this.trackKind);

  final String trackKind;
  var enabledValue = true;
  var stopped = false;

  @override
  String get id => '$trackKind-track';

  @override
  String get label => '$trackKind track';

  @override
  String get kind => trackKind;

  @override
  bool get enabled => enabledValue;

  @override
  set enabled(bool value) {
    enabledValue = value;
  }

  @override
  bool? get muted => !enabledValue;

  @override
  Future<void> dispose() => stop();

  @override
  Map<String, dynamic> getSettings() => const {};

  @override
  Future<void> stop() async {
    stopped = true;
  }
}

void main() {
  test('endCall resets speakerphone and Android communication device',
      () async {
    final audioDevice = _RecordingCallAudioDevice();
    final service = CallService(
      api: _NoopApi(),
      actorProfile: 'nik',
      audioDevice: audioDevice,
    );

    await service.endCall();

    expect(audioDevice.speakerValues, contains(false));
    expect(audioDevice.clearCommunicationDeviceCount, 1);
    service.dispose();
  });

  test('stopAndDisposeCallMediaStream disables and stops every track',
      () async {
    final audioTrack = _FakeMediaStreamTrack('audio');
    final videoTrack = _FakeMediaStreamTrack('video');
    final stream = _FakeMediaStream([audioTrack, videoTrack]);

    await stopAndDisposeCallMediaStream(stream);

    expect(audioTrack.enabled, isFalse);
    expect(videoTrack.enabled, isFalse);
    expect(audioTrack.stopped, isTrue);
    expect(videoTrack.stopped, isTrue);
    expect(stream.disposed, isTrue);
  });
}
