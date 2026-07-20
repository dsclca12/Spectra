import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/catalog_provider.dart';
import '../../../providers/view_mode_provider.dart';
import '../../components/photo_grid.dart';
import '../../components/photo_list.dart';
import '../../components/empty_state.dart';
import '../../screens/import_screen.dart';
import 'preview_panel.dart';

/// 中栏：照片网格/列表面板
class GridPanel extends ConsumerWidget {
  const GridPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(catalogProvider);
    final viewMode = ref.watch(viewModeProvider);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: catalogAsync.when(
        data: (photos) {
          if (photos.isEmpty) {
            return EmptyState(
              icon: Icons.photo_library_outlined,
              title: '还没有照片',
              message: '拖拽照片到此，或点击"导入文件夹"',
              actionLabel: '导入文件夹',
              onAction: () => _showImportDialog(context),
            );
          }

          return switch (viewMode.mode) {
            ViewMode.grid => PhotoGrid(photos: photos),
            ViewMode.list => PhotoList(photos: photos),
            ViewMode.preview => const PreviewPanel(),
          };
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          icon: Icons.error_outline,
          title: '加载失败',
          message: e.toString(),
          actionLabel: '重试',
          onAction: () => ref.invalidate(catalogProvider),
        ),
      ),
    );
  }

  void _showImportDialog(BuildContext context) {
    showImportDialog(context);
  }
}

/// 通用导入对话框快捷函数 — HomeScreen 和 GridPanel 共用
/// 避免两处维护相同的 dialog show 代码
void showImportDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (_) => const ImportDialog(),
  );
}