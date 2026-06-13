import 'dart:typed_data';

import 'package:family_todo_mobile/features/workspaces/codewhale_workspaces_page.dart';
import 'package:family_todo_mobile/features/workspaces/session_chat_view.dart';
import 'package:family_todo_mobile/features/workspaces/session_management_view.dart';
import 'package:family_todo_mobile/features/workspaces/workspace_detail_view.dart';
import 'package:family_todo_mobile/features/workspaces/workspace_folder_browser_view.dart';
import 'package:family_todo_mobile/features/workspaces/workspace_list_view.dart';
import 'package:family_todo_mobile/l10n/app_localizations.dart';
import 'package:family_todo_mobile/models/project_file.dart';
import 'package:family_todo_mobile/models/workspace_item.dart';
import 'package:family_todo_mobile/models/workspace_session.dart';
import 'package:family_todo_mobile/services/codewhale_bridge_service.dart';
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

    expect(find.text('Workspaces'), findsOneWidget);
    expect(find.text('Погода'), findsOneWidget);

    await tester.tap(find.byTooltip('Create workspace'));
    await tester.tap(find.byTooltip('Attach folder'));
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

  testWidgets('CodeWhale page uses localized workspace prompt labels',
      (tester) async {
    final service = _FakeCodeWhaleBridgeClient();

    await tester.pumpWidget(
      _localizedTestApp(
        home: CodeWhaleWorkspacesPage(
          bridgeFactory: ({
            required onMessage,
            required onStatusChange,
          }) {
            service
              ..onMessage = onMessage
              ..onStatusChange = onStatusChange;
            return service;
          },
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Create workspace'));
    await tester.pumpAndSettle();

    expect(find.text('New workspace'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.hintText == 'Name',
      ),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Новое рабочее пространство'), findsNothing);
    expect(find.text('Название'), findsNothing);
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

    await tester.tap(find.byTooltip('Create session'));
    await tester.tap(find.text('Починить мост'));
    await tester.tap(find.byTooltip('Manage session').first);

    expect(createSession, isTrue);
    expect(opened?.id, 'session-1');
    expect(managed?.id, 'session-1');
  });

  testWidgets('workspace detail uses localized session labels', (tester) async {
    await tester.pumpWidget(
      _localizedTestApp(
        home: WorkspaceDetailView(
          workspace: workspace,
          sessions: const [session],
          onBack: () {},
          onRefresh: () {},
          onCreateSession: () {},
          onOpenSession: (_) {},
          onManageSession: (_) {},
        ),
      ),
    );

    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Refresh'), findsOneWidget);
    expect(find.byTooltip('Create session'), findsOneWidget);
    expect(find.byTooltip('Manage session'), findsOneWidget);
    expect(find.text('Running · PID 1234 · port 43101'), findsOneWidget);
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

    expect(find.text('Folder selection'), findsOneWidget);
    expect(find.text('weather'), findsOneWidget);

    await tester.tap(find.text('weather'));
    expect(openedPath, r'C:\Users\user\Desktop\weather');

    await tester.tap(find.byTooltip('Connect this folder'));
    expect(selectedName, 'weather');
    expect(selectedPath, r'C:\Users\user\Desktop\weather');
  });

  testWidgets('workspace folder browser uses localized labels', (tester) async {
    await tester.pumpWidget(
      _localizedTestApp(
        home: WorkspaceFolderBrowserView(
          path: r'C:\Users\user\Desktop',
          parent: r'C:\Users\user',
          folders: const [],
          onBack: () {},
          onRefresh: () {},
          onOpenFolder: (_) {},
          onSelectFolder: (_, __) {},
        ),
      ),
    );

    expect(find.text('Folder selection'), findsOneWidget);
    expect(find.text('Current folder'), findsOneWidget);
    expect(find.text('Parent folder'), findsOneWidget);
    expect(find.text('No folders here'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Refresh folders'), findsOneWidget);
    expect(find.byTooltip('Copy path'), findsOneWidget);
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

    expect(find.text('Manage session'), findsOneWidget);
    await tester.tap(find.byTooltip('Stop session'));
    await tester.tap(find.byTooltip('Kill stuck session'));
    await tester.tap(find.byTooltip('Restart worker'));

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

    await tester.tap(find.byTooltip('Run tools automatically'));
    await tester.pumpAndSettle();
    expect(selectedAutoMode, isTrue);

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Insert path in chat'));
    expect(insertedPath, 'README.md');

    await tester.tap(find.text('Commands'));
    await tester.pumpAndSettle();
    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('Статус'), findsOneWidget);
    expect(find.text('vision'), findsNothing);

    await tester.tap(find.text('Skills'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('vision'));
    await tester.tap(find.text('web-screenshot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run selected'));
    expect(commands, ['/skill vision', '/skill web-screenshot']);
    expect(openedPath, isEmpty);
  });

  testWidgets('session management uses localized labels', (tester) async {
    var stopped = false;
    var killed = false;
    var restarted = false;
    var insertedPath = '';
    var previewedPath = '';
    final commands = <String>[];

    await tester.pumpWidget(
      _localizedTestApp(
        home: SessionManagementView(
          workspace: workspace,
          session: const WorkspaceSession(
            id: 'session-1',
            workspaceId: 'weather',
            title: 'Fix bridge',
            status: WorkspaceSessionStatus.running,
            workerPid: 1234,
            workerPort: 43101,
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
          filePreviewPath: 'lib/main.dart',
          filePreviewText: 'void main() {}',
          commands: const [
            {
              'group': 'skills',
              'label': 'vision',
              'value': '/skill vision',
              'description': 'Inspect images',
            },
            {
              'group': 'Session',
              'label': 'Status',
              'value': '/status',
              'description': 'Check status',
            },
          ],
          onBack: () {},
          onStop: () => stopped = true,
          onKill: () => killed = true,
          onRestart: () => restarted = true,
          onRefreshFiles: () {},
          onOpenFilePath: (_) {},
          onReadFile: (path) => previewedPath = path,
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
          }) {},
        ),
      ),
    );

    expect(find.text('Manage session'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.text('Session'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Commands'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('CodeWhale modes'), findsOneWidget);
    expect(find.text('Provider'), findsOneWidget);
    expect(find.text('Tool auto mode'), findsOneWidget);
    expect(find.text('Restart'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Kill'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop session'));
    await tester.tap(find.byTooltip('Kill stuck session'));
    await tester.tap(find.byTooltip('Restart worker'));
    expect(stopped, isTrue);
    expect(killed, isTrue);
    expect(restarted, isTrue);

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(find.text('Project root'), findsOneWidget);
    expect(find.byTooltip('Up one level'), findsOneWidget);
    expect(find.byTooltip('Refresh files'), findsOneWidget);
    expect(find.byTooltip('Copy file text'), findsOneWidget);
    expect(find.byTooltip('Insert path in chat'), findsOneWidget);
    expect(find.byTooltip('Preview file'), findsOneWidget);

    await tester.tap(find.byTooltip('Insert path in chat'));
    await tester.tap(find.byTooltip('Preview file'));
    expect(insertedPath, 'README.md');
    expect(previewedPath, 'README.md');

    await tester.tap(find.text('Commands'));
    await tester.pumpAndSettle();
    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('Document'), findsOneWidget);
    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('Choose one or more skills'), findsOneWidget);

    await tester.tap(find.text('Skills'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('vision'));
    await tester.pumpAndSettle();
    expect(find.text('Selected: 1'), findsOneWidget);
    await tester.tap(find.text('Run selected'));
    expect(commands, ['/skill vision']);
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

    await tester.tap(find.byTooltip('Manage session'));
    expect(managementOpened, isTrue);

    await tester.enterText(find.byType(TextField), 'новый запрос');
    await tester.tap(find.byTooltip('Send'));
    expect(sent, 'новый запрос');

    controller.dispose();
  });

  testWidgets('session chat uses localized composer labels', (tester) async {
    var photoRequested = false;
    var documentRequested = false;
    final controller = TextEditingController();

    await tester.pumpWidget(
      _localizedTestApp(
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

    expect(find.text('Session history is empty'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Manage session'), findsOneWidget);
    expect(find.byTooltip('Attach photo'), findsOneWidget);
    expect(find.byTooltip('Attach document'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);

    await tester.tap(find.byTooltip('Attach photo'));
    await tester.tap(find.byTooltip('Attach document'));
    expect(photoRequested, isTrue);
    expect(documentRequested, isTrue);

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

    await tester.tap(find.byTooltip('Attach photo'));
    await tester.tap(find.byTooltip('Attach document'));

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

    expect(find.byTooltip('Copy text'), findsOneWidget);

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

    expect(find.text('Work progress: git status'), findsOneWidget);
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

class _FakeCodeWhaleBridgeClient implements CodeWhaleBridgeClient {
  late void Function(CodeWhaleBridgeMessage message) onMessage;
  late void Function(bool connected, String status) onStatusChange;

  @override
  Future<bool> connect() async => true;

  @override
  void requestWorkspaceList() {}

  @override
  void requestCodeWhaleCommands() {}

  @override
  void requestWorkspaceFolderList({String path = ''}) {}

  @override
  void requestWorkspaceFileList(String workspaceId, {String path = ''}) {}

  @override
  void requestWorkspaceFileRead(String workspaceId, String path) {}

  @override
  void createWorkspace(String name) {}

  @override
  void attachWorkspace(String name, String path) {}

  @override
  void requestSessionList(String workspaceId) {}

  @override
  void createSession(
    String workspaceId, {
    String title = '',
    Map<String, dynamic> taskCard = const {},
  }) {}

  @override
  void updateSessionTaskCard({
    required String workspaceId,
    required String sessionId,
    Map<String, dynamic> taskCard = const {},
  }) {}

  @override
  void openSession(String workspaceId, String sessionId) {}

  @override
  void startSession(String workspaceId, String sessionId) {}

  @override
  void stopSession(String workspaceId, String sessionId) {}

  @override
  void killSession(String workspaceId, String sessionId) {}

  @override
  void updateSessionSettings({
    required String workspaceId,
    required String sessionId,
    String provider = '',
    String model = '',
    String approvalPolicy = '',
    String sandboxMode = '',
    bool autoMode = false,
  }) {}

  @override
  void sendSessionMessage(String workspaceId, String sessionId, String text) {}

  @override
  void uploadSessionFile({
    required String workspaceId,
    required String sessionId,
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    String caption = '',
  }) {}

  @override
  void requestSessionHealth(String workspaceId, String sessionId) {}

  @override
  void pollSessionTask(String workspaceId, String sessionId, String taskId) {}

  @override
  void dispose() {}
}
