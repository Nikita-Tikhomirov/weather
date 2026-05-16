import 'package:flutter/material.dart';

import '../../models/project_contact.dart';
import '../../models/project_file.dart';

class ProjectFileBrowser extends StatelessWidget {
  const ProjectFileBrowser({
    super.key,
    required this.project,
    required this.files,
    required this.currentPath,
    required this.onNavigate,
    required this.onRefresh,
    required this.onLinkToChat,
    required this.onOpenFile,
    this.onViewFile,
  });

  final ProjectContact project;
  final List<ProjectFileNode> files;
  final String currentPath;
  final void Function(String path) onNavigate;
  final VoidCallback onRefresh;
  final void Function(String filePath) onLinkToChat;
  final void Function(String dirPath) onOpenFile;
  final void Function(String path)? onViewFile;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Файлы — ${project.name}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (currentPath.isNotEmpty)
                          Text(
                            currentPath,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withValues(alpha: 0.6),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (currentPath.isNotEmpty)
                    IconButton(
                      tooltip: 'Наверх',
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: () {
                        final parent = _parentPath(currentPath);
                        if (parent == null) {
                          onNavigate('');
                          onRefresh();
                        } else {
                          onOpenFile(parent);
                        }
                      },
                    ),
                  IconButton(
                    tooltip: 'Обновить',
                    icon: const Icon(Icons.refresh),
                    onPressed: onRefresh,
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (files.isEmpty)
              const Expanded(
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        SizedBox(height: 16),
                        Text('Загрузка файлов...'),
                      ],
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.only(top: 4),
                  itemCount: files.length,
                  itemBuilder: (context, index) {
                    final node = files[index];
                    return _FileNodeTile(
                      node: node,
                      onTap: () {
                        if (node.isDir) {
                          onOpenFile(node.path);
                        } else {
                          _showFileDetail(context, node, onLinkToChat,
                              onViewFile: onViewFile);
                        }
                      },
                      onLink: () => onLinkToChat(node.path),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  static void _showFileDetail(
    BuildContext context,
    ProjectFileNode node,
    void Function(String) onLinkToChat, {
    void Function(String)? onViewFile,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.insert_drive_file_outlined,
                        size: 40, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(node.name,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(node.sizeLabel,
                              style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.6))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(node.path,
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.5))),
                const SizedBox(height: 20),
                if (onViewFile != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        onViewFile(node.path);
                      },
                      icon: const Icon(Icons.visibility),
                      label: const Text('Просмотр'),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      onLinkToChat(node.path);
                    },
                    icon: const Icon(Icons.attachment),
                    label: const Text('Ссылка в чат'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Return the parent directory path, or null if already at root.
  static String? _parentPath(String path) {
    final trimmed = path.endsWith('/') || path.endsWith('\\')
        ? path.substring(0, path.length - 1)
        : path;
    final lastSep = _lastSeparator(trimmed);
    if (lastSep < 0) return null;
    return trimmed.substring(0, lastSep);
  }

  static int _lastSeparator(String path) {
    final slash = path.lastIndexOf('/');
    final backslash = path.lastIndexOf('\\');
    return slash > backslash ? slash : backslash;
  }
}

class _FileNodeTile extends StatelessWidget {
  const _FileNodeTile({
    required this.node,
    required this.onTap,
    required this.onLink,
  });

  final ProjectFileNode node;
  final VoidCallback onTap;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        node.isDir ? Icons.folder : Icons.insert_drive_file_outlined,
        color: node.isDir ? Colors.amber.shade700 : cs.primary,
      ),
      title: Text(
        node.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: node.isDir
          ? null
          : Text(
              node.sizeLabel,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Ссылка в чат',
            icon: const Icon(Icons.attachment, size: 20),
            onPressed: onLink,
          ),
          if (node.isDir) const Icon(Icons.chevron_right, size: 20),
        ],
      ),
      onTap: onTap,
    );
  }
}
