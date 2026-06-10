import 'package:family_todo_mobile/app/family_todo_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('configures generated localizations for supported locales', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const FamilyTodoApp(
        home: SizedBox.shrink(),
      ),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));

    expect(app.title, isEmpty);
    expect(app.onGenerateTitle, isNotNull);
    expect(app.locale, const Locale('ru'));
    expect(app.localizationsDelegates, isNotNull);
    expect(app.localizationsDelegates!.length, greaterThanOrEqualTo(4));
    expect(
      app.supportedLocales,
      containsAll(const [
        Locale('ru'),
        Locale('en'),
      ]),
    );
  });
}
