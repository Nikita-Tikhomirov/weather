import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';

class _WorkspaceFolderBrowserText {
  const _WorkspaceFolderBrowserText(this.l10n);

  final AppLocalizations? l10n;

  String get back => l10n?.back ?? 'Back';
  String get folderSelection => l10n?.folderSelection ?? 'Folder selection';
  String get refreshFolders => l10n?.refreshFolders ?? 'Refresh folders';
  String get currentFolder => l10n?.currentFolder ?? 'Current folder';
  String get loading => l10n?.loading ?? 'Loading...';
  String get copyPath => l10n?.copyPath ?? 'Copy path';
  String get parentFolder => l10n?.parentFolder ?? 'Parent folder';
  String get noFoldersHere => l10n?.noFoldersHere ?? 'No folders here';
  String get connectThisFolder =>
      l10n?.connectThisFolder ?? 'Connect this folder';
}

class WorkspaceFolderBrowserView extends StatelessWidget {
  const WorkspaceFolderBrowserView({
    super.key,
    required this.path,
    required this.parent,
    required this.folders,
    required this.onBack,
    required this.onRefresh,
    required this.onOpenFolder,
    required this.onSelectFolder,
  });

  final String path;
  final String parent;
  final List<Map<String, dynamic>> folders;
  final VoidCallback onBack;
  final VoidCallback onRefresh;
  final void Function(String path) onOpenFolder;
  final void Function(String name, String path) onSelectFolder;

  @override
  Widget build(BuildContext context) {
    final text = _WorkspaceFolderBrowserText(AppLocalizations.of(context));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: text.back,
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
        title: Text(text.folderSelection),
        actions: [
          IconButton(
            tooltip: text.refreshFolders,
            icon: const Icon(Icons.refresh),
            onPressed: onRefresh,
          ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.desktop_windows_outlined),
            title: Text(text.currentFolder),
            subtitle: SelectableText(path.isEmpty ? text.loading : path),
            trailing: path.isEmpty
                ? null
                : IconButton(
                    tooltip: text.copyPath,
                    icon: const Icon(Icons.copy),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: path)),
                  ),
          ),
          if (parent.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: Text(text.parentFolder),
              onTap: () => onOpenFolder(parent),
            ),
          const Divider(height: 1),
          Expanded(
            child: folders.isEmpty
                ? Center(child: Text(text.noFoldersHere))
                : ListView.separated(
                    itemCount: folders.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      final name = (folder['name'] ?? '').toString();
                      final folderPath = (folder['path'] ?? '').toString();
                      return ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(name),
                        subtitle: SelectableText(folderPath),
                        onTap: () => onOpenFolder(folderPath),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              tooltip: text.copyPath,
                              icon: const Icon(Icons.copy),
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: folderPath),
                              ),
                            ),
                            IconButton(
                              tooltip: text.connectThisFolder,
                              icon: const Icon(Icons.add_link),
                              onPressed: () => onSelectFolder(name, folderPath),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
