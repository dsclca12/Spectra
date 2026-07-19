import 'package:flutter/material.dart';

/// Zoom-aware snap PageScrollPhysics — extends native PageScrollPhysics with
/// a "max one page per gesture" limit.
///
/// Native PageScrollPhysics may skip multiple pages on fast swipes. This version
/// clamps the target to at most one page away from the current position, paired
/// with a stiffer spring for crisp snap behavior.
///
/// **Key**: Uses an `isZoomed` closure to dynamically check zoom state. When zoomed,
/// the gesture is rejected (returns null, no ballistic simulation), avoiding PageView
/// rebuilds and image flicker caused by swapping `physics` objects on zoom state changes.
class ZoomAwarePageScrollPhysics extends ScrollPhysics {
  const ZoomAwarePageScrollPhysics({
    super.parent,
    required this.isZoomed,
  });

  /// 闭包 — 动态读取当前缩放状态，避免 setState 重建
  final bool Function() isZoomed;

  @override
  ZoomAwarePageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return ZoomAwarePageScrollPhysics(
      parent: buildParent(ancestor),
      isZoomed: isZoomed,
    );
  }

  @override
  SpringDescription get spring => const SpringDescription(
        mass: 1,
        stiffness: 300,
        damping: 30, // 阻尼比 ≈ 0.87，接近临界阻尼，快速吸附无振荡
      );

  double _getPage(ScrollMetrics position) {
    return position.pixels / position.viewportDimension;
  }

  double _getPixels(ScrollMetrics position, double page) {
    return page * position.viewportDimension;
  }

  /// 计算目标像素位置 — 与原生 PageScrollPhysics 一致的 ±0.5 页逻辑，
  /// 但 clamp 限制最多移动一页。
  double _getTargetPixels(
      ScrollMetrics position, Tolerance tolerance, double velocity) {
    double page = _getPage(position);
    if (velocity < -tolerance.velocity) {
      page -= 0.5;
    } else if (velocity > tolerance.velocity) {
      page += 0.5;
    }
    final rawTarget = page.roundToDouble();

    // 限制最多移动一页 — 核心磁吸限制
    final currentPage = _getPage(position);
    final clampedPage =
        (rawTarget - currentPage).clamp(-1.0, 1.0) + currentPage;

    return _getPixels(position, clampedPage);
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    // 缩放时拒绝翻页 — 通过闭包动态判断，无需 setState 切换 physics
    if (isZoomed()) return null;

    // 边界处理 — 已到两端且继续向外滑时交给父级
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final Tolerance tolerance = toleranceFor(position);
    final double target = _getTargetPixels(position, tolerance, velocity);
    if ((target - position.pixels).abs() > 0.1) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        target,
        velocity,
        tolerance: tolerance,
      );
    }
    return null;
  }

  @override
  bool get allowImplicitScrolling => false;
}