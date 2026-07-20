import 'package:file_picker/file_picker.dart';
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
    final theme = Theme.of(context);

    return Container(
      color: theme.canvasColor,
      child: Column(
        children: [
          // 面板标题栏
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: theme.canvasColor,
              border: Border(
                bottom: BorderSide(color: theme.dividerColor, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_outlined,
                    size: 14, color: theme.colorScheme.secondary),
                const SizedBox(width: 6),
                Text(
                  '文件夹',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Tooltip(
                  message: '导入文件夹 (Ctrl+I)',
                  child: IconTheme(
                    data: IconTheme.of(context).copyWith(size: 16),
                    child: IconButton(
                      icon: const Icon(Icons.add),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          minWidth: 24, minHeight: 24),
                      onPressed: () => _showImportPicker(context, ref),
                    ),
                  ),
                ),
              ],
            ),
          ),
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

  void _showImportPicker(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择要导入的照片文件夹',
    );

    if (result != null) {
      await ref.read(importProvider.notifier).importFolder(result);
    }
  }
}

class _FolderList extends ConsumerWidget {
  final List<Folder> folders;

  const _FolderList({required this.folders});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (folders.isEmpty) {
      final theme = Theme.of(context);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.folder_open, size: 28,
                    color: theme.colorScheme.secondary),
              ),
              const SizedBox(height: 12),
              Text(
                '还没有导入文件夹',
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _showImportPicker(context, ref),
                icon: const Icon(Icons.folder_open, size: 16),
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
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择要导入的照片文件夹',
    );

    if (result != null) {
      await ref.read(importProvider.notifier).importFolder(result);
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
    final theme = Theme.of(context);

    return ListTile(
      dense: true,
      leading: Icon(
        isSelected ? Icons.folder_open : Icons.folder_outlined,
        size: 18,
        color: isSelected
            ? theme.colorScheme.primary
            : theme.colorScheme.secondary,
      ),
      title: Text(
        folder.name,
        style: TextStyle(
          fontSize: 13,
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.2)
              : theme.hoverColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${folder.photoCount}',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.secondary,
          ),
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