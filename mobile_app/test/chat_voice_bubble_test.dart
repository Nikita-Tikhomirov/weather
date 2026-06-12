import 'package:family_todo_mobile/features/chat/chat_voice_bubble.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses localized voice playback tooltip', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const Scaffold(
          body: VoiceBubble(
            url: '/chat/media/voice-1',
            durationMs: 2400,
            mine: false,
          ),
        ),
      ),
    );

    expect(find.byTooltip('Play voice message'), findsOneWidget);
    expect(find.byTooltip('Воспроизвести'), findsNothing);
  });
}
