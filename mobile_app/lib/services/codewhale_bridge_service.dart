import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_config.dart';
import '../models/project_file.dart';
import '../models/workspace_item.dart';
import '../models/workspace_session.dart';

class CodeWhaleBridgeMessage {
  const CodeWhaleBridgeMessage({
    required this.type,
    this.text = '',
    this.error = '',
    this.workspace,
    this.workspaces = const [],
    this.session,
    this.sessions = const [],
    this.events = const [],
    this.commands = const [],
    this.files = const [],
    this.folders = const [],
    this.folderPath = '',
    this.folderParent = '',
    this.filePath = '',
    this.fileText = '',
    this.fileDataBase64 = '',
    this.filename = '',
    this.originalName = '',
    this.mimeType = '',
    this.fileSize = 0,
    this.workspaceId = '',
    this.sessionId = '',
    this.taskId = '',
    this.taskStatus = '',
    this.taskResultSummary = '',
    this.isFinal = false,
    this.requestId = '',
  });

  final String type;
  final String text;
  final String error;
  final WorkspaceItem? workspace;
  final List<WorkspaceItem> workspaces;
  final WorkspaceSession? session;
  final List<WorkspaceSession> sessions;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> commands;
  final List<ProjectFileNode> files;
  final List<Map<String, dynamic>> folders;
  final String folderPath;
  final String folderParent;
  final String filePath;
  final String fileText;
  final String fileDataBase64;
  final String filename;
  final String originalName;
  final String mimeType;
  final int fileSize;
  final String workspaceId;
  final String sessionId;
  final String taskId;
  final String taskStatus;
  final String taskResultSummary;
  final bool isFinal;
  final String requestId;

