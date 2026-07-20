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
    final theme = Theme.of(context);

    return AlertDialog(
      icon: switch (importState.status) {
        ImportStatus.completed =>
          const Icon(Icons.check_circle, size: 40, color: Colors.green),
        ImportStatus.error =>
          const Icon(Icons.error, size: 40, color: Colors.red),
        ImportStatus.idle => Icon(Icons.folder_open,
            size: 40, color: theme.colorScheme.primary),
        _ => null,
      },
      title: const Text('导入文件夹'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (importState.status == ImportStatus.idle) ...[
              const Text(
                '选择要导入的照片文件夹。支持的格式包括 JPG、PNG、HEIC、RAW 等。',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _pickFolder(context, ref),
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('选择文件夹'),
                  ),
                ],
              ),
            ] else if (importState.isActive) ...[
              // 状态指示
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    importState.status == ImportStatus.scanning
                        ? '正在扫描文件夹...'
                        : '正在导入照片...',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 统计数字
              _ImportStatRow(
                imported: importState.imported,
                skipped: importState.skipped,
                failed: importState.failed,
              ),
              const SizedBox(height: 12),
              // 当前文件
              if (importState.currentFile != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.hoverColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.insert_drive_file,
                          size: 14, color: theme.colorScheme.secondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          importState.currentFile!,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.secondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ] else if (importState.status == ImportStatus.completed) ...[
              const SizedBox(height: 4),
              Text(
                '成功导入 ${importState.imported} 张照片',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              _ImportStatRow(
                imported: importState.imported,
                skipped: importState.skipped,
                failed: importState.failed,
              ),
            ] else if (importState.status == ImportStatus.error) ...[
              const SizedBox(height: 4),
              const Text(
                '导入失败',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.4)),
                ),
                child: Text(
                  importState.error ?? '未知错误',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
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

/// 导入统计行 — 显示已导入/跳过/失败数量
class _ImportStatRow extends StatelessWidget {
  final int imported;
  final int skipped;
  final int failed;

  const _ImportStatRow({
    required this.imported,
    required this.skipped,
    required this.failed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: _StatChip(
            label: '已导入',
            value: imported,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            label: '跳过',
            value: skipped,
            color: theme.colorScheme.secondary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _StatChip(
            label: '失败',
            value: failed,
            color: failed > 0
                ? theme.colorScheme.error
                : theme.colorScheme.secondary,
          ),
        ),
      ],
    );
  }
}

/// 统计芯片
class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.secondary,
            ),
          ),
        ],
      ),
    );
  }
}