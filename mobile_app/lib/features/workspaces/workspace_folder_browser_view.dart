import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Назад',
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
        title: const Text('Выбор папки'),
        actions: [
          IconButton(
            tooltip: 'Обновить папки',
            icon: const Icon(Icons.refresh),
            onPressed: onRefresh,
          ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.desktop_windows_outlined),
            title: const Text('Текущая папка'),
            subtitle: SelectableText(path.isEmpty ? 'Загрузка...' : path),
            trailing: path.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Копировать путь',
                    icon: const Icon(Icons.copy),
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: path)),
                  ),
          ),
          if (parent.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.arrow_upward),
              title: const Text('На уровень выше'),
              onTap: () => onOpenFolder(parent),
            ),
          const Divider(height: 1),
          Expanded(
            child: folders.isEmpty
                ? const Center(child: Text('Папок здесь нет'))
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
                              tooltip: 'Копировать путь',
                              icon: const Icon(Icons.copy),
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: folderPath),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Подключить эту папку',
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
