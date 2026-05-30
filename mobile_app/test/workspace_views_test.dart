import 'package:family_todo_mobile/features/workspaces/session_chat_view.dart';
import 'package:family_todo_mobile/features/workspaces/session_management_view.dart';
import 'package:family_todo_mobile/features/workspaces/workspace_detail_view.dart';
import 'package:family_todo_mobile/features/workspaces/workspace_folder_browser_view.dart';
import 'package:family_todo_mobile/features/workspaces/workspace_list_view.dart';
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

    await tester.pumpWidget(_testApp(
      home: WorkspaceListView(
        workspaces: const [workspace],
        connected: true,
        statusText: 'Подключено',
        onRefresh: () {},
        onCreateWorkspace: () => createTapped = true,
        onAttachWorkspace: () => attachTapped = true,
        onOpenWorkspace: (item) => opened = item,
      ),
    ));

    expect(find.text('Рабочие пространства'), findsOneWidget);
    expect(find.text('Погода'), findsOneWidget);

    await tester.tap(find.byTooltip('Создать рабочее пространство'));
    await tester.tap(find.byTooltip('Подключить папку'));
    await tester.tap(find.text('Погода'));

    expect(createTapped, isTrue);
    expect(attachTapped, isTrue);
    expect(opened?.id, 'weather');
  });

  testWidgets('workspace detail shows sessions and opens management',
      (tester) async {
    var createSession = false;
    WorkspaceSession? opened;
    WorkspaceSession? managed;

    await tester.pumpWidget(_testApp(
      home: WorkspaceDetailView(
        workspace: workspace,
        sessions: const [session],
        onBack: () {},
        onRefresh: () {},
        onCreateSession: () => createSession = true,
        onOpenSession: (item) => opened = item,
        onManageSession: (item) => managed = item,
      ),
    ));

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

    await tester.pumpWidget(_testApp(
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
    ));

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
    var command = '';

    await tester.pumpWidget(_testApp(
      home: SessionManagementView(
        workspace: workspace,
        session: session,
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
        onRunCommand: (value) => command = value,
      ),
    ));

    expect(find.text('Управление сессией'), findsOneWidget);
    await tester.tap(find.byTooltip('Остановить сессию'));
    await tester.tap(find.byTooltip('Убить зависшую сессию'));
    await tester.tap(find.byTooltip('Перезапустить worker'));

    expect(stopped, isTrue);
    expect(killed, isTrue);
    expect(restarted, isTrue);

    await tester.tap(find.text('Файлы'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Путь в чат'));
    expect(insertedPath, 'README.md');

    await tester.tap(find.text('Команды'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('vision'));
    expect(command, '/skill vision');
    expect(openedPath, isEmpty);
  });

  testWidgets('session chat keeps controls out of composer', (tester) async {
    var managementOpened = false;
    var sent = '';
    final controller = TextEditingController();

    await tester.pumpWidget(_testApp(
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
    ));

    expect(find.text('Привет'), findsOneWidget);
    expect(find.text('Готов'), findsOneWidget);

    await tester.tap(find.byTooltip('Управление сессией'));
    expect(managementOpened, isTrue);

    await tester.enterText(find.byType(TextField), 'новый запрос');
    await tester.tap(find.byTooltip('Отправить'));
    expect(sent, 'новый запрос');
  });

  testWidgets('session chat merges consecutive assistant deltas',
      (tester) async {
    final controller = TextEditingController();

    await tester.pumpWidget(_testApp(
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
    ));

    expect(find.text('Привет'), findsOneWidget);
    expect(find.text('Готов'), findsOneWidget);
    expect(find.text('Го'), findsNothing);
    expect(find.text('тов'), findsNothing);

    controller.dispose();
  });

  testWidgets('session chat exposes copy action for message bubbles',
      (tester) async {
    final controller = TextEditingController();

    await tester.pumpWidget(_testApp(
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
    ));

    expect(find.byTooltip('Копировать текст'), findsOneWidget);

    controller.dispose();
  });

  testWidgets('session chat shows process events separately', (tester) async {
    final controller = TextEditingController();

    await tester.pumpWidget(_testApp(
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
    ));

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
