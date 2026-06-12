import 'package:family_todo_mobile/features/chat/chat_sticker_bubble.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses localized unavailable sticker label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ChatStickerBubble(
            stickerAssetUrl: '',
            text: '',
            compact: true,
          ),
        ),
      ),
    );

    expect(find.text('Sticker unavailable'), findsOneWidget);
    expect(find.text('Стикер недоступен'), findsNothing);
  });
}
