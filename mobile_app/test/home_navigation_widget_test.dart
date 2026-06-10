import 'package:family_todo_mobile/features/home/home_navigation_widget.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _localizedApp(Widget child) {
  return MaterialApp(
    locale: const Locale('ru'),
    theme: ThemeData(
      splashFactory: NoSplash.splashFactory,
    ),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      bottomNavigationBar: child,
    ),
  );
}

void main() {
  testWidgets('shows localized task manager destinations', (tester) async {
    final pageIndex = ValueNotifier<int>(0);
    addTearDown(pageIndex.dispose);

    await tester.pumpWidget(
      _localizedApp(
        HomeNavigationBar(
          pageIndex: pageIndex,
          canUseTaskManager: true,
          onPageSelected: (value) => pageIndex.value = value,
        ),
      ),
    );

    expect(find.text('Задачи'), findsOneWidget);
    expect(find.text('Календарь'), findsOneWidget);
    expect(find.text('Мессенджер'), findsOneWidget);
  });

  testWidgets('routes messenger-only users to messenger page', (tester) async {
    final pageIndex = ValueNotifier<int>(0);
    addTearDown(pageIndex.dispose);

    await tester.pumpWidget(
      _localizedApp(
        HomeNavigationBar(
          pageIndex: pageIndex,
          canUseTaskManager: false,
          onPageSelected: (value) => pageIndex.value = value,
        ),
      ),
    );

    await tester.tap(find.text('Мессенджер'));

    expect(pageIndex.value, 2);
  });

  testWidgets('shows localized add task label only on tasks page', (
    tester,
  ) async {
    final pageIndex = ValueNotifier<int>(0);
    var opened = false;
    addTearDown(pageIndex.dispose);

    await tester.pumpWidget(
      _localizedApp(
        HomeTaskFloatingActionButton(
          pageIndex: pageIndex,
          canUseTaskManager: true,
          onPressed: () => opened = true,
        ),
      ),
    );

    expect(find.text('Добавить задачу'), findsOneWidget);

    await tester.tap(find.text('Добавить задачу'));
    expect(opened, isTrue);

    pageIndex.value = 1;
    await tester.pump();

    expect(find.byType(FloatingActionButton), findsNothing);
  });
}