  factory CodeWhaleBridgeMessage.fromJson(Map<String, dynamic> json) {
    return CodeWhaleBridgeMessage(
      type: (json['type'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      error: (json['error'] ?? '').toString(),
      workspace: _workspaceOrNull(json['workspace']),
      workspaces: (json['workspaces'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(WorkspaceItem.fromJson)
              .toList() ??
          const [],
      session: _sessionOrNull(json['session']),
      sessions: (json['sessions'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(WorkspaceSession.fromJson)
              .toList() ??
          const [],
      events: (json['events'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(Map<String, dynamic>.from)
              .toList() ??
          const [],
      commands: (json['commands'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(Map<String, dynamic>.from)
              .toList() ??
          const [],
      files: (json['files'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(ProjectFileNode.fromJson)
              .toList() ??
          const [],
      folders: (json['folders'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(Map<String, dynamic>.from)
              .toList() ??
          const [],
      folderPath: (json['path'] ?? '').toString(),
      folderParent: (json['parent'] ?? '').toString(),
      filePath: (json['path'] ?? '').toString(),
      fileText: (json['text'] ?? '').toString(),
      fileDataBase64:
          (json['data_base64'] ?? json['dataBase64'] ?? '').toString(),
      filename: (json['name'] ?? json['filename'] ?? '').toString(),
      originalName: (json['original_name'] ?? '').toString(),
      mimeType: (json['mime_type'] ?? '').toString(),
      fileSize: int.tryParse((json['size'] ?? 0).toString()) ?? 0,
      workspaceId: (json['workspace_id'] ?? '').toString(),
      sessionId: (json['session_id'] ?? '').toString(),
      taskId: (json['task_id'] ?? '').toString(),
      taskStatus: (json['status'] ?? '').toString(),
      taskResultSummary: _taskResultSummary(json['task']),
      isFinal: json['final'] == true,
      requestId: (json['request_id'] ?? '').toString(),
    );
  }

  bool get isStatus => type == 'status';
  bool get isError => type == 'error';

  static WorkspaceItem? _workspaceOrNull(Object? value) {
    if (value is Map<String, dynamic>) {
      return WorkspaceItem.fromJson(value);
    }
    return null;
  }

  static WorkspaceSession? _sessionOrNull(Object? value) {
    if (value is Map<String, dynamic>) {
      return WorkspaceSession.fromJson(value);
    }
    return null;
  }

  static String _taskResultSummary(Object? value) {
    if (value is Map) {
      return (value['result_summary'] ?? '').toString();
    }
    return '';
  }
}

abstract class CodeWhaleBridgeClient {
  Future<bool> connect();
  void requestCodeWhaleCommands();
  void requestWorkspaceList();
  void requestWorkspaceFolderList({String path = ''});
  void requestWorkspaceFileList(String workspaceId, {String path = ''});
  void requestWorkspaceFileRead(String workspaceId, String path);
  void createWorkspace(String name);
  void attachWorkspace(String name, String path);
  void requestSessionList(String workspaceId);

  void createSession(
    String workspaceId, {
    String title = '',
    Map<String, dynamic> taskCard = const {},
  });

  void updateSessionTaskCard({
    required String workspaceId,
    required String sessionId,
    Map<String, dynamic> taskCard = const {},
  });

  void openSession(String workspaceId, String sessionId);
  void startSession(String workspaceId, String sessionId);
  void stopSession(String workspaceId, String sessionId);
  void killSession(String workspaceId, String sessionId);

  void updateSessionSettings({
    required String workspaceId,
    required String sessionId,
    String provider = '',
    String model = '',
    String approvalPolicy = '',
    String sandboxMode = '',
    bool autoMode = false,
  });

  void sendSessionMessage(String workspaceId, String sessionId, String text);

  void uploadSessionFile({
    required String workspaceId,
    required String sessionId,
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    String caption = '',
  });

  void requestSessionHealth(String workspaceId, String sessionId);
  void pollSessionTask(String workspaceId, String sessionId, String taskId);
  void dispose();
}

class CodeWhaleBridgeService implements CodeWhaleBridgeClient {
  CodeWhaleBridgeService({
    required this.onMessage,
    required this.onStatusChange,
  });

  final void Function(CodeWhaleBridgeMessage message) onMessage;
  final void Function(bool connected, String status) onStatusChange;

  Socket? _socket;
  Timer? _reconnectTimer;
  bool _running = false;
  bool _disposed = false;
  bool _connecting = false;
  int _reconnectAttempts = 0;
  String _policyTicket = '';
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  final List<String> _pendingMessages = <String>[];

  bool get isConnected => _socket != null && _running;

  static Future<String> getServerAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConfig.prefBridgeHost) ??
        AppConfig.bridgeDefaultHost;
  }

  @override
  Future<bool> connect() async {
    if (_disposed) {
      return false;
    }
    if (_running) {
      return true;
    }
    if (_connecting) {
      return false;
    }

    _connecting = true;
    final address = await getServerAddress();
    final parts = address.split(':');
    final host = parts[0].trim();
    final port =
        parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 9877 : 9877;

    try {
      _socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      _running = true;
      _connecting = false;

      _socket!.listen(
        _onData,
        onError: (error) {
          if (_disposed) {
            _cleanup();
            return;
          }
          onStatusChange(false, 'Ошибка соединения CodeWhale: $error');
          _cleanup();
          _scheduleReconnect();
        },
        onDone: () {
          if (_disposed) {
            _cleanup();
            return;
          }
          onStatusChange(false, 'Соединение CodeWhale закрыто');
          _cleanup();
          _scheduleReconnect();
        },
      );

      _reconnectAttempts = 0;
      _sendRaw('${jsonEncode({
            'type': 'codewhale_connect',
            'project_id': 'codewhale',
          })}\n');
      _flushPending();
      onStatusChange(true, 'Подключено к CodeWhale');
      return true;
    } catch (e) {
      _connecting = false;
      if (!_disposed) {
        onStatusChange(false, 'Не удалось подключиться к CodeWhale: $e');
        _scheduleReconnect();
      }
      _cleanup();
      return false;
    }
  }

  @override
  void requestCodeWhaleCommands() {
    _sendCommand({'type': 'codewhale_command_list'});
  }

  void updatePolicyTicket(String policyTicket) {
    _policyTicket = policyTicket.trim();
  }

  @override
  void requestWorkspaceList() {
    _sendCommand({'type': 'workspace_list'});
  }

  @override
  void requestWorkspaceFolderList({String path = ''}) {
    _sendCommand({
      'type': 'workspace_folder_list',
      if (path.trim().isNotEmpty) 'path': path.trim(),
    });
  }

  @override
  void requestWorkspaceFileList(String workspaceId, {String path = ''}) {
    _sendCommand({
      'type': 'workspace_file_list',
      'workspace_id': workspaceId,
      if (path.trim().isNotEmpty) 'path': path.trim(),
    });
  }

  @override
  void requestWorkspaceFileRead(String workspaceId, String path) {
    _sendCommand({
      'type': 'workspace_file_read',
      'workspace_id': workspaceId,
      'path': path.trim(),
    });
  }

  @override
  void createWorkspace(String name) {
    _sendCommand({'type': 'workspace_create', 'name': name.trim()});
  }

  @override
  void attachWorkspace(String name, String path) {
    _sendCommand({
      'type': 'workspace_attach',
      'name': name.trim(),
      'path': path.trim(),
    });
  }

  @override
  void requestSessionList(String workspaceId) {
    _sendCommand({'type': 'session_list', 'workspace_id': workspaceId});
  }

  @override
  void createSession(
    String workspaceId, {
    String title = '',
    Map<String, dynamic> taskCard = const {},
  }) {
    _sendCommand({
      'type': 'session_create',
      'workspace_id': workspaceId,
      'title': title.trim(),
      if (taskCard.isNotEmpty) 'task_card': taskCard,
    });
  }

  @override
  void updateSessionTaskCard({
    required String workspaceId,
    required String sessionId,
    Map<String, dynamic> taskCard = const {},
  }) {
    if (taskCard.isEmpty) {
      return;
    }
    _sendCommand({
      'type': 'session_update_task_card',
      'workspace_id': workspaceId,
      'session_id': sessionId,
      'task_card': taskCard,
    });
  }

  @override
  void openSession(String workspaceId, String sessionId) {
    _sendCommand({
      'type': 'session_open',
      'workspace_id': workspaceId,
      'session_id': sessionId,
    });
  }

  @override
  void startSession(String workspaceId, String sessionId) {
    _sendCommand({
      'type': 'session_start',
      'workspace_id': workspaceId,
      'session_id': sessionId,
    });
  }

  @override
  void stopSession(String workspaceId, String sessionId) {
    _sendCommand({
      'type': 'session_stop',
      'workspace_id': workspaceId,
      'session_id': sessionId,
    });
  }

  @override
  void killSession(String workspaceId, String sessionId) {
    _sendCommand({
      'type': 'session_kill',
      'workspace_id': workspaceId,
      'session_id': sessionId,
    });
  }

  @override
  void updateSessionSettings({
    required String workspaceId,
    required String sessionId,
    String provider = '',
    String model = '',
    String approvalPolicy = '',
    String sandboxMode = '',
    bool autoMode = false,
  }) {
    _sendCommand({
      'type': 'session_update_settings',
      'workspace_id': workspaceId,
      'session_id': sessionId,
      'provider': provider.trim(),
      'model': model.trim(),
      'approval_policy': approvalPolicy.trim(),
      'sandbox_mode': sandboxMode.trim(),
      'auto_mode': autoMode,
    });
  }

  @override
  void sendSessionMessage(String workspaceId, String sessionId, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    _sendCommand({
      'type': 'session_send',
      'workspace_id': workspaceId,
      'session_id': sessionId,
      'text': trimmed,
    });
  }

  @override
  void uploadSessionFile({
    required String workspaceId,
    required String sessionId,
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    String caption = '',
  }) {
    if (bytes.isEmpty || filename.trim().isEmpty) {
      return;
    }
    _sendCommand({
      'type': 'session_upload_file',
      'workspace_id': workspaceId,
      'session_id': sessionId,
      'filename': filename.trim(),
      'mime_type': mimeType.trim().isEmpty
          ? 'application/octet-stream'
          : mimeType.trim(),
      'data_base64': base64Encode(bytes),
      if (caption.trim().isNotEmpty) 'caption': caption.trim(),
    });
  }

  @override
  void requestSessionHealth(String workspaceId, String sessionId) {
    _sendCommand({
      'type': 'session_health',
      'workspace_id': workspaceId,
      'session_id': sessionId,
    });
  }

  @override
  void pollSessionTask(String workspaceId, String sessionId, String taskId) {
    _sendCommand({
      'type': 'session_task_poll',
      'workspace_id': workspaceId,
      'session_id': sessionId,
      'task_id': taskId,
    });
  }

  void _sendCommand(Map<String, dynamic> payload) {
    final ticket = _policyTicket.trim();
    final command = ticket.isEmpty || payload.containsKey('policy_ticket')
        ? payload
        : {
            ...payload,
            'policy_ticket': ticket,
          };
    _sendRaw('${jsonEncode(command)}\n');
  }

  void _onData(Uint8List data) {
    _buffer.add(data);
    while (true) {
      final content = _buffer.toBytes();
      final newlineIndex = content.indexOf(10);
      if (newlineIndex < 0) {
        break;
      }

      final lineBytes = content.sublist(0, newlineIndex);
      _buffer.clear();
      if (newlineIndex + 1 < content.length) {
        _buffer.add(content.sublist(newlineIndex + 1));
      }

      final line = utf8.decode(lineBytes, allowMalformed: true).trim();
      if (line.isEmpty) {
        continue;
      }

      try {
        final decoded = jsonDecode(line) as Map<String, dynamic>;
        onMessage(CodeWhaleBridgeMessage.fromJson(decoded));
      } catch (_) {
        onMessage(CodeWhaleBridgeMessage(type: 'output', text: line));
      }
    }
  }

  void _sendRaw(String data) {
    if (!isConnected) {
      if (_pendingMessages.length >= 30) {
        _pendingMessages.removeAt(0);
      }
      _pendingMessages.add(data);
      return;
    }
    try {
      _socket?.write(data);
    } catch (_) {
      if (!_disposed) {
        onStatusChange(
          false,
          'Не удалось отправить команду CodeWhale',
        );
      }
      _cleanup();
    }
  }

  void _flushPending() {
    if (!isConnected || _pendingMessages.isEmpty) {
      return;
    }
    final queued = List<String>.from(_pendingMessages);
    _pendingMessages.clear();
    for (final payload in queued) {
      _sendRaw(payload);
    }
  }

  void _cleanup() {
    _running = false;
    _connecting = false;
    _buffer.clear();
    try {
      _socket?.destroy();
    } catch (_) {
      // socket may already be closed
    }
    _socket = null;
  }

  void _scheduleReconnect() {
    if (_disposed || _connecting || _running || _reconnectTimer != null) {
      return;
    }
    final delaySeconds = _reconnectAttempts < 6 ? 2 + _reconnectAttempts : 10;
    _reconnectAttempts += 1;
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _reconnectTimer = null;
      if (!_disposed && !_running) {
        unawaited(connect());
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _pendingMessages.clear();
    _cleanup();
  }
}
