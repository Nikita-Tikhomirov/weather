import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/agent_policy.dart';
import '../../models/chat_models.dart';
import '../../models/task_project.dart';
import '../../models/workspace_item.dart';
import '../../services/api_client.dart';
import '../../services/codewhale_bridge_service.dart';

class AdminAccessPage extends StatefulWidget {
  const AdminAccessPage({
    super.key,
    required this.api,
    required this.actorProfile,
    required this.actorPhone,
    required this.accessPolicy,
    required this.contacts,
    required this.projects,
    this.initialWorkspaces = const [],
    this.connectToBridge = true,
    this.loadProjects,
    this.contactLabel,
  });

  final ApiClient api;
  final String actorProfile;
  final String actorPhone;
  final UserAccessPolicy accessPolicy;
  final List<ChatContact> contacts;
  final List<TaskProject> projects;
  final List<WorkspaceItem> initialWorkspaces;
  final bool connectToBridge;
  final Future<List<TaskProject>> Function()? loadProjects;
  final String Function(ChatContact contact)? contactLabel;

  @override
  State<AdminAccessPage> createState() => _AdminAccessPageState();
}

class _AdminAccessPageState extends State<AdminAccessPage> {
  final TextEditingController _searchCtl = TextEditingController();
  CodeWhaleBridgeService? _bridge;
  List<ChatContact> _contacts = const [];
  List<TaskProject> _projects = const [];
  List<WorkspaceItem> _workspaces = const [];
  List<WorkspaceAccessGrant> _grants = const [];
  String _selectedProfileKey = '';
  String _selectedTargetId = '';
  String _selectedRole = 'agent_operator';
  String _query = '';
  String _bridgeStatus = 'Воркспейсы CodeWhale не подключены';
  bool _bridgeConnected = false;
  bool _loading = false;
  bool _saving = false;

  static const List<_RoleOption> _roles = [
    _RoleOption(
      id: 'workspace_user',
      label: 'Участник воркспейса',
      description: 'Видит рабочее пространство и может пользоваться ИИ.',
    ),
    _RoleOption(
      id: 'agent_operator',
      label: 'Оператор агентов',
      description: 'Запускает агентские чаты из задач и ведет работу в них.',
    ),
    _RoleOption(
      id: 'workspace_admin',
      label: 'Администратор воркспейса',
      description: 'Управляет доступами и расширенными действиями агентов.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _contacts = _normalizedContacts();
    _projects = widget.projects;
    _workspaces = widget.initialWorkspaces;
    _selectedProfileKey = _contacts.isEmpty ? '' : _contacts.first.profileKey;
    _selectedTargetId = _targets.isEmpty ? '' : _targets.first.id;
    _searchCtl.addListener(() {
      setState(() => _query = _searchCtl.text.trim().toLowerCase());
    });
    unawaited(_loadGrants());
    unawaited(_refreshProjects());
    if (widget.connectToBridge) {
      _connectBridge();
    }
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _bridge?.dispose();
    super.dispose();
  }

  List<ChatContact> _normalizedContacts() {
    final seen = <String>{};
    final result = <ChatContact>[];
    for (final contact in widget.contacts) {
      if (contact.profileKey.trim().isEmpty) {
        continue;
      }
      if (seen.add(contact.profileKey)) {
        result.add(contact);
      }
    }
    if (widget.actorProfile.trim().isNotEmpty &&
        seen.add(widget.actorProfile)) {
      result.add(
        ChatContact(
          profileKey: widget.actorProfile,
          displayName: widget.accessPolicy.isSuperadmin ? 'Никита' : 'Я',
          phone: widget.actorPhone,
          conversationKey: '',
        ),
      );
    }
    return result;
  }

  List<_AccessTarget> get _targets {
    final seen = <String>{};
    final result = <_AccessTarget>[];
    for (final workspace in _workspaces) {
      final id = workspace.id.trim();
      if (id.isEmpty || !seen.add(id)) {
        continue;
      }
      result.add(
        _AccessTarget(
          id: id,
          name: workspace.name.trim().isEmpty ? id : workspace.name.trim(),
          kind: 'Воркспейс',
          subtitle: workspace.path,
        ),
      );
    }
    return result;
  }

  List<ChatContact> get _filteredContacts {
    if (_query.isEmpty) {
      return _contacts;
    }
    return _contacts.where((contact) {
      final text = [
        _contactTitle(contact),
        contact.profileKey,
        contact.phone,
      ].join(' ').toLowerCase();
      return text.contains(_query);
    }).toList();
  }

  Future<void> _refreshProjects() async {
    final loader = widget.loadProjects;
    if (loader == null) {
      return;
    }
    try {
      final projects = await loader();
      if (!mounted) {
        return;
      }
      setState(() {
        _projects = projects;
        _fixTargetSelection();
      });
    } catch (error) {
      _showError('Не удалось обновить проекты: $error');
    }
  }

  Future<void> _loadGrants() async {
    if (!widget.accessPolicy.canManageWorkspaceAccess || _loading) {
      return;
    }
    setState(() => _loading = true);
    try {
      final grants = await widget.api.listWorkspaceAccess(
        actorProfile: widget.actorProfile,
        actorPhone: widget.actorPhone,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _grants = grants;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
      }
      _showError('Не удалось загрузить доступы: $error');
    }
  }

  void _connectBridge() {
    final bridge = CodeWhaleBridgeService(
      onMessage: (message) {
        if (!mounted) {
          return;
        }
        if (message.type == 'workspace_list' || message.workspaces.isNotEmpty) {
          setState(() {
            _workspaces = message.workspaces;
            _fixTargetSelection();
          });
        }
      },
      onStatusChange: (connected, status) {
        if (!mounted) {
          return;
        }
        setState(() {
          _bridgeConnected = connected;
          _bridgeStatus = status;
        });
        if (connected) {
          _bridge?.requestWorkspaceList();
        }
      },
    );
    _bridge = bridge;
    unawaited(
      bridge.connect().then((_) {
        if (!mounted) {
          return;
        }
        bridge.requestWorkspaceList();
      }),
    );
  }

  Future<void> _grantAccess() async {
    final targetId = _effectiveTargetId;
    if (_selectedProfileKey.trim().isEmpty || targetId.trim().isEmpty) {
      _showError('Выберите пользователя и воркспейс');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.grantWorkspaceAccess(
        actorProfile: widget.actorProfile,
        actorPhone: widget.actorPhone,
        profileKey: _selectedProfileKey,
        workspaceId: targetId,
        role: _selectedRole,
      );
      await _reloadAfterMutation();
      _showInfo('Доступ выдан');
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
      }
      _showError('Не удалось выдать доступ: $error');
    }
  }

