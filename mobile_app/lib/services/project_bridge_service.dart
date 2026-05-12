import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/project_contact.dart';

/// Message received from the project bridge server.
class BridgeMessage {
  BridgeMessage({
    required this.type,
    this.text = '',
    this.tuiRunning = false,
    this.projectId = '',
    this.projects = const [],
  });

  final String type;
  final String text;
  final bool tuiRunning;
  final String projectId;
  final List<Map<String, dynamic>> projects;

  factory BridgeMessage.fromJson(Map<String, dynamic> json) {
    return BridgeMessage(
      type: (json['type'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      tuiRunning: json['tui_running'] == true,
      projectId: (json['project_id'] ?? '').toString(),
      projects: (json['projects'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          const [],
    );
  }

  bool get isOutput => type == 'output';
  bool get isStatus => type == 'status';
  bool get isError => type == 'error';
  bool get isSent => type == 'sent';
  bool get isPong => type == 'pong';
  bool get isProjects => type == 'projects';
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

  Socket? _socket;
  bool _running = false;
  final StringBuffer _buffer = StringBuffer();

  bool get isConnected => _socket != null && _running;

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

  /// Connect to the bridge server.
  Future<bool> connect() async {
    if (_running) {
      return true;
    }

    final address = await getServerAddress();
    final parts = address.split(':');
    final host = parts[0].trim();
    final port = parts.length > 1
        ? int.tryParse(parts[1].trim()) ?? 9876
        : 9876;

    try {
      _socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      _running = true;
      onStatusChange(true, 'Connected to $address');

      // Listen for messages
      _socket!.listen(
        _onData,
        onError: (error) {
          onStatusChange(false, 'Connection error: $error');
          _cleanup();
        },
        onDone: () {
          onStatusChange(false, 'Server disconnected');
          _cleanup();
        },
      );

      // Don't send anything — wait for startProject() to send 'connect'
      return true;
    } catch (e) {
      onStatusChange(false, 'Failed to connect: $e');
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
  void startProject(ProjectContact project) {
    if (!isConnected) {
      return;
    }
    final message = jsonEncode({
      'type': 'connect',
      'project_id': project.id,
    });
    _sendRaw('$message\n');
  }

  /// Send text to the current project session.
  void sendText(String text) {
    if (!isConnected) {
      return;
    }
    final message = jsonEncode({
      'type': 'send',
      'text': text,
    });
    _sendRaw('$message\n');
  }

  void _sendRaw(String data) {
    try {
      _socket?.write(data);
    } catch (_) {
      _cleanup();
    }
  }

  void _cleanup() {
    _running = false;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
  }

  void dispose() {
    _cleanup();
  }
}
