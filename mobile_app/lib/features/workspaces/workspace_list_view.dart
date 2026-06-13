import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/workspace_item.dart';

class _WorkspaceListText {
  const _WorkspaceListText(this.l10n);

  final AppLocalizations? l10n;

  String get workspaces => l10n?.workspaces ?? 'Workspaces';
  String get refresh => l10n?.refresh ?? 'Refresh';
  String get attachFolder => l10n?.attachFolder ?? 'Attach folder';
  String get createWorkspace => l10n?.createWorkspace ?? 'Create workspace';
  String get noWorkspacesYet => l10n?.noWorkspacesYet ?? 'No workspaces yet';
}

class WorkspaceListView extends StatelessWidget {
  const WorkspaceListView({
    super.key,
    required this.workspaces,
    required this.connected,
    required this.statusText,
    required this.onRefresh,
    required this.onCreateWorkspace,
    required this.onAttachWorkspace,
    required this.onOpenWorkspace,
  });

  final List<WorkspaceItem> workspaces;
  final bool connected;
  final String statusText;
  final VoidCallback onRefresh;
  final VoidCallback onCreateWorkspace;
  final VoidCallback onAttachWorkspace;
  final void Function(WorkspaceItem workspace) onOpenWorkspace;

  @override
  Widget build(BuildContext context) {
    final text = _WorkspaceListText(AppLocalizations.of(context));
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(text.workspaces),
        actions: [
          IconButton(
            tooltip: text.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: onRefresh,
          ),
          IconButton(
            tooltip: text.attachFolder,
            icon: const Icon(Icons.folder_open),
            onPressed: onAttachWorkspace,
          ),
          IconButton(
            tooltip: text.createWorkspace,
            icon: const Icon(Icons.add),
            onPressed: onCreateWorkspace,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: connected ? colors.primaryContainer : colors.errorContainer,
            child: Text(
              statusText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: connected
                    ? colors.onPrimaryContainer
                    : colors.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: workspaces.isEmpty
                ? Center(child: Text(text.noWorkspacesYet))
                : ListView.separated(
                    itemCount: workspaces.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = workspaces[index];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Icon(_statusIcon(item.status)),
                        ),
                        title: Text(item.name),
                        subtitle: Text(
                          item.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => onOpenWorkspace(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  IconData _statusIcon(WorkspaceStatus status) {
    switch (status) {
      case WorkspaceStatus.available:
        return Icons.folder_copy_outlined;
      case WorkspaceStatus.missing:
        return Icons.folder_off_outlined;
      case WorkspaceStatus.error:
        return Icons.error_outline;
      case WorkspaceStatus.unknown:
        return Icons.folder_outlined;
    }
  }
}
