import 'package:family_todo_mobile/features/chat/call_screen.dart';
import 'package:family_todo_mobile/services/call_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('audio call screen does not use a black base surface', () {
    expect(callScreenBaseColor('audio'), isNot(Colors.black));
    expect(callScreenBaseColor('video'), Colors.black);
  });

  test('audio calls request plain audio-only media constraints', () {
    expect(
      buildCallMediaConstraints('audio'),
      containsPair('audio', true),
    );
    expect(
      buildCallMediaConstraints('audio'),
      containsPair('video', false),
    );
  });

  test('call audio session uses Android communication routing', () {
    final config = buildCallAndroidAudioConfiguration().toMap();

    expect(config['manageAudioFocus'], isTrue);
    expect(config['androidAudioMode'], 'inCommunication');
    expect(config['androidAudioStreamType'], 'voiceCall');
    expect(config['androidAudioAttributesUsageType'], 'voiceCommunication');
  });

  test('call audio routing is forced while Android is in communication mode',
      () {
    final config = buildCallAndroidAudioConfiguration().toMap();

    expect(config['forceHandleAudioRouting'], isTrue);
  });

  test('video speaker control never switches to earpiece', () {
    expect(
      callSpeakerStateAfterTap(isVideoCall: true, isSpeakerOn: true),
      isTrue,
    );
    expect(
      callSpeakerStateAfterTap(isVideoCall: true, isSpeakerOn: false),
      isTrue,
    );
    expect(
      callSpeakerStateAfterTap(isVideoCall: false, isSpeakerOn: true),
      isFalse,
    );
  });
}
