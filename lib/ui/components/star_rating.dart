import 'package:flutter/material.dart';

/// 评分组件 — 暗部胶囊滑条，带档位刻度
///
/// 外观：深色圆角胶囊轨道，等距分段竖线标记每个档位，
/// 琥珀色光条从左填充至当前档位，底部标注档位数字 1~5。
/// 触摸屏友好：整个胶囊高度作为触摸目标，手指可水平拖拽滑选或点击设分。
class StarRating extends StatefulWidget {
  final int rating;
  final int maxRating;
  final double starSize;
  final ValueChanged<int> onChanged;
  final bool interactive;

  const StarRating({
    super.key,
    required this.rating,
    this.maxRating = 5,
    this.starSize = 16,
    required this.onChanged,
    this.interactive = true,
  });

  @override
  State<StarRating> createState() => _StarRatingState();
}

class _StarRatingState extends State<StarRating> {
  int? _dragRating;

  /// 轨道条宽度（不含右侧数字徽章）
  double get _barW => widget.maxRating * widget.starSize * 1.9;

  double _ratioFromX(double globalX, RenderBox box) {
    final local = box.globalToLocal(Offset(globalX, 0));
    // 使用轨道条宽度而非整个组件宽度（排除右侧徽章干扰）
    return (local.dx / _barW).clamp(0.0, 1.0);
  }

  int _ratingFromRatio(double ratio) {
    return (ratio * widget.maxRating).ceil().clamp(1, widget.maxRating);
  }

  void _commit(int value) {
    widget.onChanged(value == widget.rating ? 0 : value);
  }

