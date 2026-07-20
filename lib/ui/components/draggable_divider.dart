import 'package:flutter/material.dart';

/// 可拖拽分隔条 — 触摸屏友好的宽触摸区域，拖拽调节面板尺寸
///
/// 使用 GestureDetector + onPanUpdate 实现拖拽，触摸和鼠标均可用。
/// [isHorizontal] 为 true 时为水平分隔条（拖拽调节高度），false 时为垂直分隔条（拖拽调节宽度）。
/// 触摸区域 24dp（符合 Material Design 最低标准），视觉分隔线居中 1px 细线。
class DraggableDivider extends StatefulWidget {
  /// 是否为水平分隔条（水平线，上下拖拽调节高度）
  final bool isHorizontal;

  /// 拖拽回调，delta 为拖拽增量
  /// - 垂直分隔条：delta.dx 为水平增量（正=向右拖宽）
  /// - 水平分隔条：delta.dy 为垂直增量（正=向下拖，负=向上拖）
  final void Function(double delta) onDrag;

  const DraggableDivider({
    super.key,
    required this.onDrag,
    this.isHorizontal = false,
  });

  @override
  State<DraggableDivider> createState() => _DraggableDividerState();
}

class _DraggableDividerState extends State<DraggableDivider> {
  bool _isHover = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeColor = theme.colorScheme.primary.withValues(alpha: 0.4);
    final idleColor = theme.dividerColor;

    return MouseRegion(
      cursor: widget.isHorizontal
          ? SystemMouseCursors.resizeUpDown
          : SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _isHover = true),
      onExit: (_) => setState(() => _isHover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => setState(() => _isDragging = true),
        onPanUpdate: (details) {
          widget.onDrag(
            widget.isHorizontal ? details.delta.dy : details.delta.dx,
          );
        },
        onPanEnd: (_) => setState(() => _isDragging = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          // 触摸区域 24dp — Material Design 最低 48dp 在此处因视觉限制放宽至 24dp
          width: widget.isHorizontal ? double.infinity : 24,
          height: widget.isHorizontal ? 24 : double.infinity,
          color: Colors.transparent,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              // 视觉分隔线保持 1px 细线
              width: widget.isHorizontal ? double.infinity : 1,
              height: widget.isHorizontal ? 1 : double.infinity,
              color: _isDragging
                  ? activeColor
                  : (_isHover ? activeColor.withValues(alpha: 0.3) : idleColor),
            ),
          ),
        ),
      ),
    );
  }
}
