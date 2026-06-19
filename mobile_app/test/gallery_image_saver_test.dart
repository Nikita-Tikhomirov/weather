import 'package:family_todo_mobile/services/gallery_image_saver.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GalleryImageSaver', () {
    test(
      'downloads image bytes and sends them to the platform saver',
      () async {
        final imageBytes = Uint8List.fromList(<int>[
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
        ]);
        final seenRequests = <http.Request>[];
        final httpClient = MockClient((request) async {
          seenRequests.add(request);
          return http.Response.bytes(
            imageBytes,
            200,
            headers: {'content-type': 'image/png'},
          );
        });

        const channel = MethodChannel('test/gallery_image_saver');
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        const baseUrl = 'https://api.example.test';
        final saver = GalleryImageSaver(
          channel: channel,
          httpClient: httpClient,
          apiBaseUrl: baseUrl,
          apiKey: 'test-key',
        );
        addTearDown(saver.close);

        final saved = await saver.saveNetworkImage('$baseUrl/chat/media/photo');

        expect(saved, isTrue);
        expect(seenRequests, hasLength(1));
        expect(seenRequests.single.headers['Accept'], 'image/*');
        expect(seenRequests.single.headers['X-Api-Key'], 'test-key');
        expect(calls, hasLength(1));
        expect(calls.single.method, 'saveImageBytes');
        final args = Map<String, dynamic>.from(calls.single.arguments as Map);
        expect(args['bytes'], orderedEquals(imageBytes));
        expect(args['contentType'], 'image/png');
        expect(args['sourceUrl'], '$baseUrl/chat/media/photo');
      },
    );
  });
}
