import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/agent_policy.dart';
import '../../models/chat_models.dart';
import '../../models/task_project.dart';
import '../../models/workspace_item.dart';
import '../../services/api_client.dart';
import '../../services/codewhale_bridge_service.dart';

class _AdminAccessText {
  const _AdminAccessText(this.l10n);

  final AppLocalizations? l10n;

  String get administration => l10n?.administration ?? 'Administration';
  String get refresh => l10n?.refresh ?? 'Refresh';
  String get noAccess => l10n?.adminNoAccess ?? 'No administration access';
  String get bridgeNotConnected =>
      l10n?.adminBridgeNotConnected ?? 'CodeWhale workspaces are not connected';
  String get codeWhaleDisabled =>
      l10n?.adminCodeWhaleDisabled ?? 'CodeWhale disabled';
  String get newAccess => l10n?.adminNewAccess ?? 'New access';
  String get contactFromContacts =>
      l10n?.adminContactFromContacts ?? 'Contact from contacts';
  String get contactsNotFound =>
      l10n?.adminContactsNotFound ?? 'No contacts found';
  String get workspace => l10n?.adminWorkspace ?? 'Workspace';
  String get role => l10n?.adminRole ?? 'Role';
  String get grantAccess => l10n?.adminGrantAccess ?? 'Grant access';
  String get grantedAccess => l10n?.adminGrantedAccess ?? 'Granted access';
  String get noActiveAccess =>
      l10n?.adminNoActiveAccess ?? 'No active access yet';
  String get revokeAccess => l10n?.adminRevokeAccess ?? 'Revoke access';
  String get agentRoles => l10n?.adminAgentRoles ?? 'Agent roles';
  String get workspaceKind => l10n?.adminWorkspaceKind ?? 'Workspace';
  String get selectUserAndWorkspace =>
      l10n?.adminSelectUserAndWorkspace ?? 'Select a user and workspace';
  String get accessGranted => l10n?.adminAccessGranted ?? 'Access granted';
  String get accessRevoked => l10n?.adminAccessRevoked ?? 'Access revoked';

  String refreshProjectsFailed(Object error) {
    return l10n?.adminRefreshProjectsFailed(error) ??
        'Could not refresh projects: $error';
  }

  String loadAccessFailed(Object error) {
    return l10n?.adminLoadAccessFailed(error) ??
        'Could not load access grants: $error';
  }

  String grantAccessFailed(Object error) {
    return l10n?.adminGrantAccessFailed(error) ??
        'Could not grant access: $error';
  }

  String revokeAccessFailed(Object error) {
    return l10n?.adminRevokeAccessFailed(error) ??
        'Could not revoke access: $error';
  }

  String usersCount(int count) {
    return l10n?.adminUsersCount(count) ?? 'Users: $count';
  }

  String workspacesCount(int count) {
    return l10n?.adminWorkspacesCount(count) ?? 'Workspaces: $count';
  }

  String projectsCount(int count) {
    return l10n?.adminProjectsCount(count) ?? 'Projects: $count';
  }

  String roleLabel(String id) {
    switch (id) {
      case 'workspace_user':
        return l10n?.adminRoleWorkspaceUser ?? 'Workspace member';
      case 'agent_operator':
        return l10n?.adminRoleAgentOperator ?? 'Agent operator';
      case 'workspace_admin':
        return l10n?.adminRoleWorkspaceAdmin ?? 'Workspace administrator';
      default:
        return id;
    }
  }

