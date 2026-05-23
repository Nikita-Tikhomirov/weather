part of 'home_page.dart';

// ───────────────────────────────────────────────────────────────
// Profile / device initialization extracted from _HomePageState.
// ───────────────────────────────────────────────────────────────

extension _ProfileInitExtension on _HomePageState {
  Future<String> _ensureDeviceId(SharedPreferences prefs) async {
    final saved = prefs.getString('device_id')?.trim() ?? '';
    if (saved.isNotEmpty) {
      return saved;
    }
    final random = Random.secure().nextInt(1 << 32).toRadixString(16);
    final value = 'dev-${DateTime.now().microsecondsSinceEpoch}-$random';
    await prefs.setString('device_id', value);
    return value;
  }

  Future<String> _restoreProfileByPhone(
    ApiClient api,
    SharedPreferences prefs,
    String phone,
  ) async {
    final deviceId = await _ensureDeviceId(prefs);
    final session = await api.deviceStart(
      phone: phone,
      deviceId: deviceId,
      displayName: _currentProfileDisplayName,
    );
    await prefs.setString('actor_profile', session.profileKey);
    await prefs.setString('profile_phone', session.phone);
    await prefs.setString('profile_display_name', session.displayName);
    _currentProfileDisplayName = session.displayName;
    _currentProfilePhone = session.phone;
    return session.profileKey;
  }

  Future<String?> _promptForInitialProfile(ApiClient api) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return null;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) {
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
          builder: (context, setDialogState) {
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
                      final deviceId = await _ensureDeviceId(prefs);
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
                      if (mounted) {
                        _setProfileInfo(session.displayName, session.phone);
                      }
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
