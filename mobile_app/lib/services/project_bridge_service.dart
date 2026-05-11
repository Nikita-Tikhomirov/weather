import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/project_contact.dart';

/// Message received from the project bridge.
class BridgeMessage {
  BridgeMessage({
    required this.type,
    this.text = '',
    this.tuiRunning = false,
    this.projectDir = '',
  });

  final String type;
  final String text;
  final bool tuiRunning;
  final String projectDir;

  factory BridgeMessage.fromJson(Map<String, dynamic> json) {
    return BridgeMessage(
      type: (json['type'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      tuiRunning: json['tui_running'] == true,
      projectDir: (json['project_dir'] ?? '').toString(),
    );
  }

  bool get isOutput => type == 'output';
  bool get isStatus => type == 'status';
  bool get isError => type == 'error';
  bool get isSent => type == 'sent';
  bool get isPong => type == 'pong';
}

/// Manages a WebSocket connection to the Python project bridge.
class ProjectBridgeService {
  ProjectBridgeService({
    required this.project,
    required this.onMessage,
    required this.onStatusChange,
  });

  final ProjectContact project;
  final void Function(BridgeMessage message) onMessage;
  final void Function(bool connected, String status) onStatusChange;

  Socket? _socket;
  bool _running = false;
  Timer? _pingTimer;
  int _port = 0;
  final StringBuffer _buffer = StringBuffer();

  bool get isConnected => _socket != null && _running;

  /// Connect to the bridge. Reads port from the project's .project_bridge_port file.
  Future<bool> connect() async {
    if (_running) {
      return true;
    }

    // Try to read the port from the port file
    _port = await _readPortFile();
    if (_port <= 0) {
      onStatusChange(false, 'Bridge port file not found. Start project_bridge.py first.');
      return false;
    }

    try {
      _socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _port,
        timeout: const Duration(seconds: 5),
      );
      _running = true;
      onStatusChange(true, 'Connected to bridge on port $_port');

      // Start ping timer
      _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) => _ping());

      // Listen for messages
      _socket!.listen(
        _onData,
        onError: (error) {
          onStatusChange(false, 'Connection error: $error');
          _cleanup();
        },
        onDone: () {
          onStatusChange(false, 'Bridge disconnected');
          _cleanup();
        },
      );

      // Send a ping to verify
      _ping();

      return true;
    } catch (e) {
      onStatusChange(false, 'Failed to connect: $e');
      _cleanup();
      return false;
    }
  }

  Future<int> _readPortFile() async {
    try {
      final file = File('${project.path}\\.project_bridge_port'.replaceAll('\\', '/'));
      if (await file.exists()) {
        final content = await file.readAsString();
        return int.tryParse(content.trim()) ?? 0;
      }
    } catch (_) {}
    return 0;
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

  void _ping() {
    if (!isConnected) {
      return;
    }
    _sendRaw('{"type":"ping"}\n');
  }

  void restartTui() {
    if (!isConnected) {
      return;
    }
    _sendRaw('{"type":"restart"}\n');
  }

  void stopTui() {
    if (!isConnected) {
      return;
    }
    _sendRaw('{"type":"stop"}\n');
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
    _pingTimer?.cancel();
    _pingTimer = null;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
  }

  void dispose() {
    _cleanup();
  }
}
