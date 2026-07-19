import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings.dart';
import '../../providers/settings_provider.dart';

/// Settings screen — tabbed settings panel
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  int _selectedIndex = 0;

  final _sections = const [
    (Icons.palette, AppStrings.settingsAppearance),
    (Icons.image, AppStrings.settingsThumbnails),
    (Icons.download, AppStrings.settingsImport),
    (Icons.search, AppStrings.settingsSearch),
    (Icons.grid_view, AppStrings.settingsBrowse),
    (Icons.speed, AppStrings.settingsPerformance),
    (Icons.edit, AppStrings.settingsEditing),
    (Icons.keyboard, AppStrings.settingsShortcuts),
    (Icons.info, AppStrings.settingsAbout),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.settingsTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _confirmReset(context),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text(AppStrings.settingsResetAll),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          // 左侧导航 — Material 包裹为 ListTile 提供 ink splash 容器
          SizedBox(
            width: 200,
            child: Material(
              color: Theme.of(context).canvasColor,
              child: ListView.builder(
                itemCount: _sections.length,
                itemBuilder: (context, index) {
                  final (icon, title) = _sections[index];
                  final selected = index == _selectedIndex;
                  return ListTile(
                    selected: selected,
                    leading: Icon(icon, size: 20),
                    title: Text(title, style: const TextStyle(fontSize: 13)),
                    dense: true,
                    onTap: () => setState(() => _selectedIndex = index),
                  );
                },
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          // 右侧内容 — Material 为 SwitchListTile 等提供 ink splash 容器
          Expanded(
            child: Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: _buildSection(_selectedIndex),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSection(int index) {
    return switch (index) {
      0 => _buildAppearanceSection(),
      1 => _buildThumbnailSection(),
      2 => _buildImportSection(),
      3 => _buildSearchSection(),
      4 => _buildBrowseSection(),
      5 => _buildPerformanceSection(),
      6 => _buildEditSection(),
      7 => _buildShortcutSection(),
      8 => _buildAboutSection(),
      _ => [],
    };
  }

  // ─── 外观 ───

  List<Widget> _buildAppearanceSection() {
    final settings = ref.watch(settingsProvider);
    return [
      _SectionHeader(title: AppStrings.settingsAppearance, subtitle: AppStrings.settingsAppearanceSub),
      _SettingGroup(title: '主题', children: [
        _DropdownSetting(
          label: '主题模式',
          value: settings.themeMode,
          options: const [
            ('dark', '深色'),
            ('light', '浅色'),
            ('system', '跟随系统'),
          ],
          onChanged: (v) => ref
              .read(settingsProvider.notifier)
              .update(SettingKeys.themeMode, v, group: 'appearance'),
        ),
      ]),
      _SettingGroup(title: '面板', children: [
        _SliderSetting(
          label: '左栏宽度',
          value: settings.leftPanelWidth,
          min: 150,
          max: 400,
          unit: 'px',
          onChanged: (v) => ref
              .read(settingsProvider.notifier)
              .update(SettingKeys.leftPanelWidth, v, group: 'appearance'),
        ),
        _SliderSetting(
          label: '右栏宽度',
          value: settings.rightPanelWidth,
          min: 200,
          max: 500,
          unit: 'px',
          onChanged: (v) => ref
              .read(settingsProvider.notifier)
              .update(SettingKeys.rightPanelWidth, v, group: 'appearance'),
        ),
      ]),
    ];
  }

  // ─── 缩略图与画质 ───

  List<Widget> _buildThumbnailSection() {
    final settings = ref.watch(settingsProvider);
    return [
      _SectionHeader(
        title: AppStrings.settingsThumbnails,
        subtitle: AppStrings.settingsThumbnailsSub,
      ),
      _SettingGroup(title: '缩略图尺寸', children: [
        _SliderSetting(
          label: '小尺寸（网格用）',
          value: settings.thumbnailSmallSize.toDouble(),
          min: 64,
          max: 256,
          unit: 'px',
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.thumbnailSmallSize, v.round(),
              group: 'thumbnail'),
        ),
        _SliderSetting(
          label: '中尺寸（预览用）',
          value: settings.thumbnailMediumSize.toDouble(),
          min: 256,
          max: 1024,
          unit: 'px',
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.thumbnailMediumSize, v.round(),
              group: 'thumbnail'),
        ),
        _SliderSetting(
          label: '全屏预览最大尺寸',
          value: settings.previewMaxSize.toDouble(),
          min: 512,
          max: 4096,
          unit: 'px',
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.previewMaxSize, v.round(),
              group: 'thumbnail'),
        ),
      ]),
      _SettingGroup(title: '缓存', children: [
        _SliderSetting(
          label: '缩略图缓存上限',
          value: settings.thumbnailCacheLimitMB.toDouble(),
          min: 512,
          max: 20480,
          unit: 'MB',
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.thumbnailCacheLimit, v.round(),
              group: 'thumbnail'),
        ),
        _SliderSetting(
          label: '网格预渲染范围',
          value: settings.gridCacheExtent.toDouble(),
          min: 250,
          max: 2000,
          unit: 'px',
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.gridCacheExtent, v.round(),
              group: 'thumbnail'),
        ),
        _SliderSetting(
          label: '缩略图生成并发数',
          value: settings.thumbnailConcurrency.toDouble(),
          min: 1,
          max: 16,
          unit: '',
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.thumbnailConcurrency, v.round(),
              group: 'thumbnail'),
        ),
      ]),
    ];
  }

  // ─── 导入 ───

  List<Widget> _buildImportSection() {
    final settings = ref.watch(settingsProvider);
    return [
      _SectionHeader(title: AppStrings.settingsImport, subtitle: AppStrings.settingsImportSub),
      _SettingGroup(title: '导入行为', children: [
        _SwitchSetting(
          label: '导入时自动生成缩略图',
          subtitle: '关闭则缩略图在浏览时按需生成（推荐）',
          value: settings.importAutoGenerateThumbs,
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.importAutoGenerateThumbs, v,
              group: 'import'),
        ),
        _SwitchSetting(
          label: '监听文件夹变更',
          subtitle: '实时检测新增/删除/移动的文件',
          value: settings.importWatchFolders,
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.importWatchFolders, v,
              group: 'import'),
        ),
        _SliderSetting(
          label: '最大文件大小',
          value: settings.maxFileSizeMB.toDouble(),
          min: 50,
          max: 2000,
          unit: 'MB',
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.maxFileSizeMB, v.round(),
              group: 'import'),
        ),
      ]),
      _SettingGroup(title: '并发控制', children: [
        _SliderSetting(
          label: 'EXIF 读取并发数',
          value: settings.importExifConcurrency.toDouble(),
          min: 1,
          max: 8,
          unit: '',
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.importExifConcurrency, v.round(),
              group: 'import'),
        ),
        _SliderSetting(
          label: '缩略图生成并发数（导入时）',
          value: settings.importThumbnailConcurrency.toDouble(),
          min: 1,
          max: 8,
          unit: '',
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.importThumbnailConcurrency, v.round(),
              group: 'import'),
        ),
      ]),
    ];
  }

  // ─── 搜索 ───

  List<Widget> _buildSearchSection() {
    final settings = ref.watch(settingsProvider);
    return [
      _SectionHeader(title: AppStrings.settingsSearch, subtitle: AppStrings.settingsSearchSub),
      _SettingGroup(title: '搜索延迟', children: [
        _SliderSetting(
          label: '搜索 Debounce 延迟',
          value: settings.searchDebounceMs.toDouble(),
          min: 0,
          max: 1000,
          unit: 'ms',
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.searchDebounceMs, v.round(),
              group: 'search'),
        ),
      ]),
      _SettingGroup(title: '搜索范围', children: [
        _SwitchSetting(
          label: '文件名',
          value: settings.searchScopeFileName,
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.searchScopeFileName, v,
              group: 'search'),
        ),
        _SwitchSetting(
          label: 'IPTC 标题',
          value: settings.searchScopeTitle,
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.searchScopeTitle, v,
              group: 'search'),
        ),
        _SwitchSetting(
          label: 'IPTC 描述',
          value: settings.searchScopeDescription,
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.searchScopeDescription, v,
              group: 'search'),
        ),
        _SwitchSetting(
          label: '相机型号',
          value: settings.searchScopeCamera,
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.searchScopeCamera, v,
              group: 'search'),
        ),
        _SwitchSetting(
          label: '关键词',
          value: settings.searchScopeKeywords,
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.searchScopeKeywords, v,
              group: 'search'),
        ),
      ]),
    ];
  }

  // ─── 浏览 ───

  List<Widget> _buildBrowseSection() {
    final settings = ref.watch(settingsProvider);
    return [
      _SectionHeader(title: AppStrings.settingsBrowse, subtitle: AppStrings.settingsBrowseSub),
      _SettingGroup(title: '默认视图', children: [
        _DropdownSetting(
          label: '默认视图模式',
          value: settings.defaultViewMode,
          options: const [
            ('grid', '网格视图'),
            ('list', '列表视图'),
          ],
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.defaultViewMode, v,
              group: 'browse'),
        ),
        _DropdownSetting(
          label: '默认缩略图尺寸',
          value: settings.defaultThumbSize,
          options: const [
            ('small', '小 (120px)'),
            ('medium', '中 (180px)'),
            ('large', '大 (260px)'),
          ],
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.defaultThumbSize, v,
              group: 'browse'),
        ),
      ]),
      _SettingGroup(title: '默认排序', children: [
        _DropdownSetting(
          label: '排序字段',
          value: settings.defaultSortBy,
          options: const [
            ('dateTaken', '拍摄日期'),
            ('importedAt', '导入日期'),
            ('rating', '星级'),
            ('fileName', '文件名'),
          ],
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.defaultSortBy, v,
              group: 'browse'),
        ),
        _SwitchSetting(
          label: '升序排列',
          value: settings.defaultAscending,
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.defaultAscending, v,
              group: 'browse'),
        ),
      ]),
    ];
  }

  // ─── 性能 ───

  List<Widget> _buildPerformanceSection() {
    final settings = ref.watch(settingsProvider);
    return [
      _SectionHeader(title: AppStrings.settingsPerformance, subtitle: AppStrings.settingsPerformanceSub),
      _SettingGroup(title: '图片缓存', children: [
        _SliderSetting(
          label: '图片缓存最大数量',
          value: settings.imageCacheMaxCount.toDouble(),
          min: 100,
          max: 10000,
          unit: '',
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.imageCacheMaxCount, v.round(),
              group: 'performance'),
        ),
        _SliderSetting(
          label: '图片缓存最大内存',
          value: settings.imageCacheMaxSizeMB.toDouble(),
          min: 100,
          max: 4096,
          unit: 'MB',
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.imageCacheMaxSizeMB, v.round(),
              group: 'performance'),
        ),
      ]),
      _SettingGroup(title: '数据加载', children: [
        _SliderSetting(
          label: '分页大小',
          value: settings.pageSize.toDouble(),
          min: 50,
          max: 1000,
          unit: '',
          onChanged: (v) => ref.read(settingsProvider.notifier).update(
              SettingKeys.pageSize, v.round(),
              group: 'performance'),
        ),
      ]),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          '提示：修改图片缓存设置需要重启应用才能生效。',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
      ),
    ];
  }

  // ─── 编辑 ───

  List<Widget> _buildEditSection() {
    final settings = ref.watch(settingsProvider);
    return [
      _SectionHeader(title: AppStrings.settingsEditing, subtitle: AppStrings.settingsEditingSub),
      _SettingGroup(title: '自动保存', children: [
        _SwitchSetting(
          label: '启用自动保存',
          subtitle: '编辑后自动保存到数据库',
          value: settings.editAutoSave,
          onChanged: (v) => ref.read(settingsProvider.notifier)
              .update(SettingKeys.editAutoSave, v, group: 'edit'),
        ),
        _SliderSetting(
          label: '防抖延迟',
          value: settings.editAutoSaveDebounceMs.toDouble(),
          min: 500,
          max: 5000,
          step: 500,
          unit: 'ms',
          onChanged: (v) => ref.read(settingsProvider.notifier)
              .update(SettingKeys.editAutoSaveDebounceMs, v.round(),
                  group: 'edit'),
        ),
        _SwitchSetting(
          label: '切换照片时自动保存',
          subtitle: '离开当前照片时自动保存未保存的编辑',
          value: settings.editAutoSaveOnSwitch,
          onChanged: (v) => ref.read(settingsProvider.notifier)
              .update(SettingKeys.editAutoSaveOnSwitch, v, group: 'edit'),
        ),
        _SwitchSetting(
          label: '关闭查看器时自动保存',
          subtitle: '退出全屏查看器时自动保存未保存的编辑',
          value: settings.editAutoSaveOnClose,
          onChanged: (v) => ref.read(settingsProvider.notifier)
              .update(SettingKeys.editAutoSaveOnClose, v, group: 'edit'),
        ),
      ]),
      _SettingGroup(title: '编辑历史', children: [
        _SwitchSetting(
          label: '启用操作历史记录',
          subtitle: '自动记录编辑操作，可回退到任意历史节点',
          value: settings.editHistoryEnabled,
          onChanged: (v) => ref.read(settingsProvider.notifier)
              .update(SettingKeys.editHistoryEnabled, v, group: 'edit'),
        ),
        _SliderSetting(
          label: '历史记录上限',
          value: settings.editHistoryMaxCount.toDouble(),
          min: 50,
          max: 500,
          step: 50,
          unit: '条',
          onChanged: (v) => ref.read(settingsProvider.notifier)
              .update(SettingKeys.editHistoryMaxCount, v.round(),
                  group: 'edit'),
        ),
      ]),
      // 自动调整/超分辨率设置已被临时禁用
    ];
  }

  // ─── 快捷键 ───

  List<Widget> _buildShortcutSection() {
    final settings = ref.watch(settingsProvider);
    final shortcutLabels = const [
      (SettingKeys.shortcutRate0, '清除评分'),
      (SettingKeys.shortcutRate1, '1 星'),
      (SettingKeys.shortcutRate2, '2 星'),
      (SettingKeys.shortcutRate3, '3 星'),
      (SettingKeys.shortcutRate4, '4 星'),
      (SettingKeys.shortcutRate5, '5 星'),
      (SettingKeys.shortcutPick, 'Pick'),
      (SettingKeys.shortcutUnpick, 'Unpick'),
      (SettingKeys.shortcutReject, 'Reject'),
      (SettingKeys.shortcutColor1, '色标: 红'),
      (SettingKeys.shortcutColor2, '色标: 黄'),
      (SettingKeys.shortcutColor3, '色标: 绿'),
      (SettingKeys.shortcutColor4, '色标: 蓝'),
      (SettingKeys.shortcutColor5, '色标: 紫'),
      (SettingKeys.shortcutColor6, '色标: 灰'),
      (SettingKeys.shortcutClearColor, '清除色标'),
      (SettingKeys.shortcutFullscreen, '全屏查看'),
      (SettingKeys.shortcutImport, '导入文件夹'),
      (SettingKeys.shortcutSearch, '搜索'),
      (SettingKeys.shortcutToggleView, '切换网格/列表'),
      (SettingKeys.shortcutSelectAll, '全选'),
      (SettingKeys.shortcutDeselect, '取消选择'),
      (SettingKeys.shortcutToggleLeftPanel, '切换左栏'),
      (SettingKeys.shortcutToggleRightPanel, '切换右栏'),
      (SettingKeys.shortcutToggleFilterBar, '切换筛选栏'),
    ];

    return [
      _SectionHeader(title: '快捷键', subtitle: '自定义键盘快捷键映射'),
      _SettingGroup(title: '分类操作', children: [
        for (final (key, label) in shortcutLabels.take(16))
          _ShortcutSetting(
            label: label,
            value: settings.shortcuts[key] ?? '',
            onTap: () => _editShortcut(key, label),
          ),
      ]),
      _SettingGroup(title: '导航与视图', children: [
        for (final (key, label) in shortcutLabels.skip(16))
          _ShortcutSetting(
            label: label,
            value: settings.shortcuts[key] ?? '',
            onTap: () => _editShortcut(key, label),
          ),
      ]),
    ];
  }

  void _editShortcut(String key, String label) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _ShortcutEditDialog(label: label),
    );
    if (result != null) {
      await ref.read(settingsProvider.notifier).updateShortcut(key, result);
    }
  }

  // ─── About ───

  List<Widget> _buildAboutSection() {
    return [
      _SectionHeader(title: AppStrings.settingsAbout, subtitle: AppStrings.settingsAboutSub),
      _SettingGroup(title: AppStrings.settingsAppInfo, children: [
        _InfoRow(AppStrings.settingsLabelName, AppStrings.appName),
        _InfoRow(AppStrings.settingsLabelVersion, AppStrings.appVersion),
        _InfoRow(AppStrings.settingsLabelDescription, AppStrings.appDescription),
        _InfoRow(AppStrings.settingsLabelLicense, AppStrings.appLicense),
        _InfoRow(AppStrings.settingsLabelFramework, AppStrings.appFramework),
      ]),
      const SizedBox(height: 24),
      Center(
        child: Text(
          '© 2026 Spectra Project',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
      ),
    ];
  }

  // ─── 重置确认 ───

  void _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.settingsResetConfirmTitle),
        content: const Text(AppStrings.settingsResetConfirmMsg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStrings.settingsReset),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(settingsProvider.notifier).resetAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('${AppStrings.settingsReset}: ${AppStrings.ok}')),
        );
      }
    }
  }
}

