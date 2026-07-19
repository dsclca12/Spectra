import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/enums.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/providers.dart';
import '../../providers/selection_provider.dart';
import '../../providers/view_mode_provider.dart';
import '../screens/import_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/viewer_screen.dart';

/// 键盘快捷键管理器 — 绑定全局快捷键
class KeyboardShortcuts extends ConsumerWidget {
  final Widget child;
  final List<int> photoIds;

  const KeyboardShortcuts({
    super.key,
    required this.child,
    required this.photoIds,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 如果外部未提供 photoIds，通过 Selector 从 catalogProvider 获取
    // 用 select 只在 photoIds 列表实际变化时重建，避免 catalog loading 状态变化触发重建
    final effectivePhotoIds = photoIds.isNotEmpty
        ? photoIds
        : ref.watch(catalogProvider.select((async) {
            return async.maybeWhen(
              data: (photos) => photos.map((p) => p.id).toList(growable: false),
              orElse: () => const <int>[],
            );
          }));

    return Focus(
      autofocus: true,
      onKeyEvent: (focusNode, KeyEvent event) =>
          _handleKeyEvent(context, ref, event, effectivePhotoIds),
      child: child,
    );
  }

  KeyEventResult _handleKeyEvent(
    BuildContext context,
    WidgetRef ref,
    KeyEvent event,
    List<int> photoIds,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final selection = ref.read(selectionProvider);
    final catalogService = ref.read(catalogServiceProvider);
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    final key = event.logicalKey;

    // ── Ctrl 组合键 ──

    // Ctrl+I — 导入文件夹
    if (key == LogicalKeyboardKey.keyI && isCtrl) {
      showDialog(context: context, builder: (_) => const ImportDialog());
      return KeyEventResult.handled;
    }

    // Ctrl+F — 聚焦搜索框
    if (key == LogicalKeyboardKey.keyF && isCtrl) {
      _focusSearchField(context);
      return KeyEventResult.handled;
    }

    // Ctrl+Shift+I — 切换右栏（信息面板）
    if (key == LogicalKeyboardKey.keyI && isCtrl && isShift) {
      ref.read(viewModeProvider.notifier).toggleRightPanel();
      return KeyEventResult.handled;
    }

    // Ctrl+A — 全选
    if (key == LogicalKeyboardKey.keyA && isCtrl) {
      ref.read(selectionProvider.notifier).selectAll(photoIds);
      return KeyEventResult.handled;
    }

    // Ctrl+B — 切换左栏
    if (key == LogicalKeyboardKey.keyB && isCtrl) {
      ref.read(viewModeProvider.notifier).toggleLeftPanel();
      return KeyEventResult.handled;
    }

    // Ctrl+H — 切换筛选栏
    if (key == LogicalKeyboardKey.keyH && isCtrl) {
      ref.read(viewModeProvider.notifier).toggleFilterBar();
      return KeyEventResult.handled;
    }

    // Ctrl+, — 打开设置
    if (key == LogicalKeyboardKey.comma && isCtrl) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
      return KeyEventResult.handled;
    }

    // ── 数字键 0-5 — 评分 ──
    if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.digit1 ||
        key == LogicalKeyboardKey.digit2 ||
        key == LogicalKeyboardKey.digit3 ||
        key == LogicalKeyboardKey.digit4 ||
        key == LogicalKeyboardKey.digit5) {
      final rating = key.keyId - LogicalKeyboardKey.digit0.keyId;
      if (selection.hasSelection) {
        catalogService.batchRate(selection.selectedIds.toList(), rating);
        for (final id in selection.selectedIds) {
          ref.invalidate(photoByIdProvider(id));
        }
        ref.invalidate(catalogProvider);
      }
      return KeyEventResult.handled;
    }

    // ── 旗标 ──

    // P — Pick
    if (key == LogicalKeyboardKey.keyP) {
      if (selection.hasSelection) {
        catalogService.batchSetPick(selection.selectedIds.toList(), PickLabel.pick);
        for (final id in selection.selectedIds) {
          ref.invalidate(photoByIdProvider(id));
        }
        ref.invalidate(catalogProvider);
      }
      return KeyEventResult.handled;
    }

    // U — Unpick
    if (key == LogicalKeyboardKey.keyU) {
      if (selection.hasSelection) {
        catalogService.batchSetPick(selection.selectedIds.toList(), PickLabel.none);
        for (final id in selection.selectedIds) {
          ref.invalidate(photoByIdProvider(id));
        }
        ref.invalidate(catalogProvider);
      }
      return KeyEventResult.handled;
    }

