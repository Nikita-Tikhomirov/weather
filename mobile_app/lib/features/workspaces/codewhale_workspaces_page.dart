import 'package:flutter/material.dart';

import '../../models/workspace_item.dart';
import '../../models/workspace_session.dart';
import '../../services/codewhale_bridge_service.dart';
import 'session_chat_view.dart';
import 'session_management_view.dart';
import 'workspace_detail_view.dart';
import 'workspace_list_view.dart';

class CodeWhaleWorkspacesPage extends StatefulWidget {
  const CodeWhaleWorkspacesPage({super.key});

  @override
  State<CodeWhaleWorkspacesPage> createState() =>
      _CodeWhaleWorkspacesPageState();
}

class _CodeWhaleWorkspacesPageState extends State<CodeWhaleWorkspacesPage> {
  late final CodeWhaleBridgeService _service;
  final TextEditingController _inputController = TextEditingController();
  List<WorkspaceItem> _workspaces = const [];
  final Map<String, List<WorkspaceSession>> _sessionsByWorkspace = {};
  List<Map<String, dynamic>> _activeEvents = const [];
  WorkspaceItem? _activeWorkspace;
  WorkspaceSession? _activeSession;
  _WorkspacePageMode _mode = _WorkspacePageMode.list;
  bool _connected = false;
  String _statusText = 'Подключение к CodeWhale...';

  @override
  void initState() {
    super.initState();
    _service = CodeWhaleBridgeService(
      onMessage: _handleMessage,
      onStatusChange: _handleStatus,
    );
    _connect();
  }

  @override
  void dispose() {
    _service.dispose();
    _inputController.dispose();
    super.dispose();
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
          onBack: () => setState(() => _mode = _WorkspacePageMode.chat),
          onStop: () => _service.stopSession(workspace.id, session.id),
          onKill: () => _service.killSession(workspace.id, session.id),
          onRestart: () => _service.startSession(workspace.id, session.id),
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
    final path =
        await _promptText('Подключить папку', r'C:\Users\user\Desktop\...');
    if (path == null || path.isEmpty) {
      return;
    }
    final name =
        path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).last;
    _service.attachWorkspace(name, path);
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
    });
  }
}

enum _WorkspacePageMode {
  list,
  detail,
  chat,
  manage,
}
