import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:family_todo_mobile/models/project_contact.dart';
import 'package:family_todo_mobile/services/project_bridge_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dispose closes socket without reporting a connection loss', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final accepted = Completer<Socket>();
    final statuses = <String>[];

    final sub = server.listen((socket) {
      accepted.complete(socket);
    });

    SharedPreferences.setMockInitialValues({
      'bridge_host': '127.0.0.1:${server.port}',
    });

    final service = ProjectBridgeService(
      onMessage: (_) {},
      onStatusChange: (_, status) => statuses.add(status),
    );

    service.startProject(const ProjectContact(
      id: 'cifra',
      name: 'Цифра',
      path: r'C:\Users\user\Desktop\depseeker_test',
    ));

    expect(await service.connect(), isTrue);
    final socket = await accepted.future.timeout(const Duration(seconds: 2));

    service.dispose();
    await socket.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(
      statuses,
      isNot(contains('Соединение потеряно, переподключаюсь...')),
    );

    await sub.cancel();
    await server.close();
  });

  test('queued message is sent after reconnect', () async {
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

    final service = ProjectBridgeService(
      onMessage: (_) {},
      onStatusChange: (_, __) {},
    );

    service.startProject(const ProjectContact(
      id: 'cifra',
      name: 'Цифра',
      path: r'C:\Users\user\Desktop\depseeker_test',
    ));

    expect(service.sendText('hello while offline'), isFalse);
    expect(await service.connect(), isTrue);

    await connected.future.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(
      received,
      containsAllInOrder([
        containsPair('type', 'connect'),
        containsPair('type', 'send'),
      ]),
    );
    expect(
      received.any((row) => row['text'] == 'hello while offline'),
      isTrue,
    );

    service.dispose();
    await sub.cancel();
    await server.close();
  });

  test('image upload sends a file payload to the bridge', () async {
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

    final service = ProjectBridgeService(
      onMessage: (_) {},
      onStatusChange: (_, __) {},
    );

    service.startProject(const ProjectContact(
      id: 'cifra',
      name: 'Цифра',
      path: r'C:\Users\user\Desktop\depseeker_test',
    ));

    expect(await service.connect(), isTrue);
    await connected.future.timeout(const Duration(seconds: 2));

    expect(
      service.sendImage(
        fileName: 'screen.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
        caption: 'look at this',
      ),
      isTrue,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final upload = received.firstWhere((row) => row['type'] == 'upload_file');
    expect(upload['filename'], 'screen.png');
    expect(upload['mime_type'], 'image/png');
    expect(upload['data_base64'], base64Encode([1, 2, 3]));
    expect(upload['caption'], 'look at this');

    service.dispose();
    await sub.cancel();
    await server.close();
  });

  test('oversized image upload is rejected before socket send', () {
    final statuses = <String>[];
    final service = ProjectBridgeService(
      onMessage: (_) {},
      onStatusChange: (_, status) => statuses.add(status),
    );

    expect(
      service.sendImage(
        fileName: 'huge.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List(ProjectBridgeService.maxProjectUploadBytes + 1),
      ),
      isFalse,
    );
    expect(statuses.single, contains('15 МБ'));

    service.dispose();
  });

  test('empty image upload is rejected before socket send', () {
    final service = ProjectBridgeService(
      onMessage: (_) {},
      onStatusChange: (_, __) {},
    );

    expect(
      service.sendImage(
        fileName: 'empty.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List(0),
      ),
      isFalse,
    );

    service.dispose();
  });

  test('start bridge sends launcher command', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final received = <Map<String, dynamic>>[];
    final connected = Completer<void>();

    final sub = server.listen((socket) async {
      connected.complete();
      final line =
          await utf8.decoder.bind(socket).transform(const LineSplitter()).first;
      received.add(jsonDecode(line) as Map<String, dynamic>);
      final reply = '${jsonEncode({
            'type': 'status',
            'text': 'Bridge start requested for cifra',
          })}\n';
      socket.add(utf8.encode(reply));
      await socket.flush();
    });

    SharedPreferences.setMockInitialValues({
      'bridge_host': '127.0.0.1:${server.port}',
    });

    final ok =
        await ProjectBridgeService.requestBridgeStart(const ProjectContact(
      id: 'cifra',
      name: 'Цифра',
      path: r'C:\Users\user\Desktop\depseeker_test',
    ));

    expect(ok, isTrue);
    await connected.future.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(received.single['type'], 'start_bridge');
    expect(received.single['project_id'], 'cifra');

    await sub.cancel();
    await server.close();
  });

  test('history message parses replayed bridge messages', () {
    final message = BridgeMessage.fromJson({
      'type': 'history',
      'session_id': 's1',
      'messages': [
        {'type': 'send', 'text': 'prompt', 'session_id': 's1'},
        {'type': 'output', 'text': 'answer', 'session_id': 's1'},
      ],
    });

    expect(message.isHistory, isTrue);
    expect(message.sessionId, 's1');
    expect(message.messages.length, 2);
    expect(message.messages.last.text, 'answer');
  });

  test('incoming utf8 split across tcp chunks is decoded after full line', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final messages = <BridgeMessage>[];
    final connected = Completer<void>();

    final sub = server.listen((socket) async {
      connected.complete();
      final payload = utf8.encode('${jsonEncode({
            'type': 'output',
            'text': 'Привет из TUI',
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

    final service = ProjectBridgeService(
      onMessage: messages.add,
      onStatusChange: (_, __) {},
    );

    expect(await service.connect(), isTrue);
    await connected.future.timeout(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(messages.single.text, 'Привет из TUI');

    service.dispose();
    await sub.cancel();
    await server.close();
  });

  test('new session and stop commands are sent to the bridge', () async {
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

    final service = ProjectBridgeService(
      onMessage: (_) {},
      onStatusChange: (_, __) {},
    );
    service.startProject(const ProjectContact(
      id: 'cifra',
      name: 'Цифра',
      path: r'C:\Users\user\Desktop\depseeker_test',
    ));

    expect(await service.connect(), isTrue);
    await connected.future.timeout(const Duration(seconds: 2));
    service.startNewSession();
    service.stopCurrentPrompt();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(received.any((row) => row['type'] == 'new_session'), isTrue);
    expect(received.any((row) => row['type'] == 'stop'), isTrue);

    service.dispose();
    await sub.cancel();
    await server.close();
  });
}
