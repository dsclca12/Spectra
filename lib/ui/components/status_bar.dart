import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/catalog_provider.dart';
import '../../providers/import_provider.dart';
import '../../providers/selection_provider.dart';

/// 底部状态栏
class StatusBar extends ConsumerWidget {
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(photoCountProvider);
    // 用 select 隔离 — 只在选中数量变化时重建，而非整个 SelectionState 变化
    final selectionCount = ref.watch(
      selectionProvider.select((s) => s.count),
    );
    // 用 select 隔离 — 只在导入状态/进度相关字段变化时重建
    final importActive = ref.watch(
      importProvider.select((s) => s.isActive),
    );
    final importStatus = ref.watch(
      importProvider.select((s) => s.status),
    );
    final importImported = ref.watch(
      importProvider.select((s) => s.imported),
    );
    final importCurrentFile = ref.watch(
      importProvider.select((s) => s.currentFile),
    );

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).canvasColor,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // 选中数量
          if (selectionCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '选中 $selectionCount 张',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),

          // 照片总数
          countAsync.when(
            data: (count) => Text(
              '共 $count 张',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          // 导入进度
          if (importActive) ...[
            const SizedBox(width: 16),
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              importCurrentFile != null
                  ? '正在导入: $importCurrentFile'
                  : '正在扫描...',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ],

          if (importStatus == ImportStatus.completed)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(
                '导入完成: $importImported 张',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),

          const Spacer(),

          // 版本号
          Text(
            'Spectra v0.1.0',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
        ],
      ),
    );
  }
}