  Future<void> _revokeAccess(WorkspaceAccessGrant grant) async {
    setState(() => _saving = true);
    try {
      await widget.api.revokeWorkspaceAccess(
        actorProfile: widget.actorProfile,
        actorPhone: widget.actorPhone,
        profileKey: grant.profileKey,
        workspaceId: grant.workspaceId,
      );
      await _reloadAfterMutation();
      _showInfo('Доступ отозван');
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
      }
      _showError('Не удалось отозвать доступ: $error');
    }
  }

  Future<void> _reloadAfterMutation() async {
    final grants = await widget.api.listWorkspaceAccess(
      actorProfile: widget.actorProfile,
      actorPhone: widget.actorPhone,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _grants = grants;
      _saving = false;
      _loading = false;
    });
  }

  Future<void> _refreshAll() async {
    _bridge?.requestWorkspaceList();
    await _refreshProjects();
    await _loadGrants();
  }

  String get _effectiveTargetId {
    final targets = _targets;
    if (targets.any((target) => target.id == _selectedTargetId)) {
      return _selectedTargetId;
    }
    return targets.isEmpty ? '' : targets.first.id;
  }

  void _fixTargetSelection() {
    final targets = _targets;
    if (targets.isEmpty) {
      _selectedTargetId = '';
      return;
    }
    if (!targets.any((target) => target.id == _selectedTargetId)) {
      _selectedTargetId = targets.first.id;
    }
  }

  String _contactTitle(ChatContact contact) {
    final fromWidget = widget.contactLabel?.call(contact).trim() ?? '';
    if (fromWidget.isNotEmpty) {
      return fromWidget;
    }
    if (contact.displayName.trim().isNotEmpty) {
      return contact.displayName.trim();
    }
    if (contact.phone.trim().isNotEmpty) {
      return contact.phone.trim();
    }
    return contact.profileKey;
  }

  String _contactSubtitle(ChatContact contact) {
    final parts = <String>[
      if (contact.phone.trim().isNotEmpty) contact.phone.trim(),
      contact.profileKey,
    ];
    return parts.join(' · ');
  }

  String _targetLabel(String id) {
    return _targets
            .cast<_AccessTarget?>()
            .firstWhere((target) => target?.id == id, orElse: () => null)
            ?.name ??
        id;
  }

  String _roleLabel(String role) {
    return _roles
            .cast<_RoleOption?>()
            .firstWhere((item) => item?.id == role, orElse: () => null)
            ?.label ??
        role;
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showInfo(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.accessPolicy.canManageWorkspaceAccess) {
      return const Scaffold(
        body: Center(child: Text('Нет доступа к администрированию')),
      );
    }

    final targets = _targets;
    final targetId = _effectiveTargetId;
    final filteredContacts = _filteredContacts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Администрирование'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading || _saving ? null : _refreshAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            _buildStatusRow(targets.length),
            const SizedBox(height: 14),
            _buildGrantPanel(filteredContacts, targets, targetId),
            const SizedBox(height: 18),
            _buildGrantsPanel(),
            const SizedBox(height: 18),
            _buildAgentRulesPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(int targetCount) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _InfoChip(
          icon: Icons.contacts_outlined,
          text: 'Пользователи: ${_contacts.length}',
        ),
        _InfoChip(
          icon: Icons.workspaces_outline,
          text: 'Воркспейсы: $targetCount',
        ),
        _InfoChip(
          icon: Icons.folder_outlined,
          text: 'Проекты: ${_projects.length}',
        ),
        _InfoChip(
          icon: _bridgeConnected ? Icons.link : Icons.link_off,
          text: widget.connectToBridge ? _bridgeStatus : 'CodeWhale отключен',
        ),
      ],
    );
  }

  Widget _buildGrantPanel(
    List<ChatContact> contacts,
    List<_AccessTarget> targets,
    String targetId,
  ) {
    return _Panel(
      title: 'Новый доступ',
      icon: Icons.key_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchCtl,
            decoration: const InputDecoration(
              labelText: 'Пользователь из контактов',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          if (contacts.isEmpty)
            const _EmptyAdminLine(
              icon: Icons.person_off_outlined,
              text: 'Контакты не найдены',
            )
          else
            ...contacts.take(5).map(_buildContactRow),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: targetId.isEmpty ? null : targetId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Воркспейс',
              border: OutlineInputBorder(),
            ),
            items: targets
                .map(
                  (target) => DropdownMenuItem<String>(
                    value: target.id,
                    child: Text(target.name),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() => _selectedTargetId = value);
            },
          ),
          if (targetId.isNotEmpty) ...[
            const SizedBox(height: 8),
            _TargetHint(
              target: targets.firstWhere((item) => item.id == targetId),
            ),
          ],
          if (targets.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final target in targets)
                  InputChip(
                    avatar: const Icon(Icons.workspaces_outline, size: 16),
                    label: Text(target.name),
                    selected: target.id == targetId,
                    onPressed: () {
                      setState(() => _selectedTargetId = target.id);
                    },
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedRole,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Роль',
              border: OutlineInputBorder(),
            ),
            items: _roles
                .map(
                  (role) => DropdownMenuItem<String>(
                    value: role.id,
                    child: Text(role.label),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() => _selectedRole = value);
            },
          ),
          const SizedBox(height: 8),
          Text(
            _roles.firstWhere((role) => role.id == _selectedRole).description,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saving || contacts.isEmpty || targets.isEmpty
                  ? null
                  : _grantAccess,
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Выдать доступ'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactRow(ChatContact contact) {
    final selected = contact.profileKey == _selectedProfileKey;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      ),
      title: Text(_contactTitle(contact)),
      subtitle: Text(_contactSubtitle(contact)),
      trailing: selected ? const Icon(Icons.check_circle) : null,
      onTap: () => setState(() => _selectedProfileKey = contact.profileKey),
    );
  }

  Widget _buildGrantsPanel() {
    return _Panel(
      title: 'Кому что выдано',
      icon: Icons.assignment_ind_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading || _saving) const LinearProgressIndicator(),
          if (!_loading && _grants.isEmpty)
            const _EmptyAdminLine(
              icon: Icons.lock_outline,
              text: 'Активных доступов пока нет',
            )
          else
            ..._grants.map(
              (grant) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  grant.isActive
                      ? Icons.lock_open_outlined
                      : Icons.lock_outline,
                ),
                title: Text(
                  '${_contactNameByProfile(grant.profileKey)} · ${_targetLabel(grant.workspaceId)}',
                ),
                subtitle: Text(_roleLabel(grant.role)),
                trailing: IconButton(
                  tooltip: 'Отозвать доступ',
                  onPressed: grant.isActive && !_saving
                      ? () => _revokeAccess(grant)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAgentRulesPanel() {
    return const _Panel(
      title: 'Агенты и роли',
      icon: Icons.smart_toy_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RoleRuleLine(
            title: 'Участник воркспейса',
            text:
                'Может использовать ИИ только в доступном рабочем пространстве.',
          ),
          _RoleRuleLine(
            title: 'Оператор агентов',
            text:
                'Может подключать чат к задаче, создавать новый агентский чат и вести ход работы в комментариях.',
          ),
          _RoleRuleLine(
            title: 'Администратор воркспейса',
            text:
                'Может управлять доступами и расширенными действиями внутри рабочего пространства.',
          ),
        ],
      ),
    );
  }

  String _contactNameByProfile(String profileKey) {
    final contact = _contacts.cast<ChatContact?>().firstWhere(
          (contact) => contact?.profileKey == profileKey,
          orElse: () => null,
        );
    return contact == null ? profileKey : _contactTitle(contact);
  }
}

class _AccessTarget {
  const _AccessTarget({
    required this.id,
    required this.name,
    required this.kind,
    required this.subtitle,
  });

  final String id;
  final String name;
  final String kind;
  final String subtitle;
}

class _RoleOption {
  const _RoleOption({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(text),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _TargetHint extends StatelessWidget {
  const _TargetHint({required this.target});

  final _AccessTarget target;

  @override
  Widget build(BuildContext context) {
    final subtitle = target.subtitle.trim();
    return Row(
      children: [
        Icon(
          Icons.workspaces_outline,
          size: 18,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            subtitle.isEmpty ? target.kind : '${target.kind} · $subtitle',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
      ],
    );
  }
}

class _RoleRuleLine extends StatelessWidget {
  const _RoleRuleLine({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.rule_folder_outlined),
      title: Text(title),
      subtitle: Text(text),
    );
  }
}

class _EmptyAdminLine extends StatelessWidget {
  const _EmptyAdminLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}
