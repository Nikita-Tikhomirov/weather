import 'package:family_todo_mobile/features/family/family_view.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses localized filter and empty-state labels', (tester) async {
    var selectedFilter = '';

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: FamilyView(
            familyTasks: const [],
            familyFilter: 'upcoming',
            labelFor: (profile) => profile,
            onFilterChanged: (value) => selectedFilter = value,
            onEdit: (_) async {},
            onDelete: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Family Tasks'), findsOneWidget);
    expect(find.text('No tasks match this filter'), findsOneWidget);

    await tester.tap(find.text('Overdue'));
    expect(selectedFilter, 'overdue');
  });
}
