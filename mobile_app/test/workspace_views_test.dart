import 'package:family_todo_mobile/features/workspaces/session_chat_view.dart';
import 'package:family_todo_mobile/features/workspaces/session_management_view.dart';
import 'package:family_todo_mobile/features/workspaces/workspace_detail_view.dart';
import 'package:family_todo_mobile/features/workspaces/workspace_folder_browser_view.dart';
import 'package:family_todo_mobile/features/workspaces/workspace_list_view.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:family_todo_mobile/models/project_file.dart';
import 'package:family_todo_mobile/models/workspace_item.dart';
import 'package:family_todo_mobile/models/workspace_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const workspace = WorkspaceItem(
    id: 'weather',
    name: 'Погода',
    path: r'C:\Users\user\Desktop\weather',
    status: WorkspaceStatus.available,
  );
  const session = WorkspaceSession(
    id: 'session-1',
    workspaceId: 'weather',
    title: 'Починить мост',
    status: WorkspaceSessionStatus.running,
    workerPid: 1234,
    workerPort: 43101,
  );

  testWidgets('workspace list shows workspaces and create actions',
      (tester) async {
    var createTapped = false;
    var attachTapped = false;
    WorkspaceItem? opened;

    await tester.pumpWidget(
      _testApp(
        home: WorkspaceListView(
          workspaces: const [workspace],
          connected: true,
          statusText: 'Подключено',
          onRefresh: () {},
          onCreateWorkspace: () => createTapped = true,
          onAttachWorkspace: () => attachTapped = true,
          onOpenWorkspace: (item) => opened = item,
        ),
      ),
    );

    expect(find.text('Рабочие пространства'), findsOneWidget);
    expect(find.text('Погода'), findsOneWidget);

    await tester.tap(find.byTooltip('Создать рабочее пространство'));
    await tester.tap(find.byTooltip('Подключить папку'));
    await tester.tap(find.text('Погода'));

    expect(createTapped, isTrue);
    expect(attachTapped, isTrue);
    expect(opened?.id, 'weather');
  });

  testWidgets('workspace list uses localized shell labels', (tester) async {
    await tester.pumpWidget(
      _localizedTestApp(
        home: WorkspaceListView(
          workspaces: const [],
          connected: true,
          statusText: 'Connected',
          onRefresh: () {},
          onCreateWorkspace: () {},
          onAttachWorkspace: () {},
          onOpenWorkspace: (_) {},
        ),
      ),
    );

    expect(find.text('Workspaces'), findsOneWidget);
    expect(find.text('No workspaces yet'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
    expect(find.byTooltip('Attach folder'), findsOneWidget);
    expect(find.byTooltip('Create workspace'), findsOneWidget);
  });

  testWidgets('workspace detail shows sessions and opens management',
      (tester) async {
    var createSession = false;
    WorkspaceSession? opened;
    WorkspaceSession? managed;

    await tester.pumpWidget(
      _testApp(
        home: WorkspaceDetailView(
          workspace: workspace,
          sessions: const [session],
          onBack: () {},
          onRefresh: () {},
          onCreateSession: () => createSession = true,
          onOpenSession: (item) => opened = item,
          onManageSession: (item) => managed = item,
        ),
      ),
    );

    expect(find.text('Погода'), findsOneWidget);
    expect(find.text('Починить мост'), findsOneWidget);

    await tester.tap(find.byTooltip('Создать сессию'));
    await tester.tap(find.text('Починить мост'));
    await tester.tap(find.byTooltip('Управление сессией').first);

    expect(createSession, isTrue);
    expect(opened?.id, 'session-1');
    expect(managed?.id, 'session-1');
  });

  testWidgets('workspace folder browser opens and selects folders',
      (tester) async {
    var openedPath = '';
    var selectedName = '';
    var selectedPath = '';

    await tester.pumpWidget(
      _testApp(
        home: WorkspaceFolderBrowserView(
          path: r'C:\Users\user\Desktop',
          parent: '',
          folders: const [
            {
              'name': 'weather',
              'path': r'C:\Users\user\Desktop\weather',
            },
          ],
          onBack: () {},
          onRefresh: () {},
          onOpenFolder: (path) => openedPath = path,
          onSelectFolder: (name, path) {
            selectedName = name;
            selectedPath = path;
          },
        ),
      ),
    );

    expect(find.text('Выбор папки'), findsOneWidget);
    expect(find.text('weather'), findsOneWidget);

    await tester.tap(find.text('weather'));
    expect(openedPath, r'C:\Users\user\Desktop\weather');

    await tester.tap(find.byTooltip('Подключить эту папку'));
    expect(selectedName, 'weather');
    expect(selectedPath, r'C:\Users\user\Desktop\weather');
  });

  testWidgets('session management exposes kill and stop controls',
      (tester) async {
    var stopped = false;
    var killed = false;
    var restarted = false;
    var openedPath = '';
    var insertedPath = '';
    final commands = <String>[];
    var selectedProvider = '';
    var selectedModel = '';
    var selectedApprovalPolicy = '';
    var selectedSandboxMode = '';
    var selectedAutoMode = false;

    await tester.pumpWidget(
      _testApp(
        home: SessionManagementView(
          workspace: workspace,
          session: const WorkspaceSession(
            id: 'session-1',
            workspaceId: 'weather',
            title: 'Починить мост',
            status: WorkspaceSessionStatus.running,
            provider: 'deepseek',
            model: 'deepseek-v4-pro',
            approvalPolicy: 'on-request',
            sandboxMode: 'workspace-write',
            autoMode: false,
          ),
          files: const [
            ProjectFileNode(
              name: 'README.md',
              path: 'README.md',
              isDir: false,
              size: 12,
            ),
          ],
          currentFilePath: '',
          isFilesLoading: false,
          filePreviewPath: '',
          filePreviewText: '',
          commands: const [
            {
              'group': 'Навыки',
              'label': 'vision',
              'value': '/skill vision',
              'description': 'Проверка изображений',
            },
            {
              'group': 'Навыки',
              'label': 'web-screenshot',
              'value': '/skill web-screenshot',
              'description': 'Скриншоты сайтов',
            },
            {
              'group': 'Сессия',
              'label': 'Статус',
              'value': '/status',
              'description': 'Проверить статус',
            },
          ],
          onBack: () {},
          onStop: () => stopped = true,
          onKill: () => killed = true,
          onRestart: () => restarted = true,
          onRefreshFiles: () {},
          onOpenFilePath: (path) => openedPath = path,
          onReadFile: (path) => openedPath = path,
          onInsertFilePath: (path) => insertedPath = path,
          onSendPhoto: () {},
          onSendDocument: () {},
          onRunCommand: commands.add,
          onUpdateSettings: ({
            String? provider,
            String? model,
            String? approvalPolicy,
            String? sandboxMode,
            bool? autoMode,
          }) {
            if (provider != null) {
              selectedProvider = provider;
            }
            if (model != null) {
              selectedModel = model;
            }
            if (approvalPolicy != null) {
              selectedApprovalPolicy = approvalPolicy;
            }
            if (sandboxMode != null) {
              selectedSandboxMode = sandboxMode;
            }
            if (autoMode != null) {
              selectedAutoMode = autoMode;
            }
          },
        ),
      ),
    );

    expect(find.text('Управление сессией'), findsOneWidget);
    await tester.tap(find.byTooltip('Остановить сессию'));
    await tester.tap(find.byTooltip('Убить зависшую сессию'));
    await tester.tap(find.byTooltip('Перезапустить worker'));

    expect(stopped, isTrue);
    expect(killed, isTrue);
    expect(restarted, isTrue);

    await tester.drag(find.byType(ListView).first, const Offset(0, -420));
    await tester.pumpAndSettle();

    await tester.tap(find.text('deepseek'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('openrouter').last);
    await tester.pumpAndSettle();
    expect(selectedProvider, 'openrouter');

    await tester.tap(find.text('deepseek-v4-pro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('deepseek-v4-flash').last);
    await tester.pumpAndSettle();
    expect(selectedModel, 'deepseek-v4-flash');

    await tester.tap(find.text('on-request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('never').last);
    await tester.pumpAndSettle();
    expect(selectedApprovalPolicy, 'never');

    await tester.tap(find.text('workspace-write'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('danger-full-access').last);
    await tester.pumpAndSettle();
    expect(selectedSandboxMode, 'danger-full-access');

    await tester.tap(find.byTooltip('Автоматически выполнять инструменты'));
    await tester.pumpAndSettle();
    expect(selectedAutoMode, isTrue);

    await tester.tap(find.text('Файлы'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Путь в чат'));
    expect(insertedPath, 'README.md');

    await tester.tap(find.text('Команды'));
    await tester.pumpAndSettle();
    expect(find.text('Скиллы'), findsOneWidget);
    expect(find.text('Статус'), findsOneWidget);
    expect(find.text('vision'), findsNothing);

    await tester.tap(find.text('Скиллы'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('vision'));
    await tester.tap(find.text('web-screenshot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Запустить выбранные'));
    expect(commands, ['/skill vision', '/skill web-screenshot']);
    expect(openedPath, isEmpty);
  });

  testWidgets('session chat keeps controls out of composer', (tester) async {
    var managementOpened = false;
    var sent = '';
    final controller = TextEditingController();

    await tester.pumpWidget(
      _testApp(
        home: SessionChatView(
          workspace: workspace,
          session: session,
          events: const [
            {'type': 'user_message', 'text': 'Привет'},
            {'type': 'assistant_delta', 'text': 'Готов'},
          ],
          inputController: controller,
          onBack: () {},
          onOpenManagement: () => managementOpened = true,
          onSend: (text) => sent = text,
        ),
      ),
    );

    expect(find.text('Привет'), findsOneWidget);
    expect(find.text('Готов'), findsOneWidget);

    await tester.tap(find.byTooltip('Управление сессией'));
    expect(managementOpened, isTrue);

    await tester.enterText(find.byType(TextField), 'новый запрос');
    await tester.tap(find.byTooltip('Отправить'));
    expect(sent, 'новый запрос');

    controller.dispose();
  });

  testWidgets('session chat scrolls to latest event on open and update',
      (tester) async {
    final controller = TextEditingController();

    List<Map<String, dynamic>> events(int count) {
      return [
        for (var index = 0; index < count; index++)
          {
            'type': 'user_message',
            'text': index < 50
                ? 'message-$index'
                : 'message-$index ${'long agent event text ' * 22}',
          },
      ];
    }

    await tester.pumpWidget(
      _testApp(
        home: SessionChatView(
          workspace: workspace,
          session: session,
          events: events(80),
          inputController: controller,
          onBack: () {},
          onOpenManagement: () {},
          onSend: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    var scrollable = _mainScrollable(tester);
    expect(
      scrollable.position.pixels,
      scrollable.position.maxScrollExtent,
    );
    expect(find.textContaining('message-79'), findsOneWidget);
    expect(find.text('message-0'), findsNothing);

    await tester.pumpWidget(
      _testApp(
        home: SessionChatView(
          workspace: workspace,
          session: session,
          events: events(81),
          inputController: controller,
          onBack: () {},
          onOpenManagement: () {},
          onSend: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    scrollable = _mainScrollable(tester);
    expect(
      scrollable.position.pixels,
      scrollable.position.maxScrollExtent,
    );
    expect(find.textContaining('message-80'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('session chat exposes photo and document attachment actions',
      (tester) async {
    var photoRequested = false;
    var documentRequested = false;
    final controller = TextEditingController();

    await tester.pumpWidget(
      _testApp(
        home: SessionChatView(
          workspace: workspace,
          session: session,
          events: const [],
          inputController: controller,
          onBack: () {},
          onOpenManagement: () {},
          onSend: (_) {},
          onSendPhoto: () => photoRequested = true,
          onSendDocument: () => documentRequested = true,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Прикрепить фото'));
    await tester.tap(find.byTooltip('Прикрепить документ'));

    expect(photoRequested, isTrue);
    expect(documentRequested, isTrue);

    controller.dispose();
  });

  testWidgets('session chat merges consecutive assistant deltas',
      (tester) async {
    final controller = TextEditingController();

    await tester.pumpWidget(
      _testApp(
        home: SessionChatView(
          workspace: workspace,
          session: session,
          events: const [
            {'type': 'user_message', 'text': 'Привет'},
            {'type': 'assistant_delta', 'text': 'Го', 'final': false},
            {'type': 'assistant_delta', 'text': 'тов', 'final': false},
          ],
          inputController: controller,
          onBack: () {},
          onOpenManagement: () {},
          onSend: (_) {},
        ),
      ),
    );

    expect(find.text('Привет'), findsOneWidget);
    expect(find.text('Готов'), findsOneWidget);
    expect(find.text('Го'), findsNothing);
    expect(find.text('тов'), findsNothing);

    controller.dispose();
  });

  testWidgets('session chat exposes copy action for message bubbles',
      (tester) async {
    final controller = TextEditingController();

    await tester.pumpWidget(
      _testApp(
        home: SessionChatView(
          workspace: workspace,
          session: session,
          events: const [
            {'type': 'assistant_delta', 'text': 'Скопируй меня'},
          ],
          inputController: controller,
          onBack: () {},
          onOpenManagement: () {},
          onSend: (_) {},
        ),
      ),
    );

    expect(find.byTooltip('Копировать текст'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('session chat shows process events separately', (tester) async {
    final controller = TextEditingController();

    await tester.pumpWidget(
      _testApp(
        home: SessionChatView(
          workspace: workspace,
          session: session,
          events: const [
            {'type': 'session_process_event', 'text': 'git status'},
            {'type': 'assistant_delta', 'text': 'Готово'},
          ],
          inputController: controller,
          onBack: () {},
          onOpenManagement: () {},
          onSend: (_) {},
        ),
      ),
    );

    expect(find.text('Ход работы: git status'), findsOneWidget);
    expect(find.text('Готово'), findsOneWidget);

    controller.dispose();
  });
}

Widget _testApp({required Widget home}) {
  return MaterialApp(
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: home,
  );
}

Widget _localizedTestApp({required Widget home}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(splashFactory: NoSplash.splashFactory),
    home: home,
  );
}

ScrollableState _mainScrollable(WidgetTester tester) {
  return tester.stateList<ScrollableState>(find.byType(Scrollable)).firstWhere(
        (state) => state.widget.controller != null,
      );
}
