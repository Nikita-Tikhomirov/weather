import 'dart:convert';
import 'dart:io';

import 'package:family_todo_mobile/services/chat_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChatApiClient uploads', () {
    late HttpServer server;
    late Future<void> serverLoop;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverLoop = () async {
        await for (final request in server) {
          await request.drain<void>();
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'asset_url': '/chat/media/uploaded.bin',
              'image_meta': {'stored': true},
            }),
          );
          await request.response.close();
        }
      }();
    });

    tearDown(() async {
      await server.close(force: true);
      await serverLoop.catchError((_) {});
    });

    test('media upload reports intermediate byte progress', () async {
      final client = ChatApiClient(
        baseUrl: 'http://${server.address.host}:${server.port}',
        apiKey: 'test-key',
      );
      final progressValues = <double>[];
      final bytes = List<int>.filled(256 * 1024, 7);

      final result = await client.chatUploadMedia(
        actorProfile: 'test_user',
        bytes: bytes,
        filename: 'large.jpg',
        onProgress: progressValues.add,
      );

      expect(result.assetUrl, '/chat/media/uploaded.bin');
      expect(progressValues, isNotEmpty);
      expect(
        progressValues.any((value) => value > 0 && value < 1),
        isTrue,
      );
      expect(progressValues.last, 1);
    });
  });
}
