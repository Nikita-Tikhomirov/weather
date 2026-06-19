import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../models/agent_policy.dart';
import '../../services/api_client.dart';
import '../../services/telecom_call_integration.dart';
import '../../shared/utils/avatar_url_resolver.dart';

class _ProfileText {
  const _ProfileText(this.l10n);

  final AppLocalizations? l10n;

  String get profile => l10n?.profile ?? 'Profile';
  String get changePhoto => l10n?.changePhoto ?? 'Change photo';
  String get name => l10n?.name ?? 'Name';
  String get saveName => l10n?.saveName ?? 'Save name';
  String get phone => l10n?.phone ?? 'Phone';
  String get administration => l10n?.administration ?? 'Administration';
  String get adminSubtitle =>
      l10n?.profileAdminSubtitle ??
      'Users, projects, workspaces, and agent roles';
  String get nameSaved => l10n?.nameSaved ?? 'Name saved';
  String get systemCalls => l10n?.profileSystemCalls ?? 'System calls';
  String get systemCallsEnabled =>
      l10n?.profileSystemCallsEnabled ??
      'Incoming calls can use the Android call screen';
  String get systemCallsDisabled =>
      l10n?.profileSystemCallsDisabled ??
      'Enable to show incoming calls on lock screen';
  String get systemCallsFullScreenDisabled =>
      l10n?.profileSystemCallsFullScreenDisabled ??
      'Allow full-screen alerts for lock-screen calls';
  String get systemCallsNotificationsDisabled =>
      l10n?.profileSystemCallsNotificationsDisabled ??
      'Allow notifications for lock-screen calls';
  String get systemCallsChannelDisabled =>
      l10n?.profileSystemCallsChannelDisabled ??
      'Allow the call notification channel for lock-screen calls';
  String get enableSystemCalls => l10n?.profileEnableSystemCalls ?? 'Enable';
  String get allowSystemCallsFullScreen =>
      l10n?.profileAllowSystemCallsFullScreen ?? 'Allow';
  String get allowSystemCallsNotifications =>
      l10n?.profileAllowSystemCallsNotifications ?? 'Allow notifications';
  String get allowSystemCallsChannel =>
      l10n?.profileAllowSystemCallsChannel ?? 'Call channel';
  String get systemCallsSettingsFailed =>
      l10n?.profileSystemCallsSettingsFailed ??
      'Could not open system call settings';

