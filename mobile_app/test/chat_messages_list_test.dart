import 'package:family_todo_mobile/features/chat/chat_messages_list.dart';
import 'package:family_todo_mobile/models/chat_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens long human chat at the newest message', (tester) async {
    final messages = List.generate(
      120,
      (index) => _message(
        id: 'msg-$index',
        text: index < 80
            ? 'message-$index'
            : 'message-$index ${'long tail text ' * 24}',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 560,
            child: ChatMessagesList(
              messages: messages,
              owner: 'nik',
              compact: true,
              textFor: (message) => message.text,
              senderLabelFor: (profile) => profile,
              stickerAssetFor: (_) => '',
              imageUrlFor: (_) => '',
              onLongPress: (_) {},
              onImageTap: (_, __) {},
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(
      scrollable.position.pixels,
      scrollable.position.maxScrollExtent,
    );
    expect(find.textContaining('message-119'), findsOneWidget);
    expect(find.text('message-0'), findsNothing);
  });
}

ChatMessage _message({
  required String id,
  required String text,
}) {
  return ChatMessage(
    id: id,
    conversationKey: 'direct:nik:misha',
    senderProfile: id.hashCode.isEven ? 'nik' : 'misha',
    messageType: 'text',
    text: text,
    createdAt: '2026-06-08T10:00:00Z',
  );
}
