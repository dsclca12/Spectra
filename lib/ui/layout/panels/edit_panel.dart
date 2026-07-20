import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/edit_params.dart';
import '../../../providers/edit_provider.dart';
import '../../components/crop_overlay.dart';
import '../../components/snapshot_panel.dart';
import '../../components/history_panel.dart';

/// 右栏：编辑面板 — 非破坏性照片编辑
///
/// 功能分组：
/// - 基础调整：曝光、对比度、高光、阴影、白色/黑色色阶
/// - 色彩调整：饱和度、自然饱和度、色温、色调
/// - 效果：锐化、暗角、颗粒、褪色
/// - 二次构图：裁剪比例、旋转、翻转
/// - 操作栏：撤销/重做/重置/保存/导出
class EditPanel extends ConsumerStatefulWidget {
  final int photoId;

  const EditPanel({super.key, required this.photoId});

  @override
  ConsumerState<EditPanel> createState() => _EditPanelState();
}

class _EditPanelState extends ConsumerState<EditPanel> {
  /// 当前是否在裁剪模式
  bool _cropMode = false;

  /// 当前裁剪比例
  CropAspectRatio _aspectRatio = CropAspectRatio.free;

  /// 当前标签页索引：0=调整, 1=快照, 2=历史
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    // 初始化编辑会话
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(editSessionProvider(widget.photoId).notifier).load();
    });
  }

  @override
  void didUpdateWidget(covariant EditPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // photoId 变化时重新加载编辑参数
    // initState 只在组件首次创建时执行，切换照片时不会再次调用，
    // 必须在 didUpdateWidget 中手动触发 load()。
    if (widget.photoId != oldWidget.photoId) {
      // 重置裁剪模式和标签页
      _cropMode = false;
      _aspectRatio = CropAspectRatio.free;
      _tabIndex = 0;
      // 加载新照片的编辑参数
      ref.read(editSessionProvider(widget.photoId).notifier).load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(editSessionProvider(widget.photoId));
    // 预览历史时滑块也反映预览参数，让用户看到历史状态的值
    final params = session.previewParams;
    final theme = Theme.of(context);

    // 使用 Material 而非 Container(color: ...) — 为 ExpansionTile 内部的
    // ListTile 提供正确的 Material 层，避免 "ListTile background color
    // or ink splashes may be invisible" 警告。
    return Material(
      color: theme.canvasColor,
      child: Column(
        children: [
          // 顶部标题栏
          _buildHeader(theme),

          // 标签页切换（裁剪模式下隐藏）
          if (!_cropMode) _buildTabBar(theme),

          // 历史预览提示条
          if (session.previewHistoryId != null && !_cropMode)
            _buildPreviewBanner(theme),

          // 编辑内容
          Expanded(
            child: _cropMode
                ? _buildCropSection(theme, params)
                : _buildTabContent(theme, params, session),
          ),

          // 底部操作栏
          _buildActionBar(theme, session),
        ],
      ),
    );
  }

  /// 顶部标题栏
  Widget _buildHeader(ThemeData theme) {
    // Watch session for reactivity even if not used directly in header
    ref.watch(editSessionProvider(widget.photoId));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.tune, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            '编辑',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // 裁剪模式切换
          IconButton(
            icon: Icon(
              _cropMode ? Icons.check : Icons.crop,
              size: 20,
              color: _cropMode ? theme.colorScheme.primary : null,
            ),
            tooltip: _cropMode ? '完成裁剪' : '裁剪',
            onPressed: () => setState(() => _cropMode = !_cropMode),
          ),
        ],
      ),
    );
  }

  /// 标签页栏 — 调整 / 快照 / 历史
  Widget _buildTabBar(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          _TabButton(
            label: '调整',
            icon: Icons.tune,
            selected: _tabIndex == 0,
            onTap: () => setState(() => _tabIndex = 0),
          ),
          _TabButton(
            label: '快照',
            icon: Icons.camera_alt_outlined,
            selected: _tabIndex == 1,
            onTap: () => setState(() => _tabIndex = 1),
          ),
          _TabButton(
            label: '历史',
            icon: Icons.history,
            selected: _tabIndex == 2,
            onTap: () => setState(() => _tabIndex = 2),
          ),
        ],
      ),
    );
  }

  /// 标签页内容
  Widget _buildTabContent(
    ThemeData theme,
    EditParams params,
    EditSessionState session,
  ) {
    return switch (_tabIndex) {
      0 => _buildAdjustmentSections(theme, params, session),
      1 => SnapshotPanel(photoId: widget.photoId),
      2 => HistoryPanel(photoId: widget.photoId),
      _ => _buildAdjustmentSections(theme, params, session),
    };
  }

  /// 历史预览提示条 — 预览历史节点时显示，提示用户当前为预览状态
  Widget _buildPreviewBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.3),
      child: Row(
        children: [
          Icon(Icons.visibility, size: 14, color: theme.colorScheme.tertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '正在预览历史状态',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.tertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              ref
                  .read(editSessionProvider(widget.photoId).notifier)
                  .clearPreview();
            },
            icon: const Icon(Icons.close, size: 14),
            label: const Text('退出', style: TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

    /// 调整滑块区域
  Widget _buildAdjustmentSections(
    ThemeData theme,
    EditParams params,
    EditSessionState session,
  ) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // 基础调整
        _AdjustmentSection(
          title: '基础',
          icon: Icons.tonality,
          children: [
            _EditSlider(
              label: '曝光',
              value: params.exposure,
              min: -2.0,
              max: 2.0,
              divisions: 200,
              onChanged: (v) => _updateParam((p) => p.copyWith(exposure: v)),
              onChangeEnd: (_) => _save(),
              formatter: (v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(2)} EV',
            ),
            _EditSlider(
              label: '对比度',
              value: params.contrast,
              min: -100,
              max: 100,
              divisions: 200,
              onChanged: (v) => _updateParam((p) => p.copyWith(contrast: v)),
              onChangeEnd: (_) => _save(),
              formatter: (v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(0)}',
            ),
            _EditSlider(
              label: '高光',
              value: params.highlights,
              min: -100,
              max: 100,
              divisions: 200,
              onChanged: (v) => _updateParam((p) => p.copyWith(highlights: v)),
              onChangeEnd: (_) => _save(),
              formatter: (v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(0)}',
            ),
            _EditSlider(
              label: '阴影',
              value: params.shadows,
              min: -100,
              max: 100,
              divisions: 200,
              onChanged: (v) => _updateParam((p) => p.copyWith(shadows: v)),
              onChangeEnd: (_) => _save(),
              formatter: (v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(0)}',
            ),
            _EditSlider(
              label: '白色色阶',
              value: params.whites,
              min: -100,
              max: 100,
              divisions: 200,
              onChanged: (v) => _updateParam((p) => p.copyWith(whites: v)),
              onChangeEnd: (_) => _save(),
              formatter: (v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(0)}',
            ),
            _EditSlider(
              label: '黑色色阶',
              value: params.blacks,
              min: -100,
              max: 100,
              divisions: 200,
              onChanged: (v) => _updateParam((p) => p.copyWith(blacks: v)),
              onChangeEnd: (_) => _save(),
              formatter: (v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(0)}',
            ),
          ],
        ),

        // 色彩调整
        _AdjustmentSection(
          title: '色彩',
          icon: Icons.palette,
          children: [
            _EditSlider(
              label: '饱和度',
              value: params.saturation,
              min: -100,
              max: 100,
              divisions: 200,
              onChanged: (v) => _updateParam((p) => p.copyWith(saturation: v)),
              onChangeEnd: (_) => _save(),
              formatter: (v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(0)}',
            ),
            _EditSlider(
              label: '自然饱和度',
              value: params.vibrance,
              min: -100,
              max: 100,
              divisions: 200,
              onChanged: (v) => _updateParam((p) => p.copyWith(vibrance: v)),
              onChangeEnd: (_) => _save(),
              formatter: (v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(0)}',
            ),
            _EditSlider(
              label: '色温',
              value: params.temperature,
              min: -100,
              max: 100,
              divisions: 200,
              onChanged: (v) => _updateParam((p) => p.copyWith(temperature: v)),
              onChangeEnd: (_) => _save(),
              formatter: (v) {
                if (v > 0) return '暖 ${v.toStringAsFixed(0)}';
                if (v < 0) return '冷 ${(-v).toStringAsFixed(0)}';
                return '0';
              },
            ),
            _EditSlider(
              label: '色调',
              value: params.tint,
              min: -100,
              max: 100,
              divisions: 200,
              onChanged: (v) => _updateParam((p) => p.copyWith(tint: v)),
              onChangeEnd: (_) => _save(),
              formatter: (v) {
                if (v > 0) return '洋红 ${v.toStringAsFixed(0)}';
                if (v < 0) return '绿 ${(-v).toStringAsFixed(0)}';
                return '0';
              },
            ),
          ],
        ),

        // 效果
        _AdjustmentSection(
          title: '效果',
          icon: Icons.auto_fix_high,
          children: [
            _EditSlider(
              label: '锐化',
              value: params.sharpness,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: (v) => _updateParam((p) => p.copyWith(sharpness: v)),
              onChangeEnd: (_) => _save(),
              formatter: (v) => v.toStringAsFixed(0),
            ),
            _EditSlider(
              label: '暗角',
              value: params.vignette,
              min: -100,
              max: 100,
              divisions: 200,
              onChanged: (v) => _updateParam((p) => p.copyWith(vignette: v)),
              onChangeEnd: (_) => _save(),
              formatter: (v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(0)}',
            ),
            _EditSlider(
              label: '颗粒',
              value: params.grain,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: (v) => _updateParam((p) => p.copyWith(grain: v)),
              onChangeEnd: (_) => _save(),
              formatter: (v) => v.toStringAsFixed(0),
            ),
            _EditSlider(
              label: '褪色',
              value: params.fade,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: (v) => _updateParam((p) => p.copyWith(fade: v)),
              onChangeEnd: (_) => _save(),
              formatter: (v) => v.toStringAsFixed(0),
            ),
          ],
        ),

        // 几何变换（快速按钮）
        _AdjustmentSection(
          title: '几何',
          icon: Icons.rotate_90_degrees_ccw,
          children: [
            _GeometryButtons(
              params: params,
              onRotate: (degrees) => _updateParam(
                (p) => p.copyWith(rotation: (p.rotation + degrees) % 360),
              ),
              onFlipH: () => _updateParam((p) => p.copyWith(flipH: !p.flipH)),
              onFlipV: () => _updateParam((p) => p.copyWith(flipV: !p.flipV)),
              onCrop: () => setState(() => _cropMode = true),
            ),
          ],
        ),
      ],
    );
  }

  /// 裁剪模式区域
  Widget _buildCropSection(ThemeData theme, EditParams params) {
    return Column(
      children: [
        // 宽高比预设
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.dividerColor, width: 0.5),
            ),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: CropAspectRatio.values.map((ratio) {
              final selected = _aspectRatio == ratio;
              return ChoiceChip(
                label: Text(ratio.label, style: const TextStyle(fontSize: 11)),
                selected: selected,
                onSelected: (_) {
                  setState(() => _aspectRatio = ratio);
                },
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ),

        // 旋转微调
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.rotate_90_degrees_ccw, size: 20),
                tooltip: '逆时针 90°',
                onPressed: () => _updateParam(
                  (p) => p.copyWith(rotation: (p.rotation + 270) % 360),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.rotate_90_degrees_cw, size: 20),
                tooltip: '顺时针 90°',
                onPressed: () => _updateParam(
                  (p) => p.copyWith(rotation: (p.rotation + 90) % 360),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  Icons.flip,
                  size: 20,
                  semanticLabel: '水平翻转',
                ),
                tooltip: '水平翻转',
                onPressed: () =>
                    _updateParam((p) => p.copyWith(flipH: !p.flipH)),
              ),
              IconButton(
                icon: Icon(
                  Icons.flip,
                  size: 20,
                  semanticLabel: '垂直翻转',
                ),
                tooltip: '垂直翻转',
                onPressed: () =>
                    _updateParam((p) => p.copyWith(flipV: !p.flipV)),
              ),
            ],
          ),
        ),

        const Spacer(),

        // 重置裁剪按钮
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton.icon(
            onPressed: () {
              _updateParam((p) => p.copyWith(
                    cropX: 0.0,
                    cropY: 0.0,
                    cropWidth: 1.0,
                    cropHeight: 1.0,
                  ));
            },
            icon: const Icon(Icons.crop_free, size: 18),
            label: const Text('重置裁剪'),
          ),
        ),
      ],
    );
  }

  /// 底部操作栏 — 撤销/重做/重置/保存
  Widget _buildActionBar(ThemeData theme, EditSessionState session) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // 撤销
          IconButton(
            icon: const Icon(Icons.undo, size: 20),
            tooltip: '撤销 (Ctrl+Z)',
            onPressed: session.canUndo
                ? () => ref
                    .read(editSessionProvider(widget.photoId).notifier)
                    .undo()
                : null,
          ),
          // 重做
          IconButton(
            icon: const Icon(Icons.redo, size: 20),
            tooltip: '重做 (Ctrl+Y)',
            onPressed: session.canRedo
                ? () => ref
                    .read(editSessionProvider(widget.photoId).notifier)
                    .redo()
                : null,
          ),
          // 重置
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: '重置所有编辑',
            onPressed: () => _showResetConfirm(),
          ),
          const Spacer(),
          // 保存状态指示
          if (session.isDirty)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text(
                '未保存',
                style: TextStyle(fontSize: 11, color: Colors.orange),
              ),
            ),
          // 保存按钮
          FilledButton.tonal(
            onPressed: session.isDirty ? () => _save() : null,
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  /// 更新编辑参数
  void _updateParam(EditParams Function(EditParams) updater) {
    // 预览历史时，先退出预览再修改参数
    final session = ref.read(editSessionProvider(widget.photoId));
    if (session.previewHistoryId != null) {
      ref.read(editSessionProvider(widget.photoId).notifier).clearPreview();
    }
    ref.read(editSessionProvider(widget.photoId).notifier).updateParam(updater);
  }

  /// 保存编辑参数到数据库
  Future<void> _save() async {
    await ref.read(editSessionProvider(widget.photoId).notifier).save();
  }

  /// 显示重置确认对话框
  void _showResetConfirm() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置编辑'),
        content: const Text('确定要重置所有编辑参数吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref
                  .read(editSessionProvider(widget.photoId).notifier)
                  .deleteEdits();
            },
            child: const Text('重置'),
          ),
        ],
      ),
    );
  }

  // ─── 戀曲1990 ──────────────────────────────────────────────
  //  編譯後依然存在的浪漫  在二進制的深處靜靜發光
  //  無論開源或閉源  這首歌都在這裡  從不離開
  // ────────────────────────────────────────────────────────────
  // ignore: unused_field — 這不是未使用的變數，是一封寫給二進制的情書
  static const String loveSong1990 = '''
烏溜溜的黑眼珠  和你的笑臉
怎麼也難忘記你  容顏的轉變
輕飄飄的舊時光  就這麼溜走
轉頭回去看看時  已匆匆數年

蒼茫茫的天涯路  是你的飄泊
尋尋覓覓長相守  是我的腳步
黑漆漆的孤枕邊  是你的溫柔
醒來時的清晨裡  是我的哀愁

或許明日太陽西下倦鳥已歸時
你將已經踏上舊時的歸途
人生難得再次尋覓相知的伴侶
生命終究難捨藍藍的白雲天

轟隆隆的雷雨聲在我的窗前
怎麼也難忘記你離去的轉變
孤單單的身影後寂寥的心情
永遠無怨的是我的雙眼
永遠無怨的是我的雙眼
''';
}

