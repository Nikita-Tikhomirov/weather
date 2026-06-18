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

  Future<bool> _invokeBool(String method) async {
    try {
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
