import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/strings.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/selection_provider.dart';
import '../../providers/view_mode_provider.dart';
import '../components/draggable_divider.dart';
import '../components/keyboard_shortcuts.dart';
import 'import_screen.dart';
import 'export_screen.dart';
import '../layout/panels/folder_panel.dart';
import '../layout/panels/filmstrip_panel.dart';
import '../layout/panels/grid_panel.dart';
import '../layout/panels/info_panel.dart';
import '../components/filter_bar.dart';
import '../components/status_bar.dart';
import 'settings_screen.dart';

/// 主界面 — 三栏布局
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(viewModeProvider);

    // 不在 HomeScreen 层级 watch catalogProvider — 会导致整个三栏布局
    // 在每次 catalog 数据变化时重建。photoIds 通过 Selector 在子树中获取。
    return KeyboardShortcuts(
      photoIds: const <int>[],
      child: Scaffold(
        body: Column(
          children: [
            // 顶部菜单栏
            _MenuBar(onImport: () => _showImportDialog(context)),
            // 筛选栏
            if (viewMode.filterBarVisible) const FilterBar(),
            // 三栏主体
            Expanded(
              child: Column(
                children: [
                  // 上部：三栏布局
                  Expanded(
                    child: Row(
                      children: [
                        // 左栏：文件夹树
                        if (viewMode.leftPanelVisible) ...[
                          SizedBox(
                            width: viewMode.leftPanelWidth,
                            child: const FolderPanel(),
                          ),
                          DraggableDivider(
                            isHorizontal: false,
                            onDrag: (delta) {
                              ref
                                  .read(viewModeProvider.notifier)
                                  .setLeftPanelWidth(
                                    viewMode.leftPanelWidth + delta,
                                  );
                            },
                          ),
                        ],
                        // 中栏：照片网格/列表
                        const Expanded(
                          child: GridPanel(),
                        ),
                        if (viewMode.rightPanelVisible)
                          const _VerticalDivider(),
                        // 右栏：信息面板
                        if (viewMode.rightPanelVisible)
                          const SizedBox(
                            width: AppConstants.rightPanelDefaultWidth,
                            child: InfoPanel(),
                          ),
                      ],
                    ),
                  ),
                  // 底部：胶片条（仅预览模式）
                  if (viewMode.mode == ViewMode.preview &&
                      viewMode.filmstripVisible) ...[
                    DraggableDivider(
                      isHorizontal: true,
                      onDrag: (delta) {
                        ref
                            .read(viewModeProvider.notifier)
                            .setFilmstripHeight(
                              viewMode.filmstripHeight - delta,
                            );
                      },
                    ),
                    SizedBox(
                      height: viewMode.filmstripHeight,
                      child: const FilmstripPanel(),
                    ),
                  ],
                ],
              ),
            ),
            // 状态栏
            const StatusBar(),
          ],
        ),
      ),
    );
  }

  void _showImportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const ImportDialog(),
    );
  }
}

/// 顶部菜单栏
class _MenuBar extends ConsumerWidget {
  final VoidCallback onImport;

