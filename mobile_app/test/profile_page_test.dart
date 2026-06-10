import 'package:family_todo_mobile/features/profile/profile_page.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:family_todo_mobile/models/agent_policy.dart';
import 'package:family_todo_mobile/services/api_client.dart';
import 'package:flutter/material.dart';
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
}
