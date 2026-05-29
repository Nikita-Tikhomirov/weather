import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:family_todo_mobile/models/workspace_item.dart';
import 'package:family_todo_mobile/models/workspace_session.dart';
import 'package:family_todo_mobile/services/codewhale_bridge_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('workspace item parses bridge json', () {
    final item = WorkspaceItem.fromJson({
      'id': 'weather',
      'name': 'Погода',
      'path': r'C:\Users\user\Desktop\weather',
      'status': 'available',
      'created_at': 10,
      'updated_at': 20,
    });

    expect(item.id, 'weather');
    expect(item.name, 'Погода');
    expect(item.path, r'C:\Users\user\Desktop\weather');
    expect(item.status, WorkspaceStatus.available);
    expect(item.isAvailable, isTrue);
  });

  test('workspace session parses bridge json', () {
    final session = WorkspaceSession.fromJson({
      'id': 'session-1',
      'workspace_id': 'weather',
      'title': 'Починить мост',
      'status': 'running',
      'worker_pid': 1234,
      'worker_port': 43101,
      'created_at': 10,
      'updated_at': 20,
      'last_event_seq': 7,
    });

    expect(session.id, 'session-1');
    expect(session.workspaceId, 'weather');
    expect(session.status, WorkspaceSessionStatus.running);
    expect(session.workerPid, 1234);
    expect(session.isRunning, isTrue);
  });

  test('assistant delta parses live stream fields', () {
    final message = CodeWhaleBridgeMessage.fromJson({
      'type': 'assistant_delta',
      'workspace_id': 'weather',
      'session_id': 'session-1',
      'text': 'При',
      'final': false,
    });

    expect(message.type, 'assistant_delta');
    expect(message.workspaceId, 'weather');
    expect(message.sessionId, 'session-1');
    expect(message.text, 'При');
    expect(message.isFinal, isFalse);
  });

  test('connect registers as codewhale mobile client', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final received = <Map<String, dynamic>>[];
    final connected = Completer<void>();

    final sub = server.listen((socket) {
      connected.complete();
      utf8.decoder.bind(socket).transform(const LineSplitter()).listen((line) {
        received.add(jsonDecode(line) as Map<String, dynamic>);
      });
    });

    SharedPreferences.setMockInitialValues({
      'bridge_host': '127.0.0.1:${server.port}',
    });

    final service = CodeWhaleBridgeService(
      onMessage: (_) {},
      onStatusChange: (_, __) {},
    );

    expect(await service.connect(), isTrue);
    await connected.future.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(received.single['type'], 'codewhale_connect');
    expect(received.single['project_id'], 'codewhale');

    service.dispose();
    await sub.cancel();
    await server.close();
  });

  test('workspace and session commands are sent as json lines', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final received = <Map<String, dynamic>>[];
    final connected = Completer<void>();

    final sub = server.listen((socket) {
      connected.complete();
      utf8.decoder.bind(socket).transform(const LineSplitter()).listen((line) {
        received.add(jsonDecode(line) as Map<String, dynamic>);
      });
    });

    SharedPreferences.setMockInitialValues({
      'bridge_host': '127.0.0.1:${server.port}',
    });

    final service = CodeWhaleBridgeService(
      onMessage: (_) {},
      onStatusChange: (_, __) {},
    );

    expect(await service.connect(), isTrue);
    await connected.future.timeout(const Duration(seconds: 2));
    service.requestWorkspaceList();
    service.createWorkspace('Новый проект');
    service.createSession('weather', title: 'Чат 1');
    service.killSession('weather', 'session-1');
    service.pollSessionTask('weather', 'session-1', 'task-1');
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(received.map((row) => row['type']), contains('workspace_list'));
    expect(received.any((row) => row['type'] == 'workspace_create'), isTrue);
    expect(received.any((row) => row['type'] == 'session_create'), isTrue);
    expect(received.any((row) => row['type'] == 'session_kill'), isTrue);
    expect(received.any((row) => row['type'] == 'session_task_poll'), isTrue);

    service.dispose();
    await sub.cancel();
    await server.close();
  });

  test('incoming utf8 split across tcp chunks is decoded after full line',
      () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final messages = <CodeWhaleBridgeMessage>[];
    final connected = Completer<void>();

    final sub = server.listen((socket) async {
      connected.complete();
      final payload = utf8.encode('${jsonEncode({
            'type': 'status',
            'text': 'Подключено к CodeWhale',
          })}\n');
      final splitIndex = payload.indexOf(0xd0) + 1;
      socket.add(payload.sublist(0, splitIndex));
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      socket.add(payload.sublist(splitIndex));
      await socket.flush();
    });

    SharedPreferences.setMockInitialValues({
      'bridge_host': '127.0.0.1:${server.port}',
    });

    final service = CodeWhaleBridgeService(
      onMessage: messages.add,
      onStatusChange: (_, __) {},
    );

    expect(await service.connect(), isTrue);
    await connected.future.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(messages.single.text, 'Подключено к CodeWhale');

    service.dispose();
    await sub.cancel();
    await server.close();
  });
}
