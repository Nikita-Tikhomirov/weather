import 'package:family_todo_mobile/features/chat/sticker_picker_sheet.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses localized labels for an empty sticker picker',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: StickerPickerSheet(
              packs: const [],
              assetUrlResolver: (value) => value,
              onStickerSelected: (_) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Stickers'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('No stickers loaded yet'), findsOneWidget);
  });
}
