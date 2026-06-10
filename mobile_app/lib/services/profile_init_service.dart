import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../services/api_client.dart';

/// Standalone profile-initialization service extracted from _HomePageState.
///
/// Manages device-id generation, profile restoration by phone,
/// and the first-run profile prompt dialog.
class ProfileInitService {
  ProfileInitService({
    required this.api,
    this.onProfileChanged,
  });

  final ApiClient api;
  final void Function(String displayName, String phone)? onProfileChanged;

  /// Ensure a persistent device-id exists in SharedPreferences.
  static Future<String> ensureDeviceId(SharedPreferences prefs) async {
    final saved = prefs.getString('device_id')?.trim() ?? '';
    if (saved.isNotEmpty) {
      return saved;
    }
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    final value = 'dev-${DateTime.now().microsecondsSinceEpoch}-$random';
    await prefs.setString('device_id', value);
    return value;
  }

  /// Restore profile by phone number using the device-start API.
  Future<String> restoreProfileByPhone(
    SharedPreferences prefs,
    String phone,
    String displayName,
  ) async {
    final deviceId = await ensureDeviceId(prefs);
    final session = await api.deviceStart(
      phone: phone,
      deviceId: deviceId,
      displayName: displayName,
    );
    await prefs.setString('actor_profile', session.profileKey);
    await prefs.setString('profile_phone', session.phone);
    await prefs.setString('profile_display_name', session.displayName);
    onProfileChanged?.call(session.displayName, session.phone);
    return session.profileKey;
  }

  /// Show the first-run profile prompt dialog.
  /// Returns the selected profile key, or null if cancelled.
  static Future<String?> promptForInitialProfile(
    BuildContext context,
    ApiClient api,
    void Function(String displayName, String phone) onProfileChanged,
  ) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!context.mounted) return null;

    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return null;

    final phoneCtl = TextEditingController();
    final nameCtl = TextEditingController();
    String errorText = '';

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final l10n = AppLocalizations.of(ctx);
            return AlertDialog(
              title:
                  Text(l10n?.initialProfileTitle ?? 'Вход по номеру телефона'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: phoneCtl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: l10n?.phoneNumberLabel ?? 'Номер телефона',
                      hintText: '+7 999 111 22 33',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(labelText: l10n?.name ?? 'Имя'),
                  ),
                  if (errorText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      errorText,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
              actions: [
                FilledButton(
                  onPressed: () async {
                    try {
                      final deviceId = await ensureDeviceId(prefs);
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
                      onProfileChanged(session.displayName, session.phone);
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(session.profileKey);
                      }
                    } catch (error) {
                      setDialogState(() => errorText = error.toString());
                    }
                  },
                  child: Text(l10n?.continueAction ?? 'Продолжить'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
