import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/api_client.dart';

/// Standalone profile-initialization helper extracted from _HomePageState.
///
/// Manages device-id generation, profile restoration by phone number,
/// and the first-launch phone-number dialog.
/// All dependencies injected — no access to widget state.
class HomeProfileInitializer {
  HomeProfileInitializer({
    required this.api,
    required this.prefs,
    this.onProfileInfo,
  });

  final ApiClient api;
  final SharedPreferences prefs;
  final void Function(String displayName, String phone)? onProfileInfo;

  String currentProfileDisplayName = '';
  String currentProfilePhone = '';

  /// Generate or retrieve a stable device identifier.
  Future<String> ensureDeviceId() async {
    final saved = prefs.getString('device_id')?.trim() ?? '';
    if (saved.isNotEmpty) return saved;
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    final value = 'dev-${DateTime.now().microsecondsSinceEpoch}-$random';
    await prefs.setString('device_id', value);
    return value;
  }

  /// Restore a profile by phone number via the backend.
  ///
  /// Returns the profile key on success.
  Future<String> restoreProfileByPhone(String phone) async {
    final deviceId = await ensureDeviceId();
    final session = await api.deviceStart(
      phone: phone,
      deviceId: deviceId,
      displayName: currentProfileDisplayName,
    );
    await prefs.setString('actor_profile', session.profileKey);
    await prefs.setString('profile_phone', session.phone);
    await prefs.setString('profile_display_name', session.displayName);
    currentProfileDisplayName = session.displayName;
    currentProfilePhone = session.phone;
    return session.profileKey;
  }

  /// Show a dialog asking for phone number and name on first launch.
  ///
  /// [context] must be valid (the caller checks `mounted` before calling).
  /// Returns the resolved profile key, or `null` if cancelled / not mounted.
  Future<String?> promptForInitialProfile(BuildContext context) async {
    // Let the frame settle
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) {
      return null;
    }

    final phoneCtl = TextEditingController();
    final nameCtl = TextEditingController();
    String errorText = '';

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Вход по номеру телефона'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: phoneCtl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Номер телефона',
                      hintText: '+7 999 111 22 33',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Имя'),
                  ),
                  if (errorText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(errorText, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
              actions: [
                FilledButton(
                  onPressed: () async {
                    try {
                      final deviceId = await ensureDeviceId();
                      final session = await api.deviceStart(
                        phone: phoneCtl.text,
                        deviceId: deviceId,
                        displayName: nameCtl.text,
                      );
                      await prefs.setString(
                        'actor_profile',
                        session.profileKey,
                      );
                      await prefs.setString('profile_phone', session.phone);
                      await prefs.setString(
                        'profile_display_name',
                        session.displayName,
                      );
                      onProfileInfo?.call(session.displayName, session.phone);
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(session.profileKey);
                      }
                    } catch (error) {
                      setDialogState(() => errorText = error.toString());
                    }
                  },
                  child: const Text('Продолжить'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