// ─── 通用组件 ───

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.secondary,
              )),
        ],
      ),
    );
  }
}

class _SettingGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double? step;
  final String unit;
  final ValueChanged<double> onChanged;

  const _SliderSetting({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.step,
    required this.unit,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 13)),
              Text(
                unit.isEmpty
                    ? value.round().toString()
                    : '${value.round()} $unit',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: step != null
                ? ((max - min) / step!).round()
                : ((max - min) / 10).round().clamp(1, 200),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SwitchSetting extends StatelessWidget {
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchSetting({
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(label, style: const TextStyle(fontSize: 13)),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.secondary,
              ))
          : null,
      value: value,
      onChanged: onChanged,
      dense: true,
    );
  }
}

class _DropdownSetting extends StatelessWidget {
  final String label;
  final String value;
  final List<(String, String)> options;
  final ValueChanged<String> onChanged;

  const _DropdownSetting({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          DropdownButton<String>(
            value: value,
            items: options
                .map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2)))
                .toList(),
            onChanged: (v) => onChanged(v!),
            isDense: true,
          ),
        ],
      ),
    );
  }
}

class _ShortcutSetting extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _ShortcutSetting({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontSize: 13)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Text(
          value.isEmpty ? '未设置' : value,
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            color: value.isEmpty
                ? Theme.of(context).colorScheme.secondary
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
      onTap: onTap,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// 快捷键编辑对话框 — 按下按键捕获
class _ShortcutEditDialog extends StatefulWidget {
  final String label;

  const _ShortcutEditDialog({required this.label});

  @override
  State<_ShortcutEditDialog> createState() => _ShortcutEditDialogState();
}

class _ShortcutEditDialogState extends State<_ShortcutEditDialog> {
  String _captured = '';
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  String _keyLabel(LogicalKeyboardKey key) {
    // 修饰键
    if (key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight) return 'Ctrl';
    if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) return 'Shift';
    if (key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight) return 'Alt';

    // 功能键
    if (key == LogicalKeyboardKey.f1) return 'F1';
    if (key == LogicalKeyboardKey.f2) return 'F2';
    if (key == LogicalKeyboardKey.f3) return 'F3';
    if (key == LogicalKeyboardKey.f4) return 'F4';
    if (key == LogicalKeyboardKey.f5) return 'F5';
    if (key == LogicalKeyboardKey.f6) return 'F6';
    if (key == LogicalKeyboardKey.f7) return 'F7';
    if (key == LogicalKeyboardKey.f8) return 'F8';
    if (key == LogicalKeyboardKey.f9) return 'F9';
    if (key == LogicalKeyboardKey.f10) return 'F10';
    if (key == LogicalKeyboardKey.f11) return 'F11';
    if (key == LogicalKeyboardKey.f12) return 'F12';

    // 特殊键
    if (key == LogicalKeyboardKey.escape) return 'Esc';
    if (key == LogicalKeyboardKey.enter) return 'Enter';
    if (key == LogicalKeyboardKey.space) return 'Space';
    if (key == LogicalKeyboardKey.tab) return 'Tab';
    if (key == LogicalKeyboardKey.arrowLeft) return '←';
    if (key == LogicalKeyboardKey.arrowRight) return '→';
    if (key == LogicalKeyboardKey.arrowUp) return '↑';
    if (key == LogicalKeyboardKey.arrowDown) return '↓';

    // 字母和数字
    final label = key.keyLabel;
    if (label.length == 1) return label.toUpperCase();
    return label;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${AppStrings.shortcutSetFor} ${widget.label}'),
      content: SizedBox(
        height: 120,
        child: Column(
          children: [
            const Text(AppStrings.shortcutPressKeys),
            const SizedBox(height: 16),
            KeyboardListener(
              focusNode: _focusNode,
              autofocus: true,
              onKeyEvent: (event) {
                if (event is KeyDownEvent) {
                  final parts = <String>[];
                  if (HardwareKeyboard.instance.isControlPressed) {
                    parts.add('Ctrl');
                  }
                  if (HardwareKeyboard.instance.isShiftPressed) {
                    parts.add('Shift');
                  }
                  if (HardwareKeyboard.instance.isAltPressed) {
                    parts.add('Alt');
                  }
                  final keyLabel = _keyLabel(event.logicalKey);
                  // 不把修饰键本身作为最终键
                  if (keyLabel != 'Ctrl' &&
                      keyLabel != 'Shift' &&
                      keyLabel != 'Alt') {
                    parts.add(keyLabel);
                    setState(() {
                      _captured = parts.join('+');
                    });
                  }
                }
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Center(
                  child: Text(
                    _captured.isEmpty ? AppStrings.shortcutWaiting : _captured,
                    style: TextStyle(
                      fontSize: 18,
                      fontFamily: 'monospace',
                      color: _captured.isEmpty
                          ? Theme.of(context).colorScheme.secondary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.cancel),
        ),
        TextButton(
          onPressed: _captured.isEmpty
              ? null
              : () => Navigator.of(context).pop(_captured),
          child: const Text(AppStrings.ok),
        ),
      ],
    );
  }
}