  String avatarUploadFailed(Object error) {
    return l10n?.avatarUploadFailed(error.toString()) ??
        'Could not upload avatar: $error';
  }
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.api,
    required this.displayName,
    required this.phone,
    required this.profileKey,
    required this.accessPolicy,
    this.avatarUrl,
    required this.onAvatarChanged,
    required this.onDisplayNameChanged,
    this.callIntegration = const TelecomCallIntegration(),
    this.onOpenAdmin,
  });

  final ApiClient api;
  final String displayName;
  final String phone;
  final String profileKey;
  final UserAccessPolicy accessPolicy;
  final String? avatarUrl;
  final void Function(String? avatarUrl) onAvatarChanged;
  final void Function(String name) onDisplayNameChanged;
  final TelecomCallIntegration callIntegration;
  final VoidCallback? onOpenAdmin;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  late TextEditingController _nameCtl;
  String? _avatarUrl;
  bool? _systemCallAccountEnabled;
  bool? _fullScreenIntentEnabled;
  bool? _notificationsEnabled;
  bool? _callNotificationChannelEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nameCtl = TextEditingController(text: widget.displayName);
    _avatarUrl = widget.avatarUrl;
    unawaited(_refreshSystemCallStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameCtl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshSystemCallStatus());
    }
  }

  Future<void> _refreshSystemCallStatus() async {
    await widget.callIntegration.registerPhoneAccounts();
    final phoneAccountEnabled =
        await widget.callIntegration.isManagedPhoneAccountEnabled();
    final fullScreenEnabled =
        await widget.callIntegration.canUseFullScreenIntent();
    final notificationsEnabled =
        await widget.callIntegration.canPostNotifications();
    final callChannelEnabled =
        await widget.callIntegration.canUseCallNotificationChannel();
    if (!mounted) return;
    setState(() {
      _systemCallAccountEnabled = phoneAccountEnabled;
      _fullScreenIntentEnabled = fullScreenEnabled;
      _notificationsEnabled = notificationsEnabled;
      _callNotificationChannelEnabled = callChannelEnabled;
    });
  }

  Future<void> _openPhoneAccountSettings() async {
    await widget.callIntegration.registerPhoneAccounts();
    final opened = await widget.callIntegration.openPhoneAccountSettings();
    if (!mounted) return;
    if (!opened) {
      final text = _ProfileText(AppLocalizations.of(context));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text.systemCallsSettingsFailed)),
      );
      return;
    }
    unawaited(_refreshSystemCallStatus());
  }

  Future<void> _openFullScreenIntentSettings() async {
    final opened = await widget.callIntegration.openFullScreenIntentSettings();
    if (!mounted) return;
    if (!opened) {
      final text = _ProfileText(AppLocalizations.of(context));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text.systemCallsSettingsFailed)),
      );
      return;
    }
    unawaited(_refreshSystemCallStatus());
  }

  Future<void> _openNotificationSettings() async {
    final opened = await widget.callIntegration.openNotificationSettings();
    if (!mounted) return;
    if (!opened) {
      final text = _ProfileText(AppLocalizations.of(context));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text.systemCallsSettingsFailed)),
      );
      return;
    }
    unawaited(_refreshSystemCallStatus());
  }

  Future<void> _openCallNotificationChannelSettings() async {
    final opened =
        await widget.callIntegration.openCallNotificationChannelSettings();
    if (!mounted) return;
    if (!opened) {
      final text = _ProfileText(AppLocalizations.of(context));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text.systemCallsSettingsFailed)),
      );
      return;
    }
    unawaited(_refreshSystemCallStatus());
  }

  Future<void> _pickAvatar() async {
    final xfile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (xfile == null) return;

    final filePath = xfile.path;
    final prefs = await SharedPreferences.getInstance();
    final key = 'avatar_${widget.profileKey}';
    await prefs.setString(key, filePath);

    widget.onAvatarChanged(filePath);
    if (!mounted) return;
    setState(() => _avatarUrl = filePath);

    try {
      final uploadedUrl = await widget.api.uploadProfileAvatar(
        actorProfile: widget.profileKey,
        bytes: await File(filePath).readAsBytes(),
        filename: xfile.name.isNotEmpty ? xfile.name : 'avatar.jpg',
      );
      if (uploadedUrl.isEmpty) return;
      await prefs.setString(key, uploadedUrl);
      widget.onAvatarChanged(uploadedUrl);
      if (!mounted) return;
      setState(() => _avatarUrl = uploadedUrl);
    } catch (error) {
      if (!mounted) return;
      final text = _ProfileText(AppLocalizations.of(context));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text.avatarUploadFailed(error))),
      );
    }
  }

  Future<void> _saveName() async {
    final name = _nameCtl.text.trim();
    if (name.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_display_name', name);
    widget.onDisplayNameChanged(name);
    if (!mounted) return;
    final text = _ProfileText(AppLocalizations.of(context));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text.nameSaved)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = _ProfileText(AppLocalizations.of(context));
    return Scaffold(
      appBar: AppBar(title: Text(text.profile)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _pickAvatar,
              child: CircleAvatar(
                radius: 60,
                backgroundImage: _avatarImageProvider(_avatarUrl),
                child: _avatarUrl == null || _avatarUrl!.isEmpty
                    ? const Icon(Icons.person, size: 60)
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _pickAvatar,
              child: Text(text.changePhoto),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameCtl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: text.name,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saveName,
                child: Text(text.saveName),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.phone),
              title: Text(text.phone),
              subtitle: Text(widget.phone),
            ),
            ListTile(
              leading: Icon(
                _systemCallsReady
                    ? Icons.phone_in_talk_outlined
                    : Icons.phone_callback_outlined,
              ),
              title: Text(text.systemCalls),
              subtitle: Text(_systemCallsSubtitle(text)),
              trailing: _systemCallsLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _systemCallsReady
                      ? Icon(
                          Icons.check_circle_outline,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : _systemCallsAction(text),
            ),
            ListTile(
              leading: const Icon(Icons.badge),
              title: Text(text.profile),
              subtitle: Text(widget.profileKey),
            ),
            if (widget.accessPolicy.canManageWorkspaceAccess &&
                widget.onOpenAdmin != null) ...[
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: Text(text.administration),
                subtitle: Text(text.adminSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.onOpenAdmin,
              ),
            ],
          ],
        ),
      ),
    );
  }

  ImageProvider? _avatarImageProvider(String? url) {
    return AvatarUrlResolver.imageProvider(url);
  }

  bool get _systemCallsLoading =>
      _systemCallAccountEnabled == null ||
      _fullScreenIntentEnabled == null ||
      _notificationsEnabled == null ||
      _callNotificationChannelEnabled == null;

  bool get _systemCallsReady =>
      _systemCallAccountEnabled == true &&
      _fullScreenIntentEnabled == true &&
      _notificationsEnabled == true &&
      _callNotificationChannelEnabled == true;

  String _systemCallsSubtitle(_ProfileText text) {
    if (_systemCallAccountEnabled == true && _notificationsEnabled == false) {
      return text.systemCallsNotificationsDisabled;
    }
    if (_systemCallAccountEnabled == true &&
        _callNotificationChannelEnabled == false) {
      return text.systemCallsChannelDisabled;
    }
    if (_systemCallAccountEnabled == true &&
        _fullScreenIntentEnabled == false) {
      return text.systemCallsFullScreenDisabled;
    }
    return _systemCallsReady
        ? text.systemCallsEnabled
        : text.systemCallsDisabled;
  }

  Widget _systemCallsAction(_ProfileText text) {
    if (_systemCallAccountEnabled == true && _notificationsEnabled == false) {
      return TextButton(
        onPressed: _openNotificationSettings,
        child: Text(text.allowSystemCallsNotifications),
      );
    }
    if (_systemCallAccountEnabled == true &&
        _callNotificationChannelEnabled == false) {
      return TextButton(
        onPressed: _openCallNotificationChannelSettings,
        child: Text(text.allowSystemCallsChannel),
      );
    }
    if (_systemCallAccountEnabled == true &&
        _fullScreenIntentEnabled == false) {
      return TextButton(
        onPressed: _openFullScreenIntentSettings,
        child: Text(text.allowSystemCallsFullScreen),
      );
    }
    return TextButton(
      onPressed: _openPhoneAccountSettings,
      child: Text(text.enableSystemCalls),
    );
  }
}
