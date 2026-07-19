import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/import_provider.dart';

/// 导入对话框 — 选择文件夹并显示导入进度
class ImportDialog extends ConsumerWidget {
  const ImportDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final importState = ref.watch(importProvider);

    return AlertDialog(
      title: const Text('导入文件夹'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (importState.status == ImportStatus.idle) ...[
              const Text('选择要导入的照片文件夹'),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _pickFolder(context, ref),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('选择文件夹'),
                  ),
                ],
              ),
            ] else if (importState.isActive) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text('已导入: ${importState.imported} 张'),
              if (importState.currentFile != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    importState.currentFile!,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ] else if (importState.status == ImportStatus.completed) ...[
              const Icon(Icons.check_circle, size: 48, color: Colors.green),
              const SizedBox(height: 16),
              Text('导入完成: ${importState.imported} 张'),
              if (importState.skipped > 0)
                Text('跳过: ${importState.skipped} 张'),
              if (importState.failed > 0)
                Text('失败: ${importState.failed} 张'),
            ] else if (importState.status == ImportStatus.error) ...[
              const Icon(Icons.error, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('导入失败: ${importState.error}'),
            ],
          ],
        ),
      ),
      actions: [
        if (importState.status == ImportStatus.completed ||
            importState.status == ImportStatus.error)
          TextButton(
            onPressed: () {
              ref.read(importProvider.notifier).reset();
              Navigator.of(context).pop();
            },
            child: const Text('关闭'),
          ),
        if (importState.status == ImportStatus.idle)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
      ],
    );
  }

  void _pickFolder(BuildContext context, WidgetRef ref) async {
    final dialog = DirectoryPicker()
      ..title = '选择要导入的照片文件夹';

    final result = dialog.getDirectory();
    if (result != null) {
      await ref.read(importProvider.notifier).importFolder(result.path);
    }
  }
}