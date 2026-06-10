# Mobile I18n Debt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the concrete remaining mobile technical-debt item by wiring the existing ARB localization files into the Flutter app.

**Architecture:** Keep localization at the app shell boundary. `FamilyTodoApp` owns `MaterialApp`, so it should expose generated localization delegates, supported locales, and a localized app title without changing feature state or storage code.

**Tech Stack:** Flutter, `flutter_localizations`, generated `AppLocalizations`, `flutter_test`.

---

### Task 1: App Shell Localization

**Files:**
- Modify: `mobile_app/lib/app/family_todo_app.dart`
- Generate: `mobile_app/lib/l10n/app_localizations.dart`
- Generate: `mobile_app/lib/l10n/app_localizations_en.dart`
- Generate: `mobile_app/lib/l10n/app_localizations_ru.dart`
- Create: `mobile_app/test/family_todo_app_test.dart`

- [x] **Step 1: Write the failing test**

```dart
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
```

- [x] **Step 2: Run test to verify it fails**

Run: `C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat test test/family_todo_app_test.dart`

Expected: FAIL because `FamilyTodoApp` has no `home` injection yet, then fails on missing `locale`.

- [x] **Step 3: Wire generated localizations into `MaterialApp`**

```dart
import '../l10n/app_localizations.dart';

return MaterialApp(
  onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
  locale: const Locale('ru'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  debugShowCheckedModeBanner: false,
  theme: buildAppTheme(option),
  home: widget.home ??
      HomePage(
        selectedThemeKey: option.key,
        onThemeChanged: _setTheme,
      ),
);
```

- [x] **Step 4: Run test to verify it passes**

Run: `C:\Users\user\.puro\envs\stable\flutter\bin\flutter.bat test test/family_todo_app_test.dart`

Expected: PASS.

- [x] **Step 5: Run analyzer before commit**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\run_flutter_checks.ps1 -SkipTests -Retries 1`

Expected: analyzer exits 0.

Commit after successful verification: `fix: wire mobile app localizations`
