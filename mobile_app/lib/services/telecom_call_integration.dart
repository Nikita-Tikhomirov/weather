import 'package:flutter/services.dart';

class TelecomCallIntegration {
  const TelecomCallIntegration([this._channel = _defaultChannel]);

  static const _defaultChannel = MethodChannel('family_todo_mobile/telecom');

  final MethodChannel _channel;

  Future<bool> registerPhoneAccounts() {
    return _invokeBool('registerPhoneAccounts');
  }

  Future<bool> isManagedPhoneAccountEnabled() {
    return _invokeBool('isManagedPhoneAccountEnabled');
  }

  Future<bool> openPhoneAccountSettings() {
    return _invokeBool('openPhoneAccountSettings');
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
}