  String roleDescription(String id) {
    switch (id) {
      case 'workspace_user':
        return l10n?.adminRoleWorkspaceUserDescription ??
            'Can view the workspace and use AI.';
      case 'agent_operator':
        return l10n?.adminRoleAgentOperatorDescription ??
            'Can launch agent chats from tasks and run work in them.';
      case 'workspace_admin':
        return l10n?.adminRoleWorkspaceAdminDescription ??
            'Can manage access and advanced agent actions.';
      default:
        return id;
    }
  }
}

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
  String _bridgeStatus = '';
  bool _bridgeConnected = false;
  bool _loading = false;
  bool _saving = false;

  _AdminAccessText get _text => _AdminAccessText(AppLocalizations.of(context));

  static const List<_RoleOption> _roles = [
    _RoleOption(
      id: 'workspace_user',
    ),
    _RoleOption(
      id: 'agent_operator',
    ),
    _RoleOption(
      id: 'workspace_admin',
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
      if (mounted) {
        _showError(_text.refreshProjectsFailed(error));
      }
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
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      _showError(_text.loadAccessFailed(error));
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
      _showError(_text.selectUserAndWorkspace);
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
      _showInfo(_text.accessGranted);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(_text.grantAccessFailed(error));
      }
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
      _showInfo(_text.accessRevoked);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(_text.revokeAccessFailed(error));
      }
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
    return _text.roleLabel(role);
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
    final text = _AdminAccessText(AppLocalizations.of(context));
    if (!widget.accessPolicy.canManageWorkspaceAccess) {
      return Scaffold(
        body: Center(child: Text(text.noAccess)),
      );
    }

    final targets = _targets;
    final targetId = _effectiveTargetId;
    final filteredContacts = _filteredContacts;

    return Scaffold(
      appBar: AppBar(
        title: Text(text.administration),
        actions: [
          IconButton(
            tooltip: text.refresh,
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
    final text = _AdminAccessText(AppLocalizations.of(context));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _InfoChip(
          icon: Icons.contacts_outlined,
          text: text.usersCount(_contacts.length),
        ),
        _InfoChip(
          icon: Icons.workspaces_outline,
          text: text.workspacesCount(targetCount),
        ),
        _InfoChip(
          icon: Icons.folder_outlined,
          text: text.projectsCount(_projects.length),
        ),
        _InfoChip(
          icon: _bridgeConnected ? Icons.link : Icons.link_off,
          text: widget.connectToBridge
              ? (_bridgeStatus.isEmpty
                  ? text.bridgeNotConnected
                  : _bridgeStatus)
              : text.codeWhaleDisabled,
        ),
      ],
    );
  }

  Widget _buildGrantPanel(
    List<ChatContact> contacts,
    List<_AccessTarget> targets,
    String targetId,
  ) {
    final text = _AdminAccessText(AppLocalizations.of(context));
    return _Panel(
      title: text.newAccess,
      icon: Icons.key_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchCtl,
            decoration: InputDecoration(
              labelText: text.contactFromContacts,
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          if (contacts.isEmpty)
            _EmptyAdminLine(
              icon: Icons.person_off_outlined,
              text: text.contactsNotFound,
            )
          else
            ...contacts.take(5).map(_buildContactRow),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: targetId.isEmpty ? null : targetId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: text.workspace,
              border: const OutlineInputBorder(),
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
              kind: text.workspaceKind,
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
            decoration: InputDecoration(
              labelText: text.role,
              border: const OutlineInputBorder(),
            ),
            items: _roles
                .map(
                  (role) => DropdownMenuItem<String>(
                    value: role.id,
                    child: Text(text.roleLabel(role.id)),
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
            text.roleDescription(_selectedRole),
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
              label: Text(text.grantAccess),
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
    final text = _AdminAccessText(AppLocalizations.of(context));
    return _Panel(
      title: text.grantedAccess,
      icon: Icons.assignment_ind_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading || _saving) const LinearProgressIndicator(),
          if (!_loading && _grants.isEmpty)
            _EmptyAdminLine(
              icon: Icons.lock_outline,
              text: text.noActiveAccess,
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
                  tooltip: text.revokeAccess,
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
    final text = _AdminAccessText(AppLocalizations.of(context));
    return _Panel(
      title: text.agentRoles,
      icon: Icons.smart_toy_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RoleRuleLine(
            title: text.roleLabel('workspace_user'),
            text: text.roleDescription('workspace_user'),
          ),
          _RoleRuleLine(
            title: text.roleLabel('agent_operator'),
            text: text.roleDescription('agent_operator'),
          ),
          _RoleRuleLine(
            title: text.roleLabel('workspace_admin'),
            text: text.roleDescription('workspace_admin'),
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
    required this.subtitle,
  });

  final String id;
  final String name;
  final String subtitle;
}

class _RoleOption {
  const _RoleOption({
    required this.id,
  });

  final String id;
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
  const _TargetHint({required this.target, required this.kind});

  final _AccessTarget target;
  final String kind;

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
            subtitle.isEmpty ? kind : '$kind · $subtitle',
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
