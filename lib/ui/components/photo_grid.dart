import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/providers.dart';
import '../../providers/selection_provider.dart';
import '../../providers/view_mode_provider.dart';
import '../screens/viewer_screen.dart';
import 'color_label.dart';
import 'thumbnail_widget.dart';

/// 照片网格视图 — 主界面中栏的核心组件。
///
/// ⚡ 性能设计要点：
/// 1. **select 隔离**：只监听 thumbPixelSize，面板可见性/胶片条高度等变化不重建网格
/// 2. **LayoutBuilder 替代 MediaQuery**：获取实际可用宽度而非屏幕宽度，
///    侧栏切换时列数计算不受影响
/// 3. **scrollCacheExtent: 500px**：默认 250px 太小，滚动频繁创建/销毁项
///    500px 预渲染更多屏幕外项目，滚动更流畅
/// 4. **RepaintBoundary**：每个网格项独立隔离重绘范围
/// 5. **Selector 选中状态**：`select((s) => s.isSelected(photo.id))` 只监听自身
/// 6. **ConsumerStatefulWidget + gaplessPlayback**：缩略图尺寸切换时保持显示旧图
///
/// 参见：_PhotoGridItem, ThumbnailWidget, photo_grid_item
class PhotoGrid extends ConsumerWidget {
  final List<Photo> photos;

  const PhotoGrid({super.key, required this.photos});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 用 select 隔离 — 只在 thumbPixelSize 变化时重建，
    // 避免其他视图状态（面板可见性等）变化时重建整个网格
    final thumbSize = ref.watch(
      viewModeProvider.select((vm) => vm.thumbPixelSize),
    );

    // 用 LayoutBuilder 获取实际可用宽度，而非 MediaQuery（含侧栏宽度）
    // 避免窗口缩放/侧栏切换时列数计算偏差
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount =
            (constraints.maxWidth / (thumbSize + 4)).floor().clamp(2, 20);

        return GridView.builder(
          padding: const EdgeInsets.all(4),
          // scrollCacheExtent: 增加预渲染范围，滚动更流畅。
          // 默认 250px 太小，滚动时频繁创建/销毁项导致卡顿。
          // 500px 约 2-3 行额外预渲染，内存增加可控。
          // Flutter 3.44+ cacheExtent 已废弃，使用 ScrollCacheExtent。
          scrollCacheExtent: const ScrollCacheExtent.pixels(500),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: photos.length,
          itemBuilder: (context, index) {
            final photo = photos[index];
            // RepaintBoundary 隔离每个网格项的重绘范围
            // 滚动时只有可见项重绘，不会波及其他项
            return RepaintBoundary(
              child: _PhotoGridItem(
                photo: photo,
                thumbSize: thumbSize,
                index: index,
              ),
            );
          },
        );
      },
    );
  }
}

/// 网格项
class _PhotoGridItem extends ConsumerStatefulWidget {
  final Photo photo;
  final double thumbSize;
  final int index;

  const _PhotoGridItem({
    required this.photo,
    required this.thumbSize,
    required this.index,
  });

  @override
  ConsumerState<_PhotoGridItem> createState() => _PhotoGridItemState();
}

class _PhotoGridItemState extends ConsumerState<_PhotoGridItem> {
  /// 缓存右键点击位置，用于上下文菜单定位
  Offset? _lastTapPosition;
  bool _hovered = false;

  Photo get photo => widget.photo;
  double get thumbSize => widget.thumbSize;
  int get index => widget.index;

