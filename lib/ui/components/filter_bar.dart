import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/enums.dart';
import '../../data/models/photo_filter.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/view_mode_provider.dart';
import 'keyboard_shortcuts.dart';

/// 筛选栏 — 组合筛选条件
class FilterBar extends ConsumerWidget {
  const FilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(filterProvider);
    final viewMode = ref.watch(viewModeProvider);

    return Container(
      height: 48,
      color: Theme.of(context).canvasColor,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // 视图切换
          _IconButton(
            icon: viewMode.mode == ViewMode.grid
                ? Icons.view_list
                : Icons.grid_view,
            tooltip: '切换视图',
            onTap: () => ref.read(viewModeProvider.notifier).toggleViewMode(),
          ),
          const SizedBox(width: 4),

          // 缩略图尺寸
          _IconButton(
            icon: Icons.zoom_in,
            tooltip: '放大缩略图',
            onTap: () => ref.read(viewModeProvider.notifier).increaseThumbSize(),
          ),
          _IconButton(
            icon: Icons.zoom_out,
            tooltip: '缩小缩略图',
            onTap: () => ref.read(viewModeProvider.notifier).decreaseThumbSize(),
          ),
          const SizedBox(width: 8),
          const _VerticalDividerSmall(),

          // 星级筛选
          _FilterChip(
            label: filter.minRating != null ? '⭐ ≥${filter.minRating}' : '星级',
            active: filter.minRating != null,
            onTap: () => _showRatingFilter(context, ref),
          ),

          // 旗标筛选
          _FilterChip(
            label: filter.pickLabel != null
                ? _pickLabelName(filter.pickLabel!)
                : '旗标',
            active: filter.pickLabel != null,
            onTap: () => _showPickFilter(context, ref),
          ),

          // 色标筛选
          _FilterChip(
            label: filter.colorLabels != null && filter.colorLabels!.isNotEmpty
                ? '色标 (${filter.colorLabels!.length})'
                : '色标',
            active: filter.colorLabels != null && filter.colorLabels!.isNotEmpty,
            onTap: () => _showColorFilter(context, ref),
          ),

          // 日期筛选
          _FilterChip(
            label: _dateLabel(filter),
            active: filter.dateFrom != null || filter.dateTo != null,
            onTap: () => _showDateFilter(context, ref),
          ),

          // 相机筛选
          _FilterChip(
            label: filter.cameraModel != null && filter.cameraModel!.isNotEmpty
                ? '📷 ${filter.cameraModel}'
                : '相机',
            active: filter.cameraModel != null && filter.cameraModel!.isNotEmpty,
            onTap: () => _showCameraFilter(context, ref),
          ),

          // 排序
          _FilterChip(
            label: _sortLabel(filter),
            active: false,
            onTap: () => _showSortMenu(context, ref),
          ),

          // 搜索框
          const SizedBox(width: 8),
          Expanded(
            child: _SearchField(
              value: filter.searchQuery ?? '',
              onChanged: (value) {
                ref.read(filterProvider.notifier).state =
                    filter.copyWith(searchQuery: value);
              },
            ),
          ),

          // 清空筛选
          if (filter.hasActiveFilters)
            _IconButton(
              icon: Icons.clear_all,
              tooltip: '清空所有筛选',
              onTap: () {
                ref.read(filterProvider.notifier).state = const PhotoFilter();
              },
            ),
        ],
      ),
    );
  }

  String _pickLabelName(int label) {
    return switch (label) {
      PickLabel.pick => '🚩 Pick',
      PickLabel.reject => '✗ Reject',
      _ => '旗标',
    };
  }

  void _showRatingFilter(BuildContext context, WidgetRef ref) {
    final filter = ref.read(filterProvider);
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(200, 80, 0, 0),
      items: [
        for (var i = 1; i <= 5; i++)
          PopupMenuItem(
            child: Text('≥ $i 星'),
            onTap: () {
              ref.read(filterProvider.notifier).state =
                  filter.copyWith(minRating: i);
            },
          ),
        PopupMenuItem(
          child: const Text('未评分'),
          onTap: () {
            ref.read(filterProvider.notifier).state =
                filter.copyWith(minRating: 0, maxRating: 0);
          },
        ),
        PopupMenuItem(
          child: const Text('清除'),
          onTap: () {
            ref.read(filterProvider.notifier).state =
                filter.copyWith(clearMinRating: true);
          },
        ),
      ],
    );
  }

  void _showPickFilter(BuildContext context, WidgetRef ref) {
    final filter = ref.read(filterProvider);
    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(260, 80, 0, 0),
      items: [
        PopupMenuItem(
          child: const Text('🚩 Pick'),
          onTap: () {
            ref.read(filterProvider.notifier).state =
                filter.copyWith(pickLabel: PickLabel.pick);
          },
        ),
        PopupMenuItem(
          child: const Text('✗ Reject'),
          onTap: () {
            ref.read(filterProvider.notifier).state =
                filter.copyWith(pickLabel: PickLabel.reject);
          },
        ),
        PopupMenuItem(
          child: const Text('清除'),
          onTap: () {
            ref.read(filterProvider.notifier).state =
                filter.copyWith(clearPickLabel: true);
          },
        ),
      ],
    );
  }

  void _showColorFilter(BuildContext context, WidgetRef ref) {
    final filter = ref.read(filterProvider);
    final colors = [
      (const Color(0xFFE81123), '红', 1),
      (const Color(0xFFFFB900), '黄', 2),
      (const Color(0xFF10893E), '绿', 3),
      (const Color(0xFF0078D4), '蓝', 4),
      (const Color(0xFF8661C5), '紫', 5),
      (const Color(0xFF69797E), '灰', 6),
    ];

    showMenu(
      context: context,
      position: const RelativeRect.fromLTRB(320, 80, 0, 0),
      items: [
        for (final c in colors)
          PopupMenuItem(
            child: Row(
              children: [
                Container(width: 12, height: 12, color: c.$1),
                const SizedBox(width: 8),
                Text(c.$2),
              ],
            ),
            onTap: () {
              final current = filter.colorLabels ?? [];
              ref.read(filterProvider.notifier).state = filter.copyWith(
                colorLabels: [...current, c.$3],
              );
            },
          ),
        PopupMenuItem(
          child: const Text('清除'),
          onTap: () {
            ref.read(filterProvider.notifier).state =
                filter.copyWith(clearColorLabels: true);
          },
        ),
      ],
    );
  }

  // ─── 日期筛选 ───

  String _dateLabel(PhotoFilter filter) {
    if (filter.dateFrom != null && filter.dateTo != null) {
      return '📅 ${_formatDate(filter.dateFrom!)}~${_formatDate(filter.dateTo!)}';
    }
    if (filter.dateFrom != null) return '📅 ≥${_formatDate(filter.dateFrom!)}';
    if (filter.dateTo != null) return '📅 ≤${_formatDate(filter.dateTo!)}';
    return '日期';
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  void _showDateFilter(BuildContext context, WidgetRef ref) {
    final filter = ref.read(filterProvider);
    showMenu<PopupMenuEntry>(
      context: context,
      position: const RelativeRect.fromLTRB(380, 80, 0, 0),
      items: [
        PopupMenuItem(
          child: const Text('今天'),
          onTap: () {
            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            ref.read(filterProvider.notifier).state = filter.copyWith(
              dateFrom: today,
              dateTo: today.add(const Duration(days: 1)),
            );
          },
        ),
        PopupMenuItem(
          child: const Text('本周'),
          onTap: () {
            final now = DateTime.now();
            final weekStart = now.subtract(Duration(days: now.weekday - 1));
            final weekStart0 = DateTime(weekStart.year, weekStart.month, weekStart.day);
            ref.read(filterProvider.notifier).state = filter.copyWith(
              dateFrom: weekStart0,
              dateTo: weekStart0.add(const Duration(days: 7)),
            );
          },
        ),
        PopupMenuItem(
          child: const Text('本月'),
          onTap: () {
            final now = DateTime.now();
            final monthStart = DateTime(now.year, now.month, 1);
            final monthEnd = DateTime(now.year, now.month + 1, 1);
            ref.read(filterProvider.notifier).state = filter.copyWith(
              dateFrom: monthStart,
              dateTo: monthEnd,
            );
          },
        ),
        PopupMenuItem(
          child: const Text('今年'),
          onTap: () {
            final now = DateTime.now();
            ref.read(filterProvider.notifier).state = filter.copyWith(
              dateFrom: DateTime(now.year, 1, 1),
              dateTo: DateTime(now.year + 1, 1, 1),
            );
          },
        ),
        PopupMenuItem(
          child: const Text('自定义范围...'),
          onTap: () => _showDateRangePicker(context, ref),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          child: const Text('清除'),
          onTap: () {
            ref.read(filterProvider.notifier).state =
                filter.copyWith(clearDateRange: true);
          },
        ),
      ],
    );
  }

  void _showDateRangePicker(BuildContext context, WidgetRef ref) async {
    final filter = ref.read(filterProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1990),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: filter.dateFrom != null && filter.dateTo != null
          ? DateTimeRange(start: filter.dateFrom!, end: filter.dateTo!)
          : null,
    );
    if (picked != null) {
      ref.read(filterProvider.notifier).state = filter.copyWith(
        dateFrom: picked.start,
        dateTo: picked.end.add(const Duration(days: 1)),
      );
    }
  }

  // ─── 相机筛选 ───

  void _showCameraFilter(BuildContext context, WidgetRef ref) async {
    final filter = ref.read(filterProvider);
    final cameraModels = await ref.read(cameraModelsProvider.future);

    if (!context.mounted) return;

    showMenu<PopupMenuEntry>(
      context: context,
      position: const RelativeRect.fromLTRB(440, 80, 0, 0),
      items: [
        for (final entry in cameraModels.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
          PopupMenuItem(
            child: Text('${entry.key} (${entry.value})'),
            onTap: () {
              ref.read(filterProvider.notifier).state =
                  filter.copyWith(cameraModel: entry.key);
            },
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          child: const Text('清除'),
          onTap: () {
            ref.read(filterProvider.notifier).state =
                filter.copyWith(clearCameraModel: true);
          },
        ),
      ],
    );
  }

  // ─── 排序 ───

  String _sortLabel(PhotoFilter filter) {
    final name = switch (filter.sortBy) {
      'dateTaken' => '拍摄日期',
      'importedAt' => '导入日期',
      'rating' => '星级',
      'fileName' => '文件名',
      _ => '排序',
    };
    return '$name ${filter.ascending ? '↑' : '↓'}';
  }

  void _showSortMenu(BuildContext context, WidgetRef ref) {
    final filter = ref.read(filterProvider);
    showMenu<PopupMenuEntry>(
      context: context,
      position: const RelativeRect.fromLTRB(500, 80, 0, 0),
      items: [
        PopupMenuItem(
          child: const Text('拍摄日期'),
          onTap: () {
            ref.read(filterProvider.notifier).state =
                filter.copyWith(sortBy: 'dateTaken');
          },
        ),
        PopupMenuItem(
          child: const Text('导入日期'),
          onTap: () {
            ref.read(filterProvider.notifier).state =
                filter.copyWith(sortBy: 'importedAt');
          },
        ),
        PopupMenuItem(
          child: const Text('星级'),
          onTap: () {
            ref.read(filterProvider.notifier).state =
                filter.copyWith(sortBy: 'rating');
          },
        ),
        PopupMenuItem(
          child: const Text('文件名'),
          onTap: () {
            ref.read(filterProvider.notifier).state =
                filter.copyWith(sortBy: 'fileName');
          },
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          child: Text(filter.ascending ? '✓ 升序' : '升序'),
          onTap: () {
            ref.read(filterProvider.notifier).state =
                filter.copyWith(ascending: true);
          },
        ),
        PopupMenuItem(
          child: Text(!filter.ascending ? '✓ 降序' : '降序'),
          onTap: () {
            ref.read(filterProvider.notifier).state =
                filter.copyWith(ascending: false);
          },
        ),
      ],
    );
  }
}

