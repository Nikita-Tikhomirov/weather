import 'dart:convert';
import 'dart:developer' as dev;

import 'package:http/http.dart' as http;

class HttpApiClient {
  HttpApiClient({required this.baseUrl, required this.apiKey});

  final String baseUrl;
  final String apiKey;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Api-Key': apiKey,
      };

  Future<http.Response> postWithFallback({
    required List<String> paths,
    required String body,
  }) async {
    Object? lastError;
    for (final path in paths) {
      final uri = Uri.parse('$baseUrl$path');
      try {
        final response = await http.post(uri, headers: _headers, body: body);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }
        lastError = StateError(
          'POST failed: ${response.statusCode} ${response.body}',
        );
      } catch (err) {
        lastError = err;
      }
    }
    throw StateError('Unable to complete POST request: $lastError');
  }

  Future<http.Response> getWithFallback({
    required List<String> paths,
    Map<String, String>? query,
  }) async {
    Object? lastError;
    for (final path in paths) {
      final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
      try {
        final response = await http.get(uri, headers: _headers);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }
        lastError = StateError(
          'GET failed: ${response.statusCode} ${response.body}',
        );
      } catch (err) {
        lastError = err;
      }
    }
    throw StateError('Unable to complete GET request: $lastError');
  }

  /// POST with fallback paths, then decode the body as JSON.
  ///
  /// Wraps [postWithFallback] with a [jsonDecode] try/catch so callers
  /// get a decoded [Map] without risking uncaught [FormatException].
  Future<Map<String, dynamic>> postJsonWithFallback({
    required List<String> paths,
    required String body,
  }) async {
    final response = await postWithFallback(paths: paths, body: body);
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e, st) {
      dev.log('[http] JSON decode error for POST ${paths.first}: $e\n$st');
      rethrow;
    }
  }

  /// GET with fallback paths, then decode the body as JSON.
  Future<Map<String, dynamic>> getJsonWithFallback({
    required List<String> paths,
    Map<String, String>? query,
  }) async {
    final response = await getWithFallback(paths: paths, query: query);
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e, st) {
      dev.log('[http] JSON decode error for GET ${paths.first}: $e\n$st');
      rethrow;
    }
  }
}
