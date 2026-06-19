import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../app/app_config.dart';

class GalleryImageSaver {
  GalleryImageSaver({
    MethodChannel channel = const MethodChannel('family_todo_mobile/share'),
    http.Client? httpClient,
    this.apiBaseUrl = AppConfig.apiBaseUrl,
    this.apiKey = AppConfig.apiKey,
  })  : _channel = channel,
        _client = httpClient ?? http.Client();

  final MethodChannel _channel;
  final http.Client _client;
  final String apiBaseUrl;
  final String apiKey;

  Future<bool> saveNetworkImage(String url) async {
    final sourceUrl = url.trim();
    final uri = Uri.tryParse(sourceUrl);
    if (uri == null || !_isHttpUrl(uri)) {
      return false;
    }

    final response = await _client.get(uri, headers: _headersFor(uri));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return false;
    }
    if (response.bodyBytes.isEmpty) {
      return false;
    }

    final saved = await _channel.invokeMethod<bool>('saveImageBytes', {
      'bytes': response.bodyBytes,
      'contentType': response.headers['content-type'] ?? '',
      'sourceUrl': sourceUrl,
    });
    return saved == true;
  }

  void close() {
    _client.close();
  }

  Map<String, String> _headersFor(Uri imageUri) {
    final headers = <String, String>{'Accept': 'image/*'};
    final key = apiKey.trim();
    if (key.isNotEmpty && _shouldAttachApiKey(imageUri)) {
      headers['X-Api-Key'] = key;
    }
    return headers;
  }

  bool _shouldAttachApiKey(Uri imageUri) {
    final baseUri = Uri.tryParse(apiBaseUrl.trim());
    if (baseUri == null || !_isHttpUrl(baseUri)) {
      return false;
    }
    return imageUri.scheme.toLowerCase() == baseUri.scheme.toLowerCase() &&
        imageUri.host.toLowerCase() == baseUri.host.toLowerCase() &&
        _effectivePort(imageUri) == _effectivePort(baseUri);
  }

  bool _isHttpUrl(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    switch (uri.scheme.toLowerCase()) {
      case 'http':
        return 80;
      case 'https':
        return 443;
      default:
        return -1;
    }
  }
}
