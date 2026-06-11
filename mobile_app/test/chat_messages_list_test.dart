import 'package:family_todo_mobile/features/chat/chat_messages_list.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
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

  testWidgets('uses localized deleted message label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatMessagesList(
            messages: [
              _message(
                id: 'deleted-msg',
                text: '',
                deletedAt: '2026-06-08T10:05:00Z',
              ),
            ],
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
    );

    expect(find.text('Message deleted'), findsOneWidget);
  });

  testWidgets('uses localized image placeholder', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatMessagesList(
            messages: [
              _message(
                id: 'image-msg',
                text: '',
                messageType: 'image',
              ),
            ],
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
    );

    expect(find.text('Image'), findsOneWidget);
    expect(find.text('Изображение'), findsNothing);
  });

  testWidgets('uses localized edited message footer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatMessagesList(
            messages: [
              _message(
                id: 'edited-msg',
                text: 'edited body',
                editedAt: '2026-06-08T10:05:00Z',
              ),
            ],
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
    );

    expect(find.textContaining('· edited'), findsOneWidget);
    expect(find.textContaining(RegExp('[А-Яа-яЁё]')), findsNothing);
  });

  testWidgets('uses localized upload phase label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatMessagesList(
            messages: [
              _message(
                id: 'upload-msg',
                text: '',
                messageType: 'image',
                isUploading: true,
                uploadProgress: 0.75,
              ),
            ],
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
    );

    expect(find.text('Sending... 75%'), findsOneWidget);
    expect(find.text('Отправка... 75%'), findsNothing);
  });
}

ChatMessage _message({
  required String id,
  required String text,
  String messageType = 'text',
  String? deletedAt,
  String? editedAt,
  bool isUploading = false,
  double uploadProgress = 0.0,
}) {
  return ChatMessage(
    id: id,
    conversationKey: 'direct:nik:misha',
    senderProfile: id.hashCode.isEven ? 'nik' : 'misha',
    messageType: messageType,
    text: text,
    createdAt: '2026-06-08T10:00:00Z',
    deletedAt: deletedAt,
    editedAt: editedAt,
    isUploading: isUploading,
    uploadProgress: uploadProgress,
  );
}
