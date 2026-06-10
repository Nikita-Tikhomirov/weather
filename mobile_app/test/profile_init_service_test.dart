import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:family_todo_mobile/services/profile_init_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('initial profile prompt uses localized labels', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = _FakeApiClient();
    late BuildContext promptContext;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Builder(
          builder: (context) {
            promptContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final future = ProfileInitService.promptForInitialProfile(
      promptContext,
      api,
      (_, __) {},
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Sign in with phone number'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Вход по номеру телефона'), findsNothing);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(await future, 'profile-1');
  });
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://localhost', apiKey: 'test');

  @override
  Future<PhoneProfileSession> deviceStart({
    required String phone,
    required String deviceId,
    String displayName = '',
  }) async {
    return PhoneProfileSession(
      profileKey: 'profile-1',
      phone: phone,
      displayName: displayName,
      deviceId: deviceId,
      familyMembers: const [],
    );
  }
}
