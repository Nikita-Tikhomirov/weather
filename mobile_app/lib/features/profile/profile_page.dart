import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../models/agent_policy.dart';
import '../../services/api_client.dart';
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
  final VoidCallback? onOpenAdmin;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ImagePicker _picker = ImagePicker();
  late TextEditingController _nameCtl;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController(text: widget.displayName);
    _avatarUrl = widget.avatarUrl;
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
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
}
