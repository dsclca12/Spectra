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
    final theme = Theme.of(context);
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
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.canvasColor,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // 选中数量
          if (selectionCount > 0) ...[
            Icon(Icons.check_circle_outline,
                size: 13, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              '选中 $selectionCount 张',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            _StatusDivider(),
          ],

          // 照片总数
          countAsync.when(
            data: (count) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.photo_library_outlined,
                    size: 13, color: theme.colorScheme.secondary),
                const SizedBox(width: 4),
                Text(
                  '共 $count 张',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          // 导入进度
          if (importActive) ...[
            const SizedBox(width: 12),
            _StatusDivider(),
            const SizedBox(width: 12),
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                importCurrentFile != null
                    ? '正在导入: $importCurrentFile'
                    : '正在扫描...',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ),
          ],

          if (importStatus == ImportStatus.completed) ...[
            const SizedBox(width: 12),
            _StatusDivider(),
            const SizedBox(width: 12),
            Icon(Icons.check_circle, size: 13, color: Colors.green),
            const SizedBox(width: 4),
            Text(
              '导入完成: $importImported 张',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.secondary,
              ),
            ),
          ],

          const Spacer(),

          // 版本号
          Text(
            'Spectra v0.1.0',
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

/// 状态栏分隔符
class _StatusDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 12,
      color: Theme.of(context).dividerColor,
    );
  }
}