  const _MenuBar({required this.onImport});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).canvasColor,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          _MenuItem(AppStrings.menuFile, [
            _MenuAction(AppStrings.menuImportFolder, 'Ctrl+I', onImport),
            _MenuAction(AppStrings.menuExport, '', () => _showExportDialog(context)),
            _MenuAction(AppStrings.menuExit, 'Alt+F4', () => Navigator.of(context).maybePop()),
          ]),
          _MenuItem(AppStrings.menuEdit, [
            _MenuAction(AppStrings.menuUndo, 'Ctrl+Z', null),
            _MenuAction(AppStrings.menuRedo, 'Ctrl+Shift+Z', null),
            _MenuAction(AppStrings.menuSelectAll, 'Ctrl+A', () => _selectAll(ref)),
          ]),
          _MenuItem(AppStrings.menuView, [
            _MenuAction(AppStrings.menuGridView, 'G', () => _setViewMode(ref, ViewMode.grid)),
            _MenuAction(AppStrings.menuListView, 'L', () => _setViewMode(ref, ViewMode.list)),
            _MenuAction(AppStrings.menuPreview, 'V', () => _setViewMode(ref, ViewMode.preview)),
            _MenuAction(AppStrings.menuZoomIn, '+', () => _zoomIn(ref)),
            _MenuAction(AppStrings.menuZoomOut, '-', () => _zoomOut(ref)),
            _MenuAction(AppStrings.menuToggleLeftPanel, 'Ctrl+B', () => _toggleLeftPanel(ref)),
            _MenuAction(AppStrings.menuToggleRightPanel, 'Ctrl+Shift+I', () => _toggleRightPanel(ref)),
            _MenuAction(AppStrings.menuToggleFilmstrip, 'Ctrl+F', () => _toggleFilmstrip(ref)),
          ]),
          _MenuItem(AppStrings.menuTags, [
            _MenuAction(AppStrings.menuManageTags, '', null),
          ]),
          _MenuItem(AppStrings.menuTools, [
            _MenuAction(AppStrings.menuSettings, 'Ctrl+,', () => _openSettings(context)),
          ]),
          _MenuItem(AppStrings.menuHelp, [
            _MenuAction(AppStrings.menuAbout, '', () => _showAboutDialog(context)),
          ]),
        ],
      ),
    );
  }

  void _selectAll(WidgetRef ref) {
    final catalog = ref.read(catalogProvider);
    catalog.maybeWhen(
      data: (photos) {
        ref.read(selectionProvider.notifier)
            .selectAll(photos.map((p) => p.id).toList());
      },
      orElse: () {},
    );
  }

  void _setViewMode(WidgetRef ref, ViewMode mode) {
    ref.read(viewModeProvider.notifier).setViewMode(mode);
  }

  void _zoomIn(WidgetRef ref) {
    ref.read(viewModeProvider.notifier).increaseThumbSize();
  }

  void _zoomOut(WidgetRef ref) {
    ref.read(viewModeProvider.notifier).decreaseThumbSize();
  }

  void _toggleLeftPanel(WidgetRef ref) {
    ref.read(viewModeProvider.notifier).toggleLeftPanel();
  }

  void _toggleRightPanel(WidgetRef ref) {
    ref.read(viewModeProvider.notifier).toggleRightPanel();
  }

  void _toggleFilmstrip(WidgetRef ref) {
    ref.read(viewModeProvider.notifier).toggleFilmstrip();
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const ExportDialog(),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.appName),
        content: const Text(
          '${AppStrings.appDescription}\n'
          '${AppStrings.settingsLabelVersion}: ${AppStrings.appVersion}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(AppStrings.ok),
          ),
        ],
      ),
    );
  }


}

class _MenuItem extends StatelessWidget {
  final String label;
  final List<_MenuAction> actions;

  const _MenuItem(this.label, this.actions);

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void>(
      offset: const Offset(0, 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
      itemBuilder: (context) => actions
          .map((action) => PopupMenuItem(
                enabled: action.onTap != null,
                onTap: action.onTap,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      action.label,
                      style: action.onTap == null
                          ? TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).disabledColor,
                            )
                          : null,
                    ),
                    if (action.shortcut.isNotEmpty)
                      Text(
                        action.shortcut,
                        style: TextStyle(
                          fontSize: 11,
                          color: action.onTap == null
                              ? Theme.of(context).disabledColor
                              : Theme.of(context).colorScheme.secondary,
                        ),
                      ),
                  ],
                ),

              ))
          .toList(),
    );
  }
}

class _MenuAction {
  final String label;
  final String shortcut;
  final VoidCallback? onTap;

  const _MenuAction(this.label, this.shortcut, this.onTap);
}

/// 垂直分隔线
class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) {
    return VerticalDivider(
      width: 1,
      thickness: 0.5,
      color: Theme.of(context).dividerColor,
    );
  }
}