  @override
  Widget build(BuildContext context) {
    // 用 Selector 隔离选中状态 — 选中变化时只重建受影响的网格项，
    // 而非全部 200 个可见项都重建并重新 watch 缩略图 provider
    final isSelected = ref.watch(
      selectionProvider.select((s) => s.isSelected(photo.id)),
    );
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (details) {
          _lastTapPosition = details.globalPosition;
        },
        onTap: () {
          final selection = ref.read(selectionProvider);
          if (selection.hasSelection) {
            ref.read(selectionProvider.notifier).toggle(photo.id);
          } else {
            ref.read(selectionProvider.notifier).select(photo.id);
          }
        },
        onDoubleTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ViewerScreen(photoId: photo.id),
            ),
          );
        },
        onSecondaryTap: () => _showContextMenu(context),
        onLongPress: () => _showContextMenu(context),
        child: Stack(
          children: [
            // 缩略图
            Positioned.fill(
              child: ThumbnailWidget(
                photoId: photo.id,
                filePath: photo.path,
                size: thumbSize.toInt(),
              ),
            ),

            // 悬停遮罩 — 微亮 + 顶部渐变（用于突出可点击）
            if (_hovered && !isSelected)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),

            // 选中边框
            if (isSelected)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.primary,
                        width: 2.5,
                      ),
                    ),
                  ),
                ),
              ),

            // 旗标图标（左上角）
            if (photo.pickLabel > 0)
              Positioned(
                top: 4,
                left: 4,
                child: _PickLabelIcon(pickLabel: photo.pickLabel),
              ),

            // 星级（右下角，数字显示）
            if (photo.rating > 0)
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB900),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 3,
                      ),
                    ],
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

            // 色标条（底部）
            if (photo.colorLabel > 0)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ColorLabelBar(colorLabel: photo.colorLabel),
              ),

            // 选中序号
            if (isSelected)
              _SelectionBadge(photoId: photo.id),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    final catalogService = ref.read(catalogServiceProvider);
    final selection = ref.read(selectionProvider);
    final targetIds = selection.isSelected(photo.id) && selection.hasSelection
        ? selection.selectedIds.toList()
        : [photo.id];

    // 获取右键点击位置 — 让菜单出现在光标处而非固定位置
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final tapPosition = _lastTapPosition ??
        Offset(overlay.size.width / 2, overlay.size.height / 2);
    final relativeRect = RelativeRect.fromLTRB(
      tapPosition.dx,
      tapPosition.dy,
      overlay.size.width - tapPosition.dx,
      overlay.size.height - tapPosition.dy,
    );

    // ── 上下文菜单：批量操作 ──
    //
    // ⚡ 性能说明（v0.4.9）：
    // 每个操作先调用 catalogService 的批量 API（单条 SQL），然后：
    // 1. `ref.invalidate(catalogProvider)` — 刷新照片列表，保证网格视图更新
    // 2. 对每个目标 ID 调用 `ref.invalidate(photoByIdProvider(id))` —
    //    确保打开的详情面板或独立 photo widget 同步更新
    //
    // `ref.invalidate` 本身是 O(1) 轻量操作 — 仅标记为「下次读取时重新计算」，
    // 不会立即触发重建，所以即使 targetIds 包含数百个项目，开销也可忽略。
    // 这是「显式优于隐式」的设计：宁可多 invalidate 确保一致性，
    // 也不冒列表与详情不同步的风险。
    showMenu<void>(
      context: context,
      position: relativeRect,
      items: [
        const PopupMenuItem<void>(child: Text('⭐ 评分')),
        for (var i = 5; i >= 1; i--)
          PopupMenuItem<void>(
            child: Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text('${'★' * i}${'☆' * (5 - i)} ($i)'),
            ),
            onTap: () async {
              await catalogService.batchRate(targetIds, i);
              for (final id in targetIds) {
                ref.invalidate(photoByIdProvider(id));
              }
              ref.invalidate(catalogProvider);
            },
          ),
        PopupMenuItem(
          child: const Padding(
            padding: EdgeInsets.only(left: 20),
            child: Text('清除评分 (0)'),
          ),
          onTap: () async {
            await catalogService.batchRate(targetIds, 0);
            for (final id in targetIds) {
              ref.invalidate(photoByIdProvider(id));
            }
            ref.invalidate(catalogProvider);
          },
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(child: Text('🚩 旗标')),
        PopupMenuItem(
          child: const Padding(padding: EdgeInsets.only(left: 20), child: Text('Pick')),
          onTap: () async {
            await catalogService.batchSetPick(targetIds, 1);
            for (final id in targetIds) {
              ref.invalidate(photoByIdProvider(id));
            }
            ref.invalidate(catalogProvider);
          },
        ),
        PopupMenuItem(
          child: const Padding(padding: EdgeInsets.only(left: 20), child: Text('Reject')),
          onTap: () async {
            await catalogService.batchSetPick(targetIds, 2);
            for (final id in targetIds) {
              ref.invalidate(photoByIdProvider(id));
            }
            ref.invalidate(catalogProvider);
          },
        ),
        PopupMenuItem(
          child: const Padding(padding: EdgeInsets.only(left: 20), child: Text('清除旗标')),
          onTap: () async {
            await catalogService.batchSetPick(targetIds, 0);
            for (final id in targetIds) {
              ref.invalidate(photoByIdProvider(id));
            }
            ref.invalidate(catalogProvider);
          },
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(child: Text('🏷️ 色标')),
        for (final entry in [
          (const Color(0xFFE81123), '红', 1),
          (const Color(0xFFFFB900), '黄', 2),
          (const Color(0xFF10893E), '绿', 3),
          (const Color(0xFF0078D4), '蓝', 4),
          (const Color(0xFF8661C5), '紫', 5),
          (const Color(0xFF69797E), '灰', 6),
        ])
          PopupMenuItem(
            child: Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Row(
                children: [
                  Container(width: 12, height: 12, color: entry.$1),
                  const SizedBox(width: 8),
                  Text(entry.$2),
                ],
              ),
            ),
            onTap: () async {
              await catalogService.batchSetColor(targetIds, entry.$3);
              for (final id in targetIds) {
                ref.invalidate(photoByIdProvider(id));
              }
              ref.invalidate(catalogProvider);
            },
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          child: const Text('❌ 从目录中移除'),
          onTap: () async {
            // 批量删除 — 单事务，避免逐条 DELETE 的 N 次 DB 往返
            await catalogService.removePhotos(targetIds);
            ref.invalidate(catalogProvider);
          },
        ),
      ],
    );
  }
}

/// 旗标图标
class _PickLabelIcon extends StatelessWidget {
  final int pickLabel;

  const _PickLabelIcon({required this.pickLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Icon(
        pickLabel == 1 ? Icons.flag : Icons.close,
        size: 14,
        color: pickLabel == 1 ? Colors.white : const Color(0xFFE81123),
      ),
    );
  }
}

/// 选中序号徽标 — 用 Selector 只在序号变化时重建
class _SelectionBadge extends ConsumerWidget {
  final int photoId;

  const _SelectionBadge({required this.photoId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 用 select 隔离 — 只在选中序号变化时重建
    // 避免每次 build 调用 toList() 创建新列表 — 直接遍历 Set
    final index = ref.watch(
      selectionProvider.select((s) {
        if (!s.isSelected(photoId)) return -1;
        var i = 0;
        for (final id in s.selectedIds) {
          if (id == photoId) return i;
          i++;
        }
        return -1;
      }),
    );
    if (index < 0) return const SizedBox.shrink();

    return Positioned(
      top: 4,
      right: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          '${index + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}