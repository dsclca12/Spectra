import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../providers/catalog_provider.dart';
import '../../../providers/import_provider.dart';

/// 左栏：文件夹树面板
class FolderPanel extends ConsumerWidget {
  const FolderPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(folderListProvider);

    return Container(
      color: Theme.of(context).canvasColor,
      child: Column(
        children: [
          // 面板标题
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            child: Text(
              '文件夹',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          // 文件夹列表
          Expanded(
            child: foldersAsync.when(
              data: (folders) => _FolderList(folders: folders),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderList extends ConsumerWidget {
  final List<Folder> folders;

  const _FolderList({required this.folders});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (folders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_open, size: 48,
                  color: Theme.of(context).colorScheme.secondary),
              const SizedBox(height: 8),
              Text(
                '还没有导入文件夹',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _showImportPicker(context, ref),
                icon: const Icon(Icons.folder, size: 16),
                label: const Text('导入文件夹'),
              ),
            ],
          ),
        ),
      );
    }

    // Material 为 ListTile 提供 ink splash 容器
    return Material(
      color: Theme.of(context).canvasColor,
      child: ListView.builder(
        itemCount: folders.length,
        itemBuilder: (context, index) {
          final folder = folders[index];
          return _FolderTile(folder: folder);
        },
      ),
    );
  }

  void _showImportPicker(BuildContext context, WidgetRef ref) async {
    final dialog = DirectoryPicker()
      ..title = '选择要导入的照片文件夹';

    final result = dialog.getDirectory();
    if (result != null) {
      await ref.read(importProvider.notifier).importFolder(result.path);
    }
  }
}

class _FolderTile extends ConsumerWidget {
  final Folder folder;

  const _FolderTile({required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentFolderId = ref.watch(currentFolderProvider);
    final isSelected = currentFolderId == folder.id;

    return ListTile(
      dense: true,
      leading: Icon(
        isSelected ? Icons.folder_open : Icons.folder,
        size: 18,
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.secondary,
      ),
      title: Text(
        folder.name,
        style: TextStyle(
          fontSize: 13,
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${folder.photoCount} 张',
        style: TextStyle(
          fontSize: 11,
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
      selected: isSelected,
      onTap: () {
        // 点击文件夹 → 设置筛选条件，catalogProvider 自动刷新
        // 再次点击已选中文件夹 → 取消筛选
        final current = ref.read(currentFolderProvider);
        if (current == folder.id) {
          ref.read(currentFolderProvider.notifier).state = null;
        } else {
          ref.read(currentFolderProvider.notifier).state = folder.id;
        }
      },
    );
  }
}