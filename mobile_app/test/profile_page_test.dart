import 'package:family_todo_mobile/features/profile/profile_page.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:family_todo_mobile/models/agent_policy.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses localized profile labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: ProfilePage(
          api: ApiClient(baseUrl: 'http://localhost', apiKey: 'test'),
          displayName: 'Nikita',
          phone: '+10000000000',
          profileKey: 'nik',
          avatarUrl: null,
          accessPolicy: const UserAccessPolicy(
            phone: '+10000000000',
            profileKey: 'nik',
            roles: ['admin'],
            capabilities: ['workspaces.grant_access'],
            workspaces: [],
            isSuperadmin: false,
          ),
          onAvatarChanged: (_) {},
          onDisplayNameChanged: (_) {},
          onOpenAdmin: () {},
        ),
      ),
    );

    expect(find.text('Profile'), findsWidgets);
    expect(find.text('Change photo'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Save name'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('Administration'), findsOneWidget);
    expect(
      find.text('Users, projects, workspaces, and agent roles'),
      findsOneWidget,
    );
  });

  testWidgets('falls back to English profile labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: ProfilePage(
          api: ApiClient(baseUrl: 'http://localhost', apiKey: 'test'),
          displayName: 'Nikita',
          phone: '+10000000000',
          profileKey: 'nik',
          avatarUrl: null,
          accessPolicy: const UserAccessPolicy(
            phone: '+10000000000',
            profileKey: 'nik',
            roles: ['admin'],
            capabilities: ['workspaces.grant_access'],
            workspaces: [],
            isSuperadmin: false,
          ),
          onAvatarChanged: (_) {},
          onDisplayNameChanged: (_) {},
          onOpenAdmin: () {},
        ),
      ),
    );

    expect(find.text('Profile'), findsWidgets);
    expect(find.text('Change photo'), findsOneWidget);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('Save name'), findsOneWidget);
    expect(find.text('Phone'), findsOneWidget);
    expect(find.text('Administration'), findsOneWidget);
    expect(
      find.text('Users, projects, workspaces, and agent roles'),
      findsOneWidget,
    );
    expect(find.text('Профиль'), findsNothing);
    expect(find.text('Изменить фото'), findsNothing);
  });

  testWidgets('opens Android system call account settings when disabled',
      (tester) async {
    const channel = MethodChannel('family_todo_mobile/telecom');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'registerPhoneAccounts':
          return true;
        case 'isManagedPhoneAccountEnabled':
          return false;
        case 'canUseFullScreenIntent':
          return true;
        case 'openPhoneAccountSettings':
          return true;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: ProfilePage(
          api: ApiClient(baseUrl: 'http://localhost', apiKey: 'test'),
          displayName: 'Nikita',
          phone: '+10000000000',
          profileKey: 'nik',
          avatarUrl: null,
          accessPolicy: const UserAccessPolicy(
            phone: '+10000000000',
            profileKey: 'nik',
            roles: ['admin'],
            capabilities: ['workspaces.grant_access'],
            workspaces: [],
            isSuperadmin: false,
          ),
          onAvatarChanged: (_) {},
          onDisplayNameChanged: (_) {},
          onOpenAdmin: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('System calls'), findsOneWidget);
    expect(
      find.text('Enable to show incoming calls on lock screen'),
      findsOneWidget,
    );
    expect(find.text('Enable'), findsOneWidget);
    expect(calls, contains('registerPhoneAccounts'));
    expect(calls, contains('isManagedPhoneAccountEnabled'));

    await tester.tap(find.text('Enable'));
    await tester.pump();

    expect(calls, contains('openPhoneAccountSettings'));
  });

  testWidgets('opens Android full-screen call settings when fullscreen is off',
      (tester) async {
    const channel = MethodChannel('family_todo_mobile/telecom');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'registerPhoneAccounts':
          return true;
        case 'isManagedPhoneAccountEnabled':
          return true;
        case 'canUseFullScreenIntent':
          return false;
        case 'openFullScreenIntentSettings':
          return true;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: ProfilePage(
          api: ApiClient(baseUrl: 'http://localhost', apiKey: 'test'),
          displayName: 'Nikita',
          phone: '+10000000000',
          profileKey: 'nik',
          avatarUrl: null,
          accessPolicy: const UserAccessPolicy(
            phone: '+10000000000',
            profileKey: 'nik',
            roles: ['admin'],
            capabilities: ['workspaces.grant_access'],
            workspaces: [],
            isSuperadmin: false,
          ),
          onAvatarChanged: (_) {},
          onDisplayNameChanged: (_) {},
          onOpenAdmin: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('System calls'), findsOneWidget);
    expect(
      find.text('Allow full-screen alerts for lock-screen calls'),
      findsOneWidget,
    );
    expect(find.text('Allow'), findsOneWidget);
    expect(calls, contains('isManagedPhoneAccountEnabled'));
    expect(calls, contains('canUseFullScreenIntent'));

    await tester.tap(find.text('Allow'));
    await tester.pump();

    expect(calls, contains('openFullScreenIntentSettings'));
  });
}
