import 'package:family_todo_mobile/features/chat/chat_audio_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('falls back to English audio placeholder', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 220,
            child: ChatAudioBubble(
              audioUrl: '',
              text: '',
              mine: false,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Аудио'), findsNothing);
  });
}