/// 筛选芯片
class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: active
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: active
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 搜索框 — StatefulWidget 正确管理 TextEditingController
/// 避免每次 build 创建新 controller 导致光标跳回开头
class _SearchField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _SearchField({required this.value, required this.onChanged});

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode();
    // 注册到全局持有者，让 Ctrl+F 快捷键可以聚焦搜索框
    SearchFieldFocusNodeHolder.instance.focusNode = _focusNode;
  }

  @override
  void didUpdateWidget(_SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部值变化时同步 controller，保留光标位置
    if (_controller.text != widget.value) {
      final selection = _controller.selection;
      _controller.text = widget.value;
      // 尝试恢复光标位置
      if (selection.start >= 0 && selection.start <= widget.value.length) {
        _controller.selection = selection;
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    // 清除全局持有者引用
    if (SearchFieldFocusNodeHolder.instance.focusNode == _focusNode) {
      SearchFieldFocusNodeHolder.instance.focusNode = null;
    }
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // debounce 300ms — 避免每次按键触发数据库查询
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      widget.onChanged(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: InputDecoration(
        hintText: '搜索文件名、标签、标题...',
        hintStyle: const TextStyle(fontSize: 12),
        prefixIcon: const Icon(Icons.search, size: 16),
        suffixIcon: widget.value.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, size: 16),
                onPressed: () {
                  _controller.clear();
                  _onChanged('');
                },
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: Theme.of(context).scaffoldBackgroundColor,
      ),
      style: const TextStyle(fontSize: 12),
      onChanged: _onChanged,
    );
  }
}

/// 图标按钮 — 触控目标 42px，符合 Material Design 推荐最小值
class _IconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, size: 18,
              color: Theme.of(context).colorScheme.onSurface),
        ),
      ),
    );
  }
}

class _VerticalDividerSmall extends StatelessWidget {
  const _VerticalDividerSmall();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Theme.of(context).dividerColor,
    );
  }
}