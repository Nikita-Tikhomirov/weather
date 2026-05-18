import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/project_contact.dart';
import '../models/project_file.dart';

/// Message received from the project bridge server.
class BridgeMessage {
  BridgeMessage({
    required this.type,
    this.text = '',
    this.tuiRunning = false,
    this.projectId = '',
    this.sessionId = '',
    this.projects = const [],
    this.messages = const [],
    this.imageBase64 = '',
    this.imageMimeType = '',
    this.imageFilename = '',
    this.files = const [],
    this.filePath = '',
    this.fileSize = 0,
  });

  final String type;
  final String text;
  final bool tuiRunning;
  final String projectId;
  final String sessionId;
  final List<Map<String, dynamic>> projects;
  final List<BridgeMessage> messages;
  final String imageBase64;
  final String imageMimeType;
  final String imageFilename;
  final List<ProjectFileNode> files;
  final String filePath;
  final int fileSize;

  factory BridgeMessage.fromJson(Map<String, dynamic> json) {
    return BridgeMessage(
      type: (json['type'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      tuiRunning: json['tui_running'] == true,
      projectId: (json['project_id'] ?? '').toString(),
      sessionId: (json['session_id'] ?? '').toString(),
      projects: (json['projects'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          const [],
      messages: (json['messages'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(BridgeMessage.fromJson)
              .toList() ??
          const [],
      imageBase64: (json['data_base64'] ?? '').toString(),
      imageMimeType: (json['mime_type'] ?? '').toString(),
      imageFilename: (json['filename'] ?? '').toString(),
      files: (json['files'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(ProjectFileNode.fromJson)
              .toList() ??
          const [],
      filePath: (json['path'] ?? '').toString(),
      fileSize: int.tryParse((json['size'] ?? 0).toString()) ?? 0,
    );
  }

  bool get isImage => type == 'image';
  bool get isOutput => type == 'output';
  bool get isStatus => type == 'status';
  bool get isError => type == 'error';
  bool get isSent => type == 'sent';
  bool get isPong => type == 'pong';
  bool get isProjects => type == 'projects';
  bool get isHistory => type == 'history';
  bool get isSessionInfo => type == 'session_info';
  bool get isFiles => type == 'files';
  bool get isFileContent => type == 'file_content';

  String get fileContentText => text;
  String get fileContentPath => projectId.isNotEmpty ? '$projectId:$text' : text;
  String get fileContentError => text.startsWith('Error:') ? text : '';
}

/// Manages TCP connection to the remote Project Bridge Server running on PC.
///
/// Server address is stored in SharedPreferences under key 'bridge_host'.
/// Default: '10.0.0.5:9876' (replace with actual PC IP).
class ProjectBridgeService {
  ProjectBridgeService({
    required this.onMessage,
    required this.onStatusChange,
  });

  final void Function(BridgeMessage message) onMessage;
  final void Function(bool connected, String status) onStatusChange;
  static const int maxProjectUploadBytes = 15 * 1024 * 1024;

  Socket? _socket;
  bool _running = false;
  bool _disposed = false;
  bool _connecting = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  ProjectContact? _activeProject;
  final List<String> _pendingSends = <String>[];
  final StringBuffer _buffer = StringBuffer();
  
  /// Current session id (set by session_info messages from bridge).
  String? currentSessionId;

  /// Cached resume session id to use after reconnect.
  String? _pendingResumeSessionId;

  bool get isConnected => _socket != null && _running;

  /// The project id currently active (or last started) on this bridge.
  String? get activeProjectId => _activeProject?.id;

  /// Resolve server address from SharedPreferences.
  static Future<String> getServerAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('bridge_host') ?? '31.129.97.211:9877';
  }

  /// Save server address to SharedPreferences.
  static Future<void> setServerAddress(String host) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bridge_host', host);
  }

  /// Ask the PC-side launcher to start project_bridge.py through the tunnel.
  static Future<bool> requestBridgeStart(ProjectContact project) async {
    final address = await getServerAddress();
    final parts = address.split(':');
    final host = parts[0].trim();
    final port =
        parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 9876 : 9876;
    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      final reply = Completer<bool>();
      final buffer = StringBuffer();
      socket.listen(
        (data) {
          buffer.write(utf8.decode(data));
          final content = buffer.toString();
          final newlineIndex = content.indexOf('\n');
          if (newlineIndex < 0) {
            return;
          }
          final line = content.substring(0, newlineIndex).trim();
          if (line.isEmpty || reply.isCompleted) {
            return;
          }
          try {
            final decoded = jsonDecode(line) as Map<String, dynamic>;
            reply.complete(decoded['type'] != 'error');
          } catch (_) {
            reply.complete(false);
          }
        },
        onError: (_) {
          if (!reply.isCompleted) {
            reply.complete(false);
          }
        },
        onDone: () {
          if (!reply.isCompleted) {
            reply.complete(false);
          }
        },
      );
      final request = '${jsonEncode({
            'type': 'start_bridge',
            'project_id': project.id,
          })}\n';
      socket.write(request);
      await socket.flush();
      return await reply.future.timeout(const Duration(seconds: 3));
    } catch (_) {
      return false;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  /// Connect to the bridge server.
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
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final address = await getServerAddress();
    final parts = address.split(':');
    final host = parts[0].trim();
    final port =
        parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 9876 : 9876;

    try {
      _socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      _running = true;
      _connecting = false;
      _reconnectAttempt = 0;
      onStatusChange(true, 'Connected to $address');

      // Listen for messages
      _socket!.listen(
        _onData,
        onError: (error) {
          if (_disposed) {
            _cleanup();
            return;
          }
          onStatusChange(false, 'Ошибка соединения: $error');
          _cleanup();
          _scheduleReconnect();
        },
        onDone: () {
          if (_disposed) {
            _cleanup();
            return;
          }
          onStatusChange(false, 'Соединение потеряно, переподключаюсь...');
          _cleanup();
          _scheduleReconnect();
        },
      );

      final project = _activeProject;
      if (project != null) {
        startProject(project);
      }
      _flushPendingSends();
      return true;
    } catch (e) {
      _connecting = false;
      if (!_disposed) {
        onStatusChange(false, 'Не удалось подключиться: $e');
        _scheduleReconnect();
      }
      _cleanup();
      return false;
    }
  }

  void _onData(Uint8List data) {
    _buffer.write(utf8.decode(data));
    // Process complete lines
    while (true) {
      final content = _buffer.toString();
      final newlineIndex = content.indexOf('\n');
      if (newlineIndex < 0) {
        break;
      }
      final line = content.substring(0, newlineIndex).trim();
      _buffer.clear();
      if (newlineIndex + 1 < content.length) {
        _buffer.write(content.substring(newlineIndex + 1));
      }

      if (line.isEmpty) {
        continue;
      }

      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        onMessage(BridgeMessage.fromJson(json));
      } catch (_) {
        // Plain text line
        onMessage(BridgeMessage(type: 'output', text: line));
      }
    }
  }

  /// Start a project session via tunnel (connect to PC bridge).
  /// If [resumeSessionId] is provided, the bridge will try to resume that session.
  void startProject(ProjectContact project, {String? resumeSessionId}) {
    _activeProject = project;
    if (resumeSessionId != null && resumeSessionId.isNotEmpty) {
      _pendingResumeSessionId = resumeSessionId;
    }
    if (!isConnected) {
      _scheduleReconnect();
      return;
    }
    final payload = <String, dynamic>{
      'type': 'connect',
      'project_id': project.id,
    };
    final sid = _pendingResumeSessionId;
    if (sid != null && sid.isNotEmpty) {
      payload['session_id'] = sid;
      _pendingResumeSessionId = null;
    }
    _sendRaw('${jsonEncode(payload)}\n');
  }

  /// Send text to the current project session.
  bool sendText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (!isConnected) {
      if (_pendingSends.length >= 20) {
        _pendingSends.removeAt(0);
      }
      _pendingSends.add(trimmed);
      onStatusChange(false,
          'Нет соединения, сообщение будет отправлено после переподключения.');
      _scheduleReconnect();
      return false;
    }
    final message = jsonEncode({
      'type': 'send',
      'text': trimmed,
    });
    _sendRaw('$message\n');
    return true;
  }

  /// Upload an image to the selected project's vision/ folder.
  bool sendImage({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    String caption = '',
  }) {
    if (bytes.isEmpty) {
      return false;
    }
    if (bytes.length > maxProjectUploadBytes) {
      onStatusChange(
          false, 'Фото больше 15 МБ. Уменьшите фото или отправьте другое.');
      return false;
    }
    if (!isConnected) {
      onStatusChange(
          false, 'Нет соединения, фото можно отправить после переподключения.');
      _scheduleReconnect();
      return false;
    }
    final message = jsonEncode({
      'type': 'upload_file',
      'filename': fileName.trim().isEmpty ? 'photo.jpg' : fileName.trim(),
      'mime_type': mimeType.trim().isEmpty ? 'image/jpeg' : mimeType.trim(),
      'data_base64': base64Encode(bytes),
      if (caption.trim().isNotEmpty) 'caption': caption.trim(),
    });
    _sendRaw('$message\n');
    return true;
  }

  void startNewSession() {
    if (!isConnected) {
      _scheduleReconnect();
      return;
    }
    _sendRaw('${jsonEncode({'type': 'new_session'})}\n');
  }

  void stopCurrentPrompt() {
    if (!isConnected) {
      _scheduleReconnect();
      return;
    }
    _sendRaw('${jsonEncode({'type': 'stop'})}\n');
  }

  /// Request file tree from the project (recursive listing).
  void requestFileTree({String path = ''}) {
    if (!isConnected) {
      _scheduleReconnect();
      return;
    }
    final payload = <String, dynamic>{
      'type': 'list_files',
      'recursive': true,
    };
    if (path.isNotEmpty) {
      payload['path'] = path;
    }
    _sendRaw('${jsonEncode(payload)}\n');
  }

  /// Request file listing for a single directory (non-recursive).
  void requestFileList(String path) {
    if (!isConnected) {
      _scheduleReconnect();
      return;
    }
    _sendRaw('${jsonEncode({
          'type': 'list_files',
          'path': path,
          'recursive': false,
        })}\n');
  }

  /// Request file content for viewing.
  void requestFileContent(String path) {
    if (!isConnected) {
      _scheduleReconnect();
      return;
    }
    _sendRaw('${jsonEncode({
          'type': 'read_file',
          'path': path,
        })}\n');
  }

  void _sendRaw(String data) {
    try {
      _socket?.write(data);
    } catch (_) {
      if (!_disposed) {
        onStatusChange(
            false, 'Не удалось отправить данные, переподключаюсь...');
      }
      _cleanup();
      _scheduleReconnect();
    }
  }

  void _cleanup() {
    _running = false;
    _connecting = false;
    _buffer.clear();
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _pendingSends.clear();
    _cleanup();
  }

  void _scheduleReconnect() {
    if (_disposed || _activeProject == null || _reconnectTimer != null) {
      return;
    }
    final delaySeconds = _reconnectAttempt < 1
        ? 1
        : (_reconnectAttempt < 2 ? 2 : (_reconnectAttempt < 3 ? 4 : 8));
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      _reconnectTimer = null;
      if (_disposed) {
        return;
      }
      await connect();
    });
  }

  void _flushPendingSends() {
    if (!isConnected || _pendingSends.isEmpty) {
      return;
    }
    final queued = List<String>.from(_pendingSends);
    _pendingSends.clear();
    for (final text in queued) {
      sendText(text);
    }
  }
}