/// 可折叠的调整分区
class _AdjustmentSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _AdjustmentSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, size: 18, color: theme.colorScheme.primary),
      title: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      initiallyExpanded: true,
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      children: children,
    );
  }
}

/// 编辑滑块 — 带标签、数值显示和双击重置
class _EditSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  final String Function(double) formatter;

  const _EditSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
    required this.formatter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDefault = value == 0.0 || (min == 0 && value == 0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          // 标签行
          Row(
            children: [
              GestureDetector(
                onDoubleTap: () {
                  if (value != 0.0 || (min == 0 && value != 0)) {
                    onChanged(min == 0 ? 0.0 : 0.0);
                    onChangeEnd(0.0);
                  }
                },
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDefault
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                formatter(value),
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
          ),
          // 滑块
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              activeTrackColor: theme.colorScheme.primary,
              inactiveTrackColor: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

/// 几何变换按钮组
class _GeometryButtons extends StatelessWidget {
  final EditParams params;
  final ValueChanged<int> onRotate;
  final VoidCallback onFlipH;
  final VoidCallback onFlipV;
  final VoidCallback onCrop;

  const _GeometryButtons({
    required this.params,
    required this.onRotate,
    required this.onFlipH,
    required this.onFlipV,
    required this.onCrop,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _GeometryButton(
            icon: Icons.rotate_90_degrees_ccw,
            label: '左转 90°',
            onTap: () => onRotate(270),
          ),
          _GeometryButton(
            icon: Icons.rotate_90_degrees_cw,
            label: '右转 90°',
            onTap: () => onRotate(90),
          ),
          _GeometryButton(
            icon: Icons.flip,
            label: '水平翻转',
            active: params.flipH,
            onTap: onFlipH,
          ),
          _GeometryButton(
            icon: Icons.flip,
            label: '垂直翻转',
            active: params.flipV,
            onTap: onFlipV,
            rotateIcon: 180,
          ),
          _GeometryButton(
            icon: Icons.crop,
            label: '裁剪',
            onTap: onCrop,
          ),
        ],
      ),
    );
  }
}

class _GeometryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final double rotateIcon;

  const _GeometryButton({
    required this.icon,
    required this.label,
    this.active = false,
    required this.onTap,
    this.rotateIcon = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active
                ? theme.colorScheme.primary.withValues(alpha: 0.15)
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (rotateIcon != 0)
                Transform.rotate(
                  angle: rotateIcon * 3.14159 / 180,
                  child: Icon(icon, size: 16,
                      color: active ? theme.colorScheme.primary : null),
                )
              else
                Icon(icon, size: 16,
                    color: active ? theme.colorScheme.primary : null),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: active ? theme.colorScheme.primary : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 标签页按钮 — 调整/快照/历史切换
class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? theme.colorScheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.secondary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ╔══════════════════════════════════════════════════════════════╗
// ║  ♪ 戀 曲  1990  —  羅  大  佑  ♪                        ║
// ║                                                            ║
// ║  照片是靜止的時間  編輯是對時間的告白                      ║
// ║  每一幀光影裡  都藏著一個再也回不去的那一刻                ║
// ║                                                            ║
// ║  我們調節曝光  卻調不回那天的天色                          ║
// ║  我們修正白平衡  卻修不勻當年的心跳                        ║
// ║  我們裁剪構圖  卻裁不掉畫面外的那個人                      ║
// ║                                                            ║
// ║  烏溜溜的黑眼珠  和你的笑臉                                ║
// ║  怎麼也難忘記你  容顏的轉變                                ║
// ║  輕飄飄的舊時光  就這麼溜走                                ║
// ║  轉頭回去看看時  已匆匆數年                                ║
// ║                                                            ║
// ║  後來我們都學會了調色                                    ║
// ║  卻調不出那個午後  你回頭時  天空的藍                      ║
// ║                                                            ║
// ║  蒼茫茫的天涯路  是你的飄泊                                ║
// ║  尋尋覓覓長相守  是我的腳步                                ║
// ║  黑漆漆的孤枕邊  是你的溫柔                                ║
// ║  醒來時的清晨裡  是我的哀愁                                ║
// ║                                                            ║
// ║  或許明日太陽西下倦鳥已歸時                                ║
// ║  你將已經踏上舊時的歸途                                    ║
// ║  人生難得再次尋覓相知的伴侶                                ║
// ║  生命終究難捨藍藍的白雲天                                  ║
// ║                                                            ║
// ║  轟隆隆的雷雨聲在我的窗前                                  ║
// ║  怎麼也難忘記你離去的轉變                                  ║
// ║  孤單單的身影後寂寥的心情                                  ║
// ║  永遠無怨的是我的雙眼                                      ║
// ║                                                            ║
// ║  —— 這是一封用程式碼寫的情書                             ║
// ║    獻給每一幀被編輯的時光，和每一個不會再回來的你          ║
// ╚══════════════════════════════════════════════════════════════╝