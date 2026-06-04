import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/agent_policy.dart';
import '../../services/api_client.dart';
import '../../shared/utils/avatar_url_resolver.dart';

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
  });

  final ApiClient api;
  final String displayName;
  final String phone;
  final String profileKey;
  final UserAccessPolicy accessPolicy;
  final String? avatarUrl;
  final void Function(String? avatarUrl) onAvatarChanged;
  final void Function(String name) onDisplayNameChanged;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ImagePicker _picker = ImagePicker();
  late TextEditingController _nameCtl;
  late TextEditingController _workspaceCtl;
  late TextEditingController _profileCtl;
  String? _avatarUrl;
  String _grantRole = 'workspace_user';
  bool _workspaceAccessLoading = false;
  List<WorkspaceAccessGrant> _workspaceGrants = const [];

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController(text: widget.displayName);
    _workspaceCtl = TextEditingController();
    _profileCtl = TextEditingController();
    _avatarUrl = widget.avatarUrl;
    if (widget.accessPolicy.canManageWorkspaceAccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadWorkspaceAccess();
      });
    }
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _workspaceCtl.dispose();
    _profileCtl.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить аватарку: $error')),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Имя сохранено')),
    );
  }

  Future<void> _loadWorkspaceAccess() async {
    if (!widget.accessPolicy.canManageWorkspaceAccess || _workspaceAccessLoading) {
      return;
    }
    setState(() => _workspaceAccessLoading = true);
    try {
      final grants = await widget.api.listWorkspaceAccess(
        actorProfile: widget.profileKey,
      );
      if (!mounted) return;
      setState(() {
        _workspaceGrants = grants;
        _workspaceAccessLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _workspaceAccessLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить доступы: $error')),
      );
    }
  }

  Future<void> _grantWorkspaceAccess() async {
    final profile = _profileCtl.text.trim();
    final workspace = _workspaceCtl.text.trim();
    if (profile.isEmpty || workspace.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните профиль и воркспейс')),
      );
      return;
    }
    setState(() => _workspaceAccessLoading = true);
    try {
      await widget.api.grantWorkspaceAccess(
        actorProfile: widget.profileKey,
        profileKey: profile,
        workspaceId: workspace,
        role: _grantRole,
      );
      await _loadWorkspaceAccessAfterMutation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Доступ выдан')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _workspaceAccessLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось выдать доступ: $error')),
      );
    }
  }

  Future<void> _revokeWorkspaceAccess(WorkspaceAccessGrant grant) async {
    setState(() => _workspaceAccessLoading = true);
    try {
      await widget.api.revokeWorkspaceAccess(
        actorProfile: widget.profileKey,
        profileKey: grant.profileKey,
        workspaceId: grant.workspaceId,
      );
      await _loadWorkspaceAccessAfterMutation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Доступ отозван')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _workspaceAccessLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отозвать доступ: $error')),
      );
    }
  }

  Future<void> _loadWorkspaceAccessAfterMutation() async {
    try {
      final grants = await widget.api.listWorkspaceAccess(
        actorProfile: widget.profileKey,
      );
      if (!mounted) return;
      setState(() {
        _workspaceGrants = grants;
        _workspaceAccessLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _workspaceAccessLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
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
              child: const Text('Изменить фото'),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameCtl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Имя',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saveName,
                child: const Text('Сохранить имя'),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.phone),
              title: const Text('Телефон'),
              subtitle: Text(widget.phone),
            ),
            ListTile(
              leading: const Icon(Icons.badge),
              title: const Text('Профиль'),
              subtitle: Text(widget.profileKey),
            ),
            if (widget.accessPolicy.canManageWorkspaceAccess) ...[
              const SizedBox(height: 24),
              _buildWorkspaceAccessPanel(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceAccessPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.admin_panel_settings_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Доступы к воркспейсам',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Обновить',
              onPressed: _workspaceAccessLoading ? null : _loadWorkspaceAccess,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _workspaceCtl,
          decoration: const InputDecoration(
            labelText: 'Воркспейс',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _profileCtl,
          decoration: const InputDecoration(
            labelText: 'Профиль пользователя',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _grantRole,
          decoration: const InputDecoration(
            labelText: 'Роль',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(
              value: 'workspace_user',
              child: Text('Пользователь воркспейса'),
            ),
            DropdownMenuItem(
              value: 'agent_operator',
              child: Text('Оператор агентов'),
            ),
            DropdownMenuItem(
              value: 'workspace_admin',
              child: Text('Администратор воркспейса'),
            ),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() => _grantRole = value);
          },
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: _workspaceAccessLoading ? null : _grantWorkspaceAccess,
            icon: const Icon(Icons.key_outlined),
            label: const Text('Выдать доступ'),
          ),
        ),
        const SizedBox(height: 16),
        if (_workspaceAccessLoading)
          const LinearProgressIndicator()
        else if (_workspaceGrants.isEmpty)
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Активных записей доступа пока нет'),
          )
        else
          ..._workspaceGrants.map(
            (grant) => ListTile(
              leading: Icon(
                grant.isActive ? Icons.lock_open_outlined : Icons.lock_outline,
              ),
              title: Text('${grant.workspaceId} · ${grant.profileKey}'),
              subtitle: Text(_roleLabel(grant.role)),
              trailing: IconButton(
                tooltip: 'Отозвать доступ',
                onPressed: grant.isActive
                    ? () => _revokeWorkspaceAccess(grant)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ),
          ),
      ],
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'agent_operator':
        return 'Оператор агентов';
      case 'workspace_admin':
        return 'Администратор воркспейса';
      case 'workspace_user':
        return 'Пользователь воркспейса';
      default:
        return role;
    }
  }

  ImageProvider? _avatarImageProvider(String? url) {
    return AvatarUrlResolver.imageProvider(url);
  }
}
