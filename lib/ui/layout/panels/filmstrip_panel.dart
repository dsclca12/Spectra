import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../data/database/app_database.dart';
import '../../../providers/catalog_provider.dart';
import '../../../providers/selection_provider.dart';
import '../../components/thumbnail_widget.dart';

/// 底部胶片条面板 — 单图预览模式下在底部显示所有照片的水平缩略图列表
///
/// 功能：
/// - 水平滚动缩略图列表，显示所有照片概览
/// - 点击缩略图 → 更新 selectionProvider → PreviewPanel 自动跳转
/// - 监听 selectionProvider 变化 → 自动高亮当前项并滚动到可见位置
/// - 触摸屏友好：大触摸目标（缩略图 + 间距），选中项高亮边框
class FilmstripPanel extends ConsumerStatefulWidget {
  const FilmstripPanel({super.key});

  @override
  ConsumerState<FilmstripPanel> createState() => _FilmstripPanelState();
}

class _FilmstripPanelState extends ConsumerState<FilmstripPanel> {
  /// 滚动控制器 — 用于程序化滚动到当前选中项
  final ScrollController _scrollController = ScrollController();

  /// 上一次高亮的 photoId — 避免重复滚动
  int? _lastHighlightedId;

  /// 每个 item 的总宽度（缩略图 + 间距 + 边框）
  static const double _itemWidth = 128 + 8; // 缩略图 128 + 左右间距各 4

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 滚动到指定索引，确保该项可见
  void _scrollToIndex(int index, double viewportWidth) {
    if (!_scrollController.hasClients) return;

    final offset = index * _itemWidth;
    final currentOffset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // 如果已经在可见范围内，不滚动
    final visibleStart = currentOffset;
    final visibleEnd = currentOffset + viewportWidth;

    if (offset >= visibleStart && offset + _itemWidth <= visibleEnd) {
      return;
    }

    // 计算目标偏移 — 将目标项居中显示
    double targetOffset = offset - (viewportWidth - _itemWidth) / 2;
    targetOffset = targetOffset.clamp(0.0, maxScroll);

    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(catalogProvider);
    // 用 select 只监听选中 ID 的变化，避免 selectionProvider 中其他状态变化
    // （如全选/清除选中时的 selectedIds 集合操作）导致胶片条整体重建
    final selectedId = ref.watch(
      selectionProvider.select((s) => s.hasSelection ? s.selectedIds.first : null),
    );

    return Container(
      color: Theme.of(context).canvasColor,
      child: Column(
        children: [
          // 面板标题栏
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            child: catalogAsync.when(
              data: (photos) => Text(
                '胶片条 · ${photos.length} 张',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              loading: () => Text(
                '胶片条',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              error: (_, __) => Text(
                '胶片条',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          // 水平缩略图列表
          Expanded(
            child: catalogAsync.when(
              data: (photos) {
                if (photos.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        '没有照片',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.secondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }

                // selection 变化时自动滚动到当前项
                if (selectedId != null && selectedId != _lastHighlightedId) {
                  _lastHighlightedId = selectedId;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || !_scrollController.hasClients) return;
                    final index = photos.indexWhere((p) => p.id == selectedId);
                    if (index >= 0) {
                      _scrollToIndex(
                        index,
                        _scrollController.position.viewportDimension,
                      );
                    }
                  });
                }

                return _FilmstripList(
                  photos: photos,
                  selectedId: selectedId,
                  scrollController: _scrollController,
                  onTap: (photoId) {
                    ref.read(selectionProvider.notifier).select(photoId);
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

/// 胶片条列表 — 水平 ListView.builder 按需渲染
class _FilmstripList extends StatelessWidget {
  final List<Photo> photos;
  final int? selectedId;
  final ScrollController scrollController;
  final ValueChanged<int> onTap;

  const _FilmstripList({
    required this.photos,
    required this.selectedId,
    required this.scrollController,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      itemCount: photos.length,
      itemExtent: 128 + 8, // 固定 item 宽度，优化滚动性能
      itemBuilder: (context, index) {
        final photo = photos[index];
        final isSelected = photo.id == selectedId;

        return _FilmstripItem(
          photo: photo,
          isSelected: isSelected,
          onTap: () => onTap(photo.id),
        );
      },
    );
  }
}

/// 胶片条单项 — 缩略图 + 选中高亮
class _FilmstripItem extends ConsumerWidget {
  final Photo photo;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilmstripItem({
    required this.photo,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(
              color: theme.dividerColor.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: Stack(
          children: [
            // 选中高亮边框
            if (isSelected)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.primary,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            // 缩略图
            Padding(
              padding: const EdgeInsets.all(2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: ThumbnailWidget(
                  photoId: photo.id,
                  filePath: photo.path,
                  size: AppConstants.thumbnailSmall, // 128px
                  fit: BoxFit.cover,
                ),
              ),
            ),
            // 星级 — 数字徽章
            if (photo.rating > 0)
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB900),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '${photo.rating}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}