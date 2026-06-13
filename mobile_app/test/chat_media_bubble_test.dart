import 'package:family_todo_mobile/features/chat/chat_media_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows English video load fallback on invalid URL', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VideoPlayerScreen(url: 'http://[bad-url'),
      ),
    );
    await tester.pump();

    expect(find.text('Could not load video'), findsOneWidget);
    expect(find.text('Не удалось загрузить видео'), findsNothing);
  });
}
