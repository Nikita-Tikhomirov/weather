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
}
