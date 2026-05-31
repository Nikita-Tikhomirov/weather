import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/project_file.dart';
import '../../models/workspace_item.dart';
import '../../models/workspace_session.dart';
import '../../services/codewhale_bridge_service.dart';
import 'session_chat_view.dart';
import 'session_management_view.dart';
import 'workspace_folder_browser_view.dart';
import 'workspace_detail_view.dart';
import 'workspace_list_view.dart';

class CodeWhaleWorkspacesPage extends StatefulWidget {
  const CodeWhaleWorkspacesPage({super.key});

  @override
  State<CodeWhaleWorkspacesPage> createState() =>
      _CodeWhaleWorkspacesPageState();
}

class _CodeWhaleWorkspacesPageState extends State<CodeWhaleWorkspacesPage>
    with WidgetsBindingObserver {
  late final CodeWhaleBridgeService _service;
  final TextEditingController _inputController = TextEditingController();
  final Map<String, Timer> _taskPollers = {};
  List<WorkspaceItem> _workspaces = const [];
  List<Map<String, dynamic>> _folderBrowserFolders = const [];
  List<Map<String, dynamic>> _codeWhaleCommands = const [];
  final Map<String, List<WorkspaceSession>> _sessionsByWorkspace = {};
  List<Map<String, dynamic>> _activeEvents = const [];
  List<ProjectFileNode> _workspaceFiles = const [];
  final Map<String, String> _pendingUploadPromptsByName = {};
  String _folderBrowserPath = '';
  String _folderBrowserParent = '';
  String _currentFilePath = '';
  String _filePreviewPath = '';
  String _filePreviewText = '';
  WorkspaceItem? _activeWorkspace;
  WorkspaceSession? _activeSession;
  _WorkspacePageMode _mode = _WorkspacePageMode.list;
  bool _connected = false;
  bool _filesLoading = false;
  String _statusText = 'Подключение к CodeWhale...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = CodeWhaleBridgeService(
      onMessage: _handleMessage,
      onStatusChange: _handleStatus,
    );
    _connect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.dispose();
    for (final timer in _taskPollers.values) {
      timer.cancel();
    }
    _taskPollers.clear();
    _inputController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_connect());
      _resyncActiveSession();
    }
  }

  Future<void> _connect() async {
    await _service.connect();
    _service.requestWorkspaceList();
  }

  void _handleStatus(bool connected, String status) {
    if (!mounted) {
      return;
    }
    setState(() {
      _connected = connected;
      _statusText = status;
    });
    if (connected) {
      _service.requestWorkspaceList();
      _service.requestCodeWhaleCommands();
      _resyncActiveSession();
    }
  }

  void _resyncActiveSession() {
    final workspace = _activeWorkspace;
    if (workspace == null) {
      return;
    }
    _service.requestSessionList(workspace.id);
    final session = _activeSession;
    if (session != null) {
      _service.openSession(workspace.id, session.id);
    }
  }

  void _handleMessage(CodeWhaleBridgeMessage message) {
    if (!mounted) {
      return;
    }
    setState(() {
      if (message.isError) {
        _statusText =
            message.error.isEmpty ? 'Ошибка CodeWhale' : message.error;
        _connected = false;
      }
      if (message.workspaces.isNotEmpty || message.type == 'workspace_list') {
        _workspaces = message.workspaces;
      }
      if (message.type == 'workspace_folder_list') {
        _folderBrowserPath = message.folderPath;
        _folderBrowserParent = message.folderParent;
        _folderBrowserFolders = message.folders;
      }
      if (message.type == 'codewhale_command_list') {
        _codeWhaleCommands = message.commands;
      }
      if (message.type == 'workspace_file_list') {
        _filesLoading = false;
        _currentFilePath = message.folderPath;
        _workspaceFiles = ProjectFileNode.sorted(message.files);
      }
      if (message.type == 'workspace_file_content') {
        _filePreviewPath = message.filePath;
        _filePreviewText = message.fileText;
      }
      final workspace = message.workspace;
      if (workspace != null) {
        final existing = _workspaces.where((item) => item.id != workspace.id);
        _workspaces = [...existing, workspace]
          ..sort((a, b) => a.name.compareTo(b.name));
      }
      if (message.sessions.isNotEmpty || message.type == 'session_list') {
        final workspaceId = message.workspaceId.isNotEmpty
            ? message.workspaceId
            : (message.sessions.isEmpty
                ? ''
                : message.sessions.first.workspaceId);
        if (workspaceId.isNotEmpty) {
          _sessionsByWorkspace[workspaceId] = message.sessions;
        }
      }
      final session = message.session;
      if (session != null) {
        _upsertSession(session);
        if (_activeSession?.id == session.id) {
          _activeSession = session;
        }
      }
      if (message.type == 'session_open') {
        _activeEvents = message.events;
        _mode = _WorkspacePageMode.chat;
      }
      if (message.type == 'session_stream_started') {
        _statusText = 'CodeWhale думает...';
        _appendSessionEvent(
          message,
          {'type': 'session_process_event', 'text': 'Запуск CodeWhale'},
        );
      }
      if (message.type == 'assistant_delta') {
        _appendAssistantDelta(message);
      }
      if (message.type == 'session_process_event') {
        _appendSessionEvent(message, {
          'type': 'session_process_event',
          'text': message.text,
        });
      }
      if (message.type == 'session_file_uploaded') {
        _appendSessionEvent(message, {
          'type': 'file_attachment',
          'text': 'Файл прикреплен: ${message.filePath}',
          'path': message.filePath,
          'filename': message.filename,
          'mime_type': message.mimeType,
          'size': message.fileSize,
        });
        _statusText = 'Файл прикреплен';
        var promptPrefix =
            _pendingUploadPromptsByName.remove(message.originalName) ??
                _pendingUploadPromptsByName.remove(message.filename) ??
                _pendingUploadPromptsByName.remove(message.filePath) ??
                '';
        if (promptPrefix.isEmpty && _pendingUploadPromptsByName.length == 1) {
          final originalName = _pendingUploadPromptsByName.keys.single;
          promptPrefix = _pendingUploadPromptsByName.remove(originalName) ?? '';
        }
        final workspace = _activeWorkspace;
        final session = _activeSession;
        if (promptPrefix.isNotEmpty && workspace != null && session != null) {
          _sendQuickAction(
            workspace,
            session,
            '$promptPrefix: ${message.filePath}',
          );
        }
      }
      if (message.type == 'session_stream_done') {
        _statusText = 'CodeWhale готов';
        _appendSessionEvent(
          message,
          {'type': 'session_process_event', 'text': 'Готово'},
        );
        final workspace = _activeWorkspace;
        final session = _activeSession;
        if (workspace != null && session != null) {
          _service.openSession(workspace.id, session.id);
        }
      }
      if (message.type == 'session_task') {
        _handleSessionTask(message);
      }
    });
  }

  void _handleSessionTask(CodeWhaleBridgeMessage message) {
    final taskId = message.taskId;
    if (taskId.isEmpty) {
      return;
    }
    final done = message.taskStatus == 'completed' ||
        message.taskStatus == 'failed' ||
        message.taskStatus == 'canceled';
    if (done) {
      _taskPollers.remove(taskId)?.cancel();
      final workspace = _activeWorkspace;
      final session = _activeSession;
      if (workspace != null && session != null) {
        _service.openSession(workspace.id, session.id);
      }
      return;
    }
    if (_taskPollers.containsKey(taskId)) {
      return;
    }
    final workspaceId = message.workspaceId;
    final sessionId = message.sessionId;
    if (workspaceId.isEmpty || sessionId.isEmpty) {
      return;
    }
    _taskPollers[taskId] = Timer.periodic(const Duration(seconds: 2), (_) {
      _service.pollSessionTask(workspaceId, sessionId, taskId);
    });
  }

  void _upsertSession(WorkspaceSession session) {
    final current = _sessionsByWorkspace[session.workspaceId] ?? const [];
    final next = [
      for (final item in current)
        if (item.id != session.id) item,
      session,
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _sessionsByWorkspace[session.workspaceId] = next;
  }

  void _appendAssistantDelta(CodeWhaleBridgeMessage message) {
    final workspace = _activeWorkspace;
    final session = _activeSession;
    if (workspace == null || session == null) {
      return;
    }
    if (message.workspaceId.isNotEmpty && message.workspaceId != workspace.id) {
      return;
    }
    if (message.sessionId.isNotEmpty && message.sessionId != session.id) {
      return;
    }
    if (message.text.isEmpty) {
      return;
    }

    final events = List<Map<String, dynamic>>.from(_activeEvents);
    if (events.isNotEmpty && events.last['type'] == 'assistant_delta') {
      final previous = events.removeLast();
      events.add({
        ...previous,
        'text': '${previous['text'] ?? ''}${message.text}',
        'final': message.isFinal,
      });
    } else {
      events.add({
        'type': 'assistant_delta',
        'text': message.text,
        'final': message.isFinal,
      });
    }
    _activeEvents = events;
  }

  void _appendSessionEvent(
    CodeWhaleBridgeMessage message,
    Map<String, dynamic> event,
  ) {
    final workspace = _activeWorkspace;
    final session = _activeSession;
    if (workspace == null || session == null) {
      return;
    }
    if (message.workspaceId.isNotEmpty && message.workspaceId != workspace.id) {
      return;
    }
    if (message.sessionId.isNotEmpty && message.sessionId != session.id) {
      return;
    }
    final text = (event['text'] ?? '').toString();
    if (text.trim().isEmpty) {
      return;
    }
    _activeEvents = [..._activeEvents, event];
  }

  @override
  Widget build(BuildContext context) {
    final workspace = _activeWorkspace;
    final session = _activeSession;
    switch (_mode) {
      case _WorkspacePageMode.list:
        return WorkspaceListView(
          workspaces: _workspaces,
          connected: _connected,
          statusText: _statusText,
          onRefresh: _service.requestWorkspaceList,
          onCreateWorkspace: _createWorkspace,
          onAttachWorkspace: _attachWorkspace,
          onOpenWorkspace: _openWorkspace,
        );
      case _WorkspacePageMode.detail:
        if (workspace == null) {
          return const SizedBox.shrink();
        }
        return WorkspaceDetailView(
          workspace: workspace,
          sessions: _sessionsByWorkspace[workspace.id] ?? const [],
          onBack: () => setState(() => _mode = _WorkspacePageMode.list),
          onRefresh: () => _service.requestSessionList(workspace.id),
          onCreateSession: () => _createSession(workspace),
          onOpenSession: (item) => _openSession(workspace, item),
          onManageSession: (item) => _manageSession(workspace, item),
        );
      case _WorkspacePageMode.folderBrowser:
        return WorkspaceFolderBrowserView(
          path: _folderBrowserPath,
          parent: _folderBrowserParent,
          folders: _folderBrowserFolders,
          onBack: () => setState(() => _mode = _WorkspacePageMode.list),
          onRefresh: () =>
              _service.requestWorkspaceFolderList(path: _folderBrowserPath),
          onOpenFolder: (path) =>
              _service.requestWorkspaceFolderList(path: path),
          onSelectFolder: (name, path) {
            _service.attachWorkspace(name, path);
            setState(() => _mode = _WorkspacePageMode.list);
          },
        );
      case _WorkspacePageMode.chat:
        if (workspace == null || session == null) {
          return const SizedBox.shrink();
        }
        return SessionChatView(
          workspace: workspace,
          session: session,
          events: _activeEvents,
          inputController: _inputController,
          onBack: () => setState(() => _mode = _WorkspacePageMode.detail),
          onOpenManagement: () =>
              setState(() => _mode = _WorkspacePageMode.manage),
          onSendPhoto: () => _sendPhoto(workspace, session),
          onSendDocument: () => _sendDocument(workspace, session),
          onSend: (text) {
            _service.sendSessionMessage(workspace.id, session.id, text);
            setState(() {
              _activeEvents = [
                ..._activeEvents,
                {'type': 'user_message', 'text': text},
              ];
            });
          },
        );
      case _WorkspacePageMode.manage:
        if (workspace == null || session == null) {
          return const SizedBox.shrink();
        }
        return SessionManagementView(
          workspace: workspace,
          session: session,
          files: _workspaceFiles,
          currentFilePath: _currentFilePath,
          isFilesLoading: _filesLoading,
          filePreviewPath: _filePreviewPath,
          filePreviewText: _filePreviewText,
          commands: _codeWhaleCommands,
          onBack: () => setState(() => _mode = _WorkspacePageMode.chat),
          onStop: () => _service.stopSession(workspace.id, session.id),
          onKill: () => _service.killSession(workspace.id, session.id),
          onRestart: () => _service.startSession(workspace.id, session.id),
          onRefreshFiles: () => _requestWorkspaceFiles(workspace.id),
          onOpenFilePath: (path) => _requestWorkspaceFiles(
            workspace.id,
            path: path,
          ),
          onReadFile: (path) =>
              _service.requestWorkspaceFileRead(workspace.id, path),
          onInsertFilePath: _insertPathToChat,
          onSendPhoto: () => _sendPhoto(workspace, session),
          onSendDocument: () => _sendDocument(workspace, session),
          onRunCommand: (command) => _sendQuickAction(
            workspace,
            session,
            command,
          ),
          onUpdateSettings: ({
            String? provider,
            String? model,
            String? approvalPolicy,
            String? sandboxMode,
            bool? autoMode,
          }) {
            final nextProvider = provider ?? session.provider;
            final nextModel = model ?? session.model;
            final nextApprovalPolicy = approvalPolicy ?? session.approvalPolicy;
            final nextSandboxMode = sandboxMode ?? session.sandboxMode;
            final nextAutoMode = autoMode ?? session.autoMode;
            _service.updateSessionSettings(
              workspaceId: workspace.id,
              sessionId: session.id,
              provider: nextProvider,
              model: nextModel,
              approvalPolicy: nextApprovalPolicy,
              sandboxMode: nextSandboxMode,
              autoMode: nextAutoMode,
            );
          },
        );
    }
  }

  Future<void> _createWorkspace() async {
    final name = await _promptText('Новое рабочее пространство', 'Название');
    if (name == null || name.isEmpty) {
      return;
    }
    _service.createWorkspace(name);
  }

  Future<void> _attachWorkspace() async {
    setState(() {
      _folderBrowserPath = '';
      _folderBrowserParent = '';
      _folderBrowserFolders = const [];
      _mode = _WorkspacePageMode.folderBrowser;
    });
    _service.requestWorkspaceFolderList();
  }

  Future<void> _createSession(WorkspaceItem workspace) async {
    final title = await _promptText('Новая сессия', 'Название');
    _service.createSession(workspace.id, title: title ?? '');
  }

  Future<String?> _promptText(String title, String hint) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Готово'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _openWorkspace(WorkspaceItem workspace) {
    setState(() {
      _activeWorkspace = workspace;
      _mode = _WorkspacePageMode.detail;
    });
    _service.requestSessionList(workspace.id);
  }

  void _openSession(WorkspaceItem workspace, WorkspaceSession session) {
    setState(() {
      _activeWorkspace = workspace;
      _activeSession = session;
    });
    _service.openSession(workspace.id, session.id);
  }

  void _manageSession(WorkspaceItem workspace, WorkspaceSession session) {
    setState(() {
      _activeWorkspace = workspace;
      _activeSession = session;
      _mode = _WorkspacePageMode.manage;
      _filesLoading = true;
    });
    _service.requestWorkspaceFileList(workspace.id);
    _service.requestCodeWhaleCommands();
  }

  void _requestWorkspaceFiles(String workspaceId, {String path = ''}) {
    setState(() {
      _filesLoading = true;
      _currentFilePath = path;
      _filePreviewPath = '';
      _filePreviewText = '';
    });
    _service.requestWorkspaceFileList(workspaceId, path: path);
  }

  void _insertPathToChat(String path) {
    final current = _inputController.text.trim();
    _inputController.text = current.isEmpty ? path : '$current\n$path';
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: _inputController.text.length),
    );
    setState(() => _mode = _WorkspacePageMode.chat);
  }

  void _sendQuickAction(
    WorkspaceItem workspace,
    WorkspaceSession session,
    String prompt,
  ) {
    _service.sendSessionMessage(workspace.id, session.id, prompt);
    setState(() {
      _mode = _WorkspacePageMode.chat;
      _activeEvents = [
        ..._activeEvents,
        {'type': 'user_message', 'text': prompt},
      ];
    });
  }

  Future<void> _sendPhoto(
    WorkspaceItem workspace,
    WorkspaceSession session,
  ) async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.gallery);
    if (photo == null) {
      return;
    }
    final caption = await _promptText(
      'Комментарий к фото',
      'Пусто = только сохранить',
    );
    if (caption == null) {
      return;
    }
    final bytes = await photo.readAsBytes();
    _service.uploadSessionFile(
      workspaceId: workspace.id,
      sessionId: session.id,
      bytes: bytes,
      filename: photo.name,
      mimeType: photo.mimeType ?? 'image/jpeg',
      caption: caption,
    );
    if (caption.isNotEmpty) {
      _pendingUploadPromptsByName[photo.name] = caption;
    }
    setState(() => _mode = _WorkspacePageMode.chat);
  }

  Future<void> _sendDocument(
    WorkspaceItem workspace,
    WorkspaceSession session,
  ) async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    final file = result?.files.single;
    if (file == null) {
      return;
    }
    final bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null || bytes.isEmpty) {
      return;
    }
    final caption = await _promptText(
      'Комментарий к документу',
      'Пусто = только сохранить',
    );
    if (caption == null) {
      return;
    }
    _service.uploadSessionFile(
      workspaceId: workspace.id,
      sessionId: session.id,
      bytes: bytes,
      filename: file.name,
      mimeType: _mimeTypeForName(file.name),
      caption: caption,
    );
    if (caption.isNotEmpty) {
      _pendingUploadPromptsByName[file.name] = caption;
    }
    setState(() => _mode = _WorkspacePageMode.chat);
  }

  String _mimeTypeForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (lower.endsWith('.txt') || lower.endsWith('.md')) {
      return 'text/plain';
    }
    return 'application/octet-stream';
  }
}

enum _WorkspacePageMode {
  list,
  folderBrowser,
  detail,
  chat,
  manage,
}
