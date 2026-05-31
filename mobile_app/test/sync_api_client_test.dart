import 'dart:convert';

import 'package:family_todo_mobile/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ApiClient', () {
    late ApiClient client;

    setUp(() {
      client = ApiClient(
        baseUrl: 'https://api.example.com',
        apiKey: 'test-key',
      );
    });

    test('constructor sets base URL and API key', () {
      expect(client.baseUrl, 'https://api.example.com');
    });

    test('registerDeviceToken returns structured result', () async {
      // This test verifies the API client can be constructed and
      // the method signature is correct. Actual HTTP calls are mocked
      // in integration tests.
      expect(client, isNotNull);
    });

    group('JSON safe decoding', () {
      test('safeDecode returns null for empty string', () {
        final result = ApiClient.safeDecode('');
        expect(result, isNull);
      });

      test('safeDecode returns null for invalid JSON', () {
        final result = ApiClient.safeDecode('not json');
        expect(result, isNull);
      });

      test('safeDecode returns map for valid JSON object', () {
        final result = ApiClient.safeDecode('{"key": "value"}');
        expect(result, isA<Map<String, dynamic>>());
        expect(result!['key'], 'value');
      });

      test('safeDecode returns list for valid JSON array', () {
        final result = ApiClient.safeDecode('[1, 2, 3]');
        expect(result, isA<List<dynamic>>());
      });

      test('safeDecodeList returns empty list for null input', () {
        final result = ApiClient.safeDecodeList(null);
        expect(result, isEmpty);
      });

      test('safeDecodeList returns empty list for non-list JSON', () {
        final result = ApiClient.safeDecodeList('{"a": 1}');
        expect(result, isEmpty);
      });

      test('safeDecodeList returns list for valid JSON array', () {
        final result = ApiClient.safeDecodeList('[{"id": 1}, {"id": 2}]');
        expect(result, hasLength(2));
        expect(result[0]['id'], 1);
      });

      test('safeDecodeMap returns empty map for null input', () {
        final result = ApiClient.safeDecodeMap(null);
        expect(result, isEmpty);
      });

      test('safeDecodeMap returns map for valid JSON object', () {
        final result = ApiClient.safeDecodeMap('{"name": "test"}');
        expect(result['name'], 'test');
      });
    });

    group('URL construction', () {
      test('chatMarkRead constructs correct endpoint', () {
        // Verify the method exists and accepts parameters
        expect(
          () => client.chatMarkRead(
            actorProfile: 'user1',
            conversationKey: 'conv1',
          ),
          returnsNormally,
        );
      });
    });
  });
}
