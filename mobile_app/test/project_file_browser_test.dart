import 'package:family_todo_mobile/features/projects/project_file_browser.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:family_todo_mobile/models/project_contact.dart';
import 'package:family_todo_mobile/models/project_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('project file browser uses localized labels', (tester) async {
    var linkedPath = '';
    var openedPath = '';
    var viewedPath = '';
    var refreshed = false;

    await tester.pumpWidget(
      _localizedApp(
        home: Scaffold(
          body: ProjectFileBrowser(
            project: const ProjectContact(
              id: 'weather',
              name: 'Weather',
              path: 'C:/projects/weather',
            ),
            files: const [
              ProjectFileNode(
                name: 'README.md',
                path: 'README.md',
                isDir: false,
                size: 2048,
              ),
              ProjectFileNode(
                name: 'lib',
                path: 'lib',
                isDir: true,
              ),
            ],
            currentPath: '',
            isLoading: false,
            onNavigate: (path) => openedPath = path,
            onRefresh: () => refreshed = true,
            onLinkToChat: (path) => linkedPath = path,
            onOpenFile: (path) => openedPath = path,
            onViewFile: (path) => viewedPath = path,
          ),
        ),
      ),
    );

    expect(find.text('Files - Weather'), findsOneWidget);
    expect(find.byTooltip('Project root'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.byTooltip('Link to chat'), findsWidgets);

    await tester.tap(find.byTooltip('Refresh'));
    expect(refreshed, isTrue);

    await tester.tap(find.text('lib'));
    expect(openedPath, 'lib');

    await tester.tap(find.text('README.md'));
    await tester.pumpAndSettle();

    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Link to chat'), findsOneWidget);

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(viewedPath, 'README.md');

    await tester.tap(find.text('README.md'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Link to chat'));
    await tester.pumpAndSettle();
    expect(linkedPath, 'README.md');
  });
}

Widget _localizedApp({required Widget home}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: home,
  );
}
