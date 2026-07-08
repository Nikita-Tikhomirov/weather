import 'package:flutter/services.dart';

class TelecomCallIntegration {
  const TelecomCallIntegration([this._channel = _defaultChannel]);

  static const _defaultChannel = MethodChannel('family_todo_mobile/telecom');

  final MethodChannel _channel;

  Future<bool> registerPhoneAccounts() {
    return _invokeBool('registerPhoneAccounts');
  }

  Future<bool> canUseFullScreenIntent() {
    return _invokeBool('canUseFullScreenIntent');
  }

  Future<bool> openFullScreenIntentSettings() {
    return _invokeBool('openFullScreenIntentSettings');
  }

  Future<bool> canPostNotifications() {
    return _invokeBool('canPostNotifications');
  }

  Future<bool> openNotificationSettings() {
    return _invokeBool('openNotificationSettings');
  }

  Future<bool> canUseCallNotificationChannel() {
    return _invokeBool('canUseCallNotificationChannel');
  }

  Future<bool> openCallNotificationChannelSettings() {
    return _invokeBool('openCallNotificationChannelSettings');
  }

  Future<bool> showIncomingCall(Map<String, dynamic> data) {
    return _invokeBool(
      'showIncomingCall',
      {'data': _stringMap(data)},
    );
  }

  Future<bool> answerIncomingConnection(String sessionId) {
    return _invokeBool(
      'answerIncomingConnection',
      {'sessionId': sessionId},
    );
  }

  Future<bool> rejectIncomingConnection(String sessionId) {
    return _invokeBool(
      'rejectIncomingConnection',
      {'sessionId': sessionId},
    );
  }

  Future<bool> endIncomingConnection(String sessionId) {
    return _invokeBool(
      'endIncomingConnection',
      {'sessionId': sessionId},
    );
  }

  Future<bool> _invokeBool(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<bool>(method, arguments) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Map<String, String> _stringMap(Map<String, dynamic> data) {
    final out = <String, String>{};
    for (final entry in data.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) continue;
      out[key] = entry.value?.toString() ?? '';
    }
    return out;
  }
}
