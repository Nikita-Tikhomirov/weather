import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.displayName,
    required this.phone,
    required this.profileKey,
    this.avatarUrl,
    required this.onAvatarChanged,
    required this.onDisplayNameChanged,
  });

  final String displayName;
  final String phone;
  final String profileKey;
  final String? avatarUrl;
  final void Function(String? avatarUrl) onAvatarChanged;
  final void Function(String name) onDisplayNameChanged;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final ImagePicker _picker = ImagePicker();
  late TextEditingController _nameCtl;

  @override
  void initState() {
    super.initState();
    _nameCtl = TextEditingController(text: widget.displayName);
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
    // Store locally as base64 in SharedPreferences for simplicity
    final bytes = await File(filePath).readAsBytes();
    final prefs = await SharedPreferences.getInstance();
    final key = 'avatar_${widget.profileKey}';
    await prefs.setString(key, filePath);

    widget.onAvatarChanged(filePath);
    if (!mounted) return;
    setState(() {});
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
                backgroundImage: widget.avatarUrl != null &&
                        widget.avatarUrl!.isNotEmpty
                    ? FileImage(File(widget.avatarUrl!))
                    : null,
                child: widget.avatarUrl == null || widget.avatarUrl!.isEmpty
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
          ],
        ),
      ),
    );
  }
}