  void _onDragStart(DragStartDetails d) {
    final box = context.findRenderObject() as RenderBox;
    setState(() {
      _dragRating = _ratingFromRatio(_ratioFromX(d.globalPosition.dx, box));
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final box = context.findRenderObject() as RenderBox;
    setState(() {
      _dragRating = _ratingFromRatio(_ratioFromX(d.globalPosition.dx, box));
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dragRating != null) {
      _commit(_dragRating!);
    }
    setState(() => _dragRating = null);
  }

  void _onTapDown(TapDownDetails d) {
    final box = context.findRenderObject() as RenderBox;
    _commit(_ratingFromRatio(_ratioFromX(d.globalPosition.dx, box)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final currentRating = _dragRating ?? widget.rating;
    final displayRatio = currentRating / widget.maxRating;

    // ── 尺寸 ──
    final barH = (widget.starSize * 0.62).clamp(8.0, 22.0);
    final labelFontSize = (widget.starSize * 0.48).clamp(9.0, 15.0);
    final labelSpacing = 3.0;
    final labelBoxH = labelFontSize * 1.5;
    final outerH = barH + labelSpacing + labelBoxH;
    // 每段宽度
    final barW = widget.maxRating * widget.starSize * 1.9;
    final segGap = (barH * 0.2).clamp(2.0, 4.0);

    // 右侧数字徽章尺寸
    final badgeW = barH * 1.6;
    final badgeFontSize = barH * 0.7;
    final badgeGap = barH * 0.3;

    final totalW = barW + badgeGap + badgeW;

    final trackColor = theme.brightness == Brightness.dark
        ? const Color(0xFF2A2A2E)
        : const Color(0xFFE0E0E0);

    const amberColors = [
      Color(0xFFFFB900),
      Color(0xFFFF8C00),
    ];

    final isMuted = !widget.interactive || widget.rating == 0;

    final Widget bar = _SegmentedTrack(
      barW: barW,
      barH: barH,
      segGap: segGap,
      trackColor: trackColor,
      displayRatio: displayRatio,
      maxRating: widget.maxRating,
      amberColors: amberColors,
      isMuted: isMuted,
    );

    // 右侧数字徽章
    final Widget badge = Container(
      width: badgeW,
      height: barH,
      decoration: BoxDecoration(
        color: currentRating > 0
            ? const Color(0xFFFFB900)
            : trackColor,
        borderRadius: BorderRadius.circular(barH * 0.3),
        boxShadow: currentRating > 0
            ? [
                BoxShadow(
                  color: const Color(0xFFFFB900).withValues(alpha: 0.3),
                  blurRadius: barH * 0.4,
                ),
              ]
            : null,
      ),
      child: Center(
        child: Text(
          '$currentRating',
          style: TextStyle(
            fontSize: badgeFontSize,
            fontWeight: FontWeight.w700,
            height: 1.0,
            color: currentRating > 0 ? Colors.black : theme.colorScheme.onSurface.withValues(alpha: 0.25),
          ),
        ),
      ),
    );

    final Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            bar,
            SizedBox(height: labelSpacing),
            // 档位标签 1 2 3 4 5
            SizedBox(
              width: barW,
              height: labelBoxH,
              child: Row(
                children: List.generate(widget.maxRating, (i) {
                  final active = (i + 1) <= currentRating;
                  return SizedBox(
                    width: barW / widget.maxRating,
                    child: Center(
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: labelFontSize,
                          fontWeight: FontWeight.w600,
                          height: 1.0,
                          color: active
                              ? const Color(0xFFFFB900)
                              : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
        // 数字徽章 — 与 bar 底对齐
        SizedBox(width: badgeGap),
        Padding(
          padding: EdgeInsets.only(bottom: labelSpacing + labelBoxH),
          child: badge,
        ),
      ],
    );

    final Widget result = SizedBox(width: totalW, height: outerH, child: row);

    if (!widget.interactive) return result;

    return GestureDetector(
      onTapDown: _onTapDown,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      behavior: HitTestBehavior.opaque,
      child: result,
    );
  }
}

// ────────────────────────────────────────
// 分段轨道 — 5 个独立圆角段，间隙分隔，填充段的清晰可见
// ────────────────────────────────────────

class _SegmentedTrack extends StatelessWidget {
  final double barW;
  final double barH;
  final double segGap;
  final Color trackColor;
  final double displayRatio;
  final int maxRating;
  final List<Color> amberColors;
  final bool isMuted;

  const _SegmentedTrack({
    required this.barW,
    required this.barH,
    required this.segGap,
    required this.trackColor,
    required this.displayRatio,
    required this.maxRating,
    required this.amberColors,
    required this.isMuted,
  });

  @override
  Widget build(BuildContext context) {
    // 每个段的宽度（含间隙）
    final segW = barW / maxRating;
    // 段自身的宽度
    final innerW = segW - segGap;
    final radius = barH * 0.35;

    // 每段独立的填充比例：0.0 = 全空, 1.0 = 全满, 中间值随拖拽渐变
    // displayRatio 是全局填充比例，如 0.6 = 3/5 段填满
    final int fullSegs = (displayRatio * maxRating).floor();
    final double partial = (displayRatio * maxRating) - fullSegs;

    return SizedBox(
      width: barW,
      height: barH,
      child: Row(
        children: List.generate(maxRating, (i) {
          final double fill;
          if (i < fullSegs) {
            fill = 1.0;
          } else if (i == fullSegs) {
            fill = partial;
          } else {
            fill = 0.0;
          }

          return Padding(
            padding: EdgeInsets.only(left: i == 0 ? 0 : segGap),
            child: SizedBox(
              width: innerW,
              height: barH,
              child: _Segment(
                fillRatio: fill,
                barH: barH,
                radius: radius,
                trackColor: trackColor,
                amberColors: amberColors,
                isMuted: isMuted,
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// 单个分段 — 暗底 + 琥珀填充动画
class _Segment extends StatelessWidget {
  final double fillRatio;
  final double barH;
  final double radius;
  final Color trackColor;
  final List<Color> amberColors;
  final bool isMuted;

  const _Segment({
    required this.fillRatio,
    required this.barH,
    required this.radius,
    required this.trackColor,
    required this.amberColors,
    required this.isMuted,
  });

  @override
  Widget build(BuildContext context) {
    // 暗底容器
    return Container(
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 1,
            offset: const Offset(0, 0.5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: () {
          if (fillRatio <= 0) return const SizedBox.shrink();
          final colors = isMuted
              ? amberColors.map((c) => c.withValues(alpha: 0.25)).toList()
              : amberColors;
          return Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fillRatio,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors),
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: isMuted
                      ? null
                      : [
                          BoxShadow(
                            color: amberColors.first.withValues(alpha: 0.25),
                            blurRadius: barH * 0.6,
                          ),
                        ],
                ),
              ),
            ),
          );
        }(),
      ),
    );
  }
}
