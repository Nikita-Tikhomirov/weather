import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../app/app_config.dart';
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
    this.workspaceId = '',
    this.sessionId = '',
    this.taskId = '',
    this.taskStatus = '',
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
  final String workspaceId;
  final String sessionId;
  final String taskId;
  final String taskStatus;
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
      workspaceId: (json['workspace_id'] ?? '').toString(),
      sessionId: (json['session_id'] ?? '').toString(),
      taskId: (json['task_id'] ?? '').toString(),
      taskStatus: (json['status'] ?? '').toString(),
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
}

class CodeWhaleBridgeService {
  CodeWhaleBridgeService({
    required this.onMessage,
    required this.onStatusChange,
  });

  final void Function(CodeWhaleBridgeMessage message) onMessage;
  final void Function(bool connected, String status) onStatusChange;

  Socket? _socket;
  bool _running = false;
  bool _disposed = false;
  bool _connecting = false;
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  final List<String> _pendingMessages = <String>[];

  bool get isConnected => _socket != null && _running;

  static Future<String> getServerAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConfig.prefBridgeHost) ??
        AppConfig.bridgeDefaultHost;
  }

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
      onStatusChange(true, 'Подключено к CodeWhale');

      _socket!.listen(
        _onData,
        onError: (error) {
          if (_disposed) {
            _cleanup();
            return;
          }
          onStatusChange(false, 'Ошибка соединения CodeWhale: $error');
          _cleanup();
        },
        onDone: () {
          if (_disposed) {
            _cleanup();
            return;
          }
          onStatusChange(false, 'Соединение CodeWhale закрыто');
          _cleanup();
        },
      );

      _sendRaw('${jsonEncode({
            'type': 'codewhale_connect',
            'project_id': 'codewhale',
          })}\n');
      _flushPending();
      return true;
    } catch (e) {
      _connecting = false;
      if (!_disposed) {
        onStatusChange(false, 'Не удалось подключиться к CodeWhale: $e');
      }
      _cleanup();
      return false;
    }
  }

  void requestWorkspaceList() {
    _sendCommand({'type': 'workspace_list'});
  }

  void createWorkspace(String name) {
    _sendCommand({'type': 'workspace_create', 'name': name.trim()});
  }

  void attachWorkspace(String name, String path) {
    _sendCommand({
      'type': 'workspace_attach',
      'name': name.trim(),
      'path': path.trim(),
    });
  }

  void requestSessionList(String workspaceId) {
    _sendCommand({'type': 'session_list', 'workspace_id': workspaceId});
  }

  void createSession(String workspaceId, {String title = ''}) {
    _sendCommand({
      'type': 'session_create',
      'workspace_id': workspaceId,
      'title': title.trim(),
    });
  }

  void openSession(String workspaceId, String sessionId) {
    _sendCommand({
      'type': 'session_open',
      'workspace_id': workspaceId,
      'session_id': sessionId,
    });
  }

  void startSession(String workspaceId, String sessionId) {
    _sendCommand({
      'type': 'session_start',
      'workspace_id': workspaceId,
      'session_id': sessionId,
    });
  }

  void stopSession(String workspaceId, String sessionId) {
    _sendCommand({
      'type': 'session_stop',
      'workspace_id': workspaceId,
      'session_id': sessionId,
    });
  }

  void killSession(String workspaceId, String sessionId) {
    _sendCommand({
      'type': 'session_kill',
      'workspace_id': workspaceId,
      'session_id': sessionId,
    });
  }

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

  void requestSessionHealth(String workspaceId, String sessionId) {
    _sendCommand({
      'type': 'session_health',
      'workspace_id': workspaceId,
      'session_id': sessionId,
    });
  }

  void pollSessionTask(String workspaceId, String sessionId, String taskId) {
    _sendCommand({
      'type': 'session_task_poll',
      'workspace_id': workspaceId,
      'session_id': sessionId,
      'task_id': taskId,
    });
  }

  void _sendCommand(Map<String, dynamic> payload) {
    _sendRaw('${jsonEncode(payload)}\n');
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

  void dispose() {
    _disposed = true;
    _pendingMessages.clear();
    _cleanup();
  }
}