    // X — Reject
    if (key == LogicalKeyboardKey.keyX) {
      if (selection.hasSelection) {
        catalogService.batchSetPick(selection.selectedIds.toList(), PickLabel.reject);
        for (final id in selection.selectedIds) {
          ref.invalidate(photoByIdProvider(id));
        }
        ref.invalidate(catalogProvider);
      }
      return KeyEventResult.handled;
    }

    // ── F1-F7 — 色标 ──
    if (key == LogicalKeyboardKey.f1) {
      _setColorLabel(ref, selection, catalogService, 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f2) {
      _setColorLabel(ref, selection, catalogService, 2);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f3) {
      _setColorLabel(ref, selection, catalogService, 3);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f4) {
      _setColorLabel(ref, selection, catalogService, 4);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f5) {
      _setColorLabel(ref, selection, catalogService, 5);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f6) {
      _setColorLabel(ref, selection, catalogService, 6);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f7) {
      if (selection.hasSelection) {
        catalogService.batchSetColor(selection.selectedIds.toList(), 0);
        for (final id in selection.selectedIds) {
          ref.invalidate(photoByIdProvider(id));
        }
        ref.invalidate(catalogProvider);
      }
      return KeyEventResult.handled;
    }

    // ── Esc — 取消选择 ──
    if (key == LogicalKeyboardKey.escape) {
      ref.read(selectionProvider.notifier).clear();
      return KeyEventResult.handled;
    }

    // ── Enter — 打开全屏查看器（选中第一张）──
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (selection.hasSelection) {
        final firstId = selection.selectedIds.first;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ViewerScreen(photoId: firstId)),
        );
      } else if (photoIds.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ViewerScreen(photoId: photoIds.first)),
        );
      }
      return KeyEventResult.handled;
    }

    // ── F — 全屏查看器（同 Enter）──
    if (key == LogicalKeyboardKey.keyF && !isCtrl) {
      if (selection.hasSelection) {
        final firstId = selection.selectedIds.first;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ViewerScreen(photoId: firstId)),
        );
      } else if (photoIds.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ViewerScreen(photoId: photoIds.first)),
        );
      }
      return KeyEventResult.handled;
    }

    // ── 方向键 — 浏览导航 ──
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      if (photoIds.isEmpty) return KeyEventResult.ignored;
      final currentId = selection.hasSelection
          ? selection.selectedIds.first
          : photoIds.first;
      final currentIndex = photoIds.indexOf(currentId);
      if (currentIndex == -1) return KeyEventResult.ignored;
      final direction = key == LogicalKeyboardKey.arrowLeft ? -1 : 1;
      final newIndex = (currentIndex + direction).clamp(0, photoIds.length - 1);
      if (newIndex != currentIndex) {
        ref.read(selectionProvider.notifier).select(photoIds[newIndex]);
      }
      return KeyEventResult.handled;
    }

    // ── + / - — 缩略图尺寸 ──
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.numpadAdd) {
      ref.read(viewModeProvider.notifier).increaseThumbSize();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      ref.read(viewModeProvider.notifier).decreaseThumbSize();
      return KeyEventResult.handled;
    }

    // ── G — 网格视图 ──
    if (key == LogicalKeyboardKey.keyG) {
      ref.read(viewModeProvider.notifier).setViewMode(ViewMode.grid);
      return KeyEventResult.handled;
    }

    // ── L — 列表视图 ──
    if (key == LogicalKeyboardKey.keyL) {
      ref.read(viewModeProvider.notifier).setViewMode(ViewMode.list);
      return KeyEventResult.handled;
    }

    // ── V — 单图预览 ──
    if (key == LogicalKeyboardKey.keyV) {
      ref.read(viewModeProvider.notifier).setViewMode(ViewMode.preview);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  /// 聚焦搜索框 — 通过 FocusScope 查找 FilterBar 中的搜索框
  void _focusSearchField(BuildContext context) {
    // 搜索框用 SearchFieldFocusNode 标记，这里查找并聚焦
    final focusNode = SearchFieldFocusNodeHolder.instance.focusNode;
    if (focusNode != null) {
      focusNode.requestFocus();
    }
  }

  void _setColorLabel(
    WidgetRef ref,
    SelectionState selection,
    dynamic catalogService,
    int label,
  ) {
    if (selection.hasSelection) {
      catalogService.batchSetColor(selection.selectedIds.toList(), label);
      for (final id in selection.selectedIds) {
        ref.invalidate(photoByIdProvider(id));
      }
      ref.invalidate(catalogProvider);
    }
  }
}

/// 全局搜索框焦点持有者 — 让快捷键可以聚焦搜索框
class SearchFieldFocusNodeHolder {
  SearchFieldFocusNodeHolder._();
  static final SearchFieldFocusNodeHolder instance = SearchFieldFocusNodeHolder._();
  FocusNode? focusNode;
}