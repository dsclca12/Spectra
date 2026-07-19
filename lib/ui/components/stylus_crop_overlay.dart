import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../../data/models/edit_params.dart';
import '../../data/services/pointer_type_service.dart';

void _cropLog(String message) {
  debugPrint('[StylusCrop] $message');
}

/// 手写笔裁剪叠加层 — 在单图查看器上方叠加。
///
/// 交互流程：
/// 1. 手写笔在图片显示区域内按下并拖拽一条对角线 → 生成初始裁剪框。
/// 2. 裁剪框出现后，手写笔可拖拽 8 个手柄（四角 + 四边）调整大小，
///    或拖拽框内区域平移裁剪框。
/// 3. 触摸屏输入完全透传到下层 InteractiveViewer，维持原有缩放/平移/翻页手势。
///
/// 设备区分依赖 [PointerTypeService]：当 Flutter PointerEvent 到达时，
/// 若 `event.kind == stylus` 或最近有原生 pen 事件，则视为手写笔并消费；
/// 否则视为触摸/鼠标，透传给下层。
///
/// 坐标系：所有拖拽在"图片显示区域"（BoxFit.contain 适配后的 Rect）内进行，
/// 最终转换为 [EditParams] 的归一化裁剪比例（0.0~1.0）。
class StylusCropOverlay extends StatefulWidget {
  /// 图片原始宽度（像素）— 用于计算 BoxFit.contain 显示区域。
  final int imageWidth;

  /// 图片原始高度（像素）。
  final int imageHeight;

  /// 当前裁剪参数。
  final EditParams params;

  /// 裁剪参数变化回调。
  final ValueChanged<EditParams> onChanged;

  /// 是否启用 — 非当前页或禁用时透传所有输入。
  final bool isEnabled;

  const StylusCropOverlay({
    super.key,
    required this.imageWidth,
    required this.imageHeight,
    required this.params,
    required this.onChanged,
    this.isEnabled = true,
  });

  @override
  State<StylusCropOverlay> createState() => _StylusCropOverlayState();
}

class _StylusCropOverlayState extends State<StylusCropOverlay> {
  /// 当前拖拽的手柄类型；null 表示未在拖拽。
  _HandleType? _draggingHandle;

  /// 拖拽起始时的裁剪框（显示坐标）。
  _CropRect? _dragStartRect;

  /// 手写笔对角线绘制阶段：按下点（显示坐标）。
  Offset? _diagonalStart;

  /// 当前对角线终点（显示坐标）— 拖拽中实时更新。
  Offset? _diagonalCurrent;

  /// 当前正在绘制对角线的指针 ID（防止多点干扰）。
  int? _diagonalPointerId;

  /// 指针类型服务（单例）。
  final PointerTypeService _pointerTypeService = PointerTypeService();

  static const Duration _stylusEventFreshness = Duration(milliseconds: 250);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final displayRect = _calculateDisplayRect(
          constraints.maxWidth,
          constraints.maxHeight,
          widget.imageWidth,
          widget.imageHeight,
        );
        final cropRect = _cropRectToDisplay(displayRect, widget.params);

        // 用 Listener（不参与手势竞技场，触摸零干扰）。
        // 手写笔 down 时通过 GestureBinding.cancelPointer 取消该指针，
        // 让下层 InteractiveViewer 的 ScaleGestureRecognizer 收到
        // PointerCancelEvent 而停止跟踪，从而不触发缩放/平移。
        // 触摸/鼠标 down 不做任何操作，完全透传给下层。
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: Stack(
            children: [
              // 遮罩 + 裁剪框 + 手柄（仅当已有裁剪框或正在画对角线时显示）
              if (_diagonalStart != null && _diagonalCurrent != null)
                _buildDiagonalPreview(displayRect)
              else if (_hasCropRect())
                _buildCropUI(displayRect, cropRect),
            ],
          ),
        );
      },
    );
  }

  // ─── 设备类型判断 ───────────────────────────────────────────────

  /// 判断一个 Flutter PointerEvent 是否来自"正在书写"的手写笔。
  ///
  /// 蓝牙手写笔悬空时压力为 0，此时视为触摸透传（不干扰下层手势）；
  /// 只有压力 > 0（笔尖接触屏幕）才认领为手写笔输入。
  ///
  /// 判定条件（须同时满足"是笔"且"有压力"）：
  /// 1. `event.kind == stylus / invertedStylus` 且 `pressure > 0`
  /// 2. 原生服务最近有 pen 事件 且 `pressure > 0`
  /// 3. `pressure > 0` 且 `pressureMax > 0`（笔特有压感，触摸屏 pressureMax == 0）
  /// 4. 有倾斜 且 `pressure > 0`
  bool _isStylus(PointerEvent event) {
    // 压力必须 > 0 — 蓝牙手写笔悬空时压力为 0，视为触摸透传。
    final hasPressure = event.pressure > 0.0;

    final kindStylus = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    final nativePen = _pointerTypeService.hasRecentPenEvent(
      maxAge: _stylusEventFreshness,
    );
    final pressureMaxValid = event.pressureMax > 0.0;
    final tiltNonZero = event.tilt != 0.0;

    _cropLog(
      'isStylus check: kind=${event.kind} pressure=${event.pressure} '
      'pressureMax=${event.pressureMax} tilt=${event.tilt} '
      'hasPressure=$hasPressure kindStylus=$kindStylus '
      'nativePen=$nativePen pressureMaxValid=$pressureMaxValid '
      'tiltNonZero=$tiltNonZero',
    );

    if (kindStylus) {
      _cropLog('  → kindStylus branch, return hasPressure=$hasPressure');
      return hasPressure;
    }
    // Windows 原生信号兜底：部分触摸屏笔输入 Flutter 上报为 touch，
    // 但原生 WM_POINTER 仍能区分 PT_PEN。
    if (nativePen) {
      _cropLog('  → nativePen branch, return hasPressure=$hasPressure');
      return hasPressure;
    }
    // 压感兜底：触摸屏 pressureMax == 0 且 pressure == 0，
    // 手写笔即使 Flutter 上报为 touch 也常有 pressureMax > 0。
    if (pressureMaxValid && hasPressure) {
      _cropLog('  → pressureMax branch, return true');
      return true;
    }
    // 倾斜兜底：触摸屏 tilt == 0，手写笔常有非零 tilt。
    if (tiltNonZero && hasPressure) {
      _cropLog('  → tilt branch, return true');
      return true;
    }
    _cropLog('  → not stylus, return false');
    return false;
  }

  // ─── 指针事件处理 ───────────────────────────────────────────────

  void _onPointerDown(PointerDownEvent event) {
    _cropLog(
      'onPointerDown: pointer=${event.pointer} kind=${event.kind} '
      'pressure=${event.pressure} pos=${event.localPosition}',
    );
    if (!widget.isEnabled) {
      _cropLog('  → not enabled, ignore');
      return;
    }
    if (!_isStylus(event)) {
      _cropLog('  → not stylus, passthrough');
      return; // 触摸/鼠标透传
    }

    final displayRect = _currentDisplayRect();
    if (displayRect == null) {
      _cropLog('  → displayRect null, ignore');
      return;
    }

    final local = event.localPosition;
    // 只接受在图片显示区域内的按下
    if (!displayRect.contains(local)) {
      _cropLog(
        '  → outside displayRect $displayRect, ignore (pos=$local)',
      );
      return;
    }

    // ★ 关键：取消该指针，让下层 InteractiveViewer 收到 PointerCancelEvent，
    // 停止跟踪该指针，避免手写笔同时触发缩放/平移。
    // cancelPointer 会向所有正在跟踪该指针的识别器派发 cancel 事件。
    _cropLog('  → cancelPointer ${event.pointer}');
    GestureBinding.instance.cancelPointer(event.pointer);

    // 若已有裁剪框，先判断是否点中了手柄或框内
    final cropRect = _cropRectToDisplay(displayRect, widget.params);
    final handle = _hitTestHandle(cropRect, local);
    if (handle != null) {
      _cropLog('  → hit handle $handle');
      _draggingHandle = handle;
      _dragStartRect = _CropRect.fromRect(cropRect);
      return;
    }

    // 否则开始画对角线（会重置已有裁剪框）
    _cropLog('  → start diagonal at $local');
    _diagonalStart = local;
    _diagonalCurrent = local;
    _diagonalPointerId = event.pointer;
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!widget.isEnabled) return;
    // 仅处理我们认领的手写笔指针
    if (event.pointer != _diagonalPointerId && _draggingHandle == null) {
      return;
    }
    if (_diagonalPointerId == null && _draggingHandle == null) return;

    final displayRect = _currentDisplayRect();
    if (displayRect == null) return;

    final local = event.localPosition;

    // 对角线绘制阶段
    if (_diagonalStart != null && event.pointer == _diagonalPointerId) {
      setState(() {
        _diagonalCurrent = _clampToDisplay(local, displayRect);
      });
      return;
    }

    // 手柄拖拽阶段
    if (_draggingHandle != null && _dragStartRect != null) {
      _onHandleDrag(event.delta, displayRect);
      return;
    }
  }

  void _onPointerUp(PointerEvent event) {
    if (!widget.isEnabled) return;

    // 对角线绘制结束 → 生成裁剪框
    if (_diagonalStart != null &&
        _diagonalCurrent != null &&
        event.pointer == _diagonalPointerId) {
      final displayRect = _currentDisplayRect();
      if (displayRect != null) {
        final newRect = Rect.fromPoints(_diagonalStart!, _diagonalCurrent!);
        // 最小尺寸阈值，避免误触产生极小裁剪框
        if (newRect.width >= 16 && newRect.height >= 16) {
          final params = _displayRectToCropParams(displayRect, newRect);
          widget.onChanged(params);
        }
      }
      setState(() {
        _diagonalStart = null;
        _diagonalCurrent = null;
        _diagonalPointerId = null;
      });
      return;
    }

    // 手柄拖拽结束
    if (_draggingHandle != null) {
      setState(() {
        _draggingHandle = null;
        _dragStartRect = null;
      });
    }
  }

  // ─── 手柄拖拽逻辑 ───────────────────────────────────────────────

  void _onHandleDrag(Offset delta, Rect displayRect) {
    if (_draggingHandle == null || _dragStartRect == null) return;

    final start = _dragStartRect!;
    var newRect = Rect.fromLTWH(start.left, start.top, start.width, start.height);

    switch (_draggingHandle!) {
      case _HandleType.move:
        newRect = newRect.translate(delta.dx, delta.dy);
        break;
      case _HandleType.topLeft:
        newRect = Rect.fromLTRB(
          newRect.left + delta.dx,
          newRect.top + delta.dy,
          newRect.right,
          newRect.bottom,
        );
        break;
      case _HandleType.topRight:
        newRect = Rect.fromLTRB(
          newRect.left,
          newRect.top + delta.dy,
          newRect.right + delta.dx,
          newRect.bottom,
        );
        break;
      case _HandleType.bottomLeft:
        newRect = Rect.fromLTRB(
          newRect.left + delta.dx,
          newRect.top,
          newRect.right,
          newRect.bottom + delta.dy,
        );
        break;
      case _HandleType.bottomRight:
        newRect = Rect.fromLTRB(
          newRect.left,
          newRect.top,
          newRect.right + delta.dx,
          newRect.bottom + delta.dy,
        );
        break;
      case _HandleType.top:
        newRect = Rect.fromLTRB(
          newRect.left,
          newRect.top + delta.dy,
          newRect.right,
          newRect.bottom,
        );
        break;
      case _HandleType.bottom:
        newRect = Rect.fromLTRB(
          newRect.left,
          newRect.top,
          newRect.right,
          newRect.bottom + delta.dy,
        );
        break;
      case _HandleType.left:
        newRect = Rect.fromLTRB(
          newRect.left + delta.dx,
          newRect.top,
          newRect.right,
          newRect.bottom,
        );
        break;
      case _HandleType.right:
        newRect = Rect.fromLTRB(
          newRect.left,
          newRect.top,
          newRect.right + delta.dx,
          newRect.bottom,
        );
        break;
    }

    // 限制在显示区域内
    newRect = _clampRect(newRect, displayRect);

    // 最小尺寸
    const minSize = 16.0;
    if (newRect.width < minSize || newRect.height < minSize) return;

    final newParams = _displayRectToCropParams(displayRect, newRect);
    widget.onChanged(newParams);
  }

  // ─── 命中测试 ───────────────────────────────────────────────────

  /// 判断点是否落在某个手柄上。手柄有 24px 命中区域。
  _HandleType? _hitTestHandle(Rect cropRect, Offset point) {
    const hitSize = 32.0; // 手写笔命中区域稍大，便于操作
    final half = hitSize / 2;

    final handles = <_HandleType, Offset>{
      _HandleType.topLeft: cropRect.topLeft,
      _HandleType.topRight: cropRect.topRight,
      _HandleType.bottomLeft: cropRect.bottomLeft,
      _HandleType.bottomRight: cropRect.bottomRight,
      _HandleType.top: Offset(cropRect.center.dx, cropRect.top),
      _HandleType.bottom: Offset(cropRect.center.dx, cropRect.bottom),
      _HandleType.left: Offset(cropRect.left, cropRect.center.dy),
      _HandleType.right: Offset(cropRect.right, cropRect.center.dy),
    };

    for (final entry in handles.entries) {
      final pos = entry.value;
      if ((point - pos).dx.abs() <= half && (point - pos).dy.abs() <= half) {
        return entry.key;
      }
    }

    // 框内 → move
    if (cropRect.contains(point)) {
      return _HandleType.move;
    }

    return null;
  }

  // ─── UI 构建 ───────────────────────────────────────────────────

  /// 是否已有有效裁剪框（非全图）。
  bool _hasCropRect() {
    final p = widget.params;
    return p.cropWidth < 1.0 ||
        p.cropHeight < 1.0 ||
        p.cropX > 0.0 ||
        p.cropY > 0.0;
  }

  Widget _buildDiagonalPreview(Rect displayRect) {
    final rect = Rect.fromPoints(_diagonalStart!, _diagonalCurrent!);
    return Stack(
      children: [
        // 遮罩
        CustomPaint(
          painter: _MaskPainter(displayRect: displayRect, cropRect: rect),
          size: Size.infinite,
        ),
        // 对角线 + 框
        Positioned.fromRect(
          rect: rect,
          child: CustomPaint(
            painter: _DiagonalPainter(start: _diagonalStart!, end: _diagonalCurrent!),
            size: Size.infinite,
          ),
        ),
      ],
    );
  }

  Widget _buildCropUI(Rect displayRect, Rect cropRect) {
    return Stack(
      children: [
        // 遮罩
        CustomPaint(
          painter: _MaskPainter(displayRect: displayRect, cropRect: cropRect),
          size: Size.infinite,
        ),
        // 裁剪框 + 网格
        Positioned.fromRect(
          rect: cropRect,
          child: CustomPaint(painter: _CropGridPainter(), size: Size.infinite),
        ),
        // 8 个手柄
        ..._buildHandles(cropRect),
        // 尺寸显示
        Positioned(
          left: cropRect.left,
          top: cropRect.bottom + 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${(widget.imageWidth * widget.params.cropWidth).round()} × '
              '${(widget.imageHeight * widget.params.cropHeight).round()}',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildHandles(Rect cropRect) {
    const handleSize = 24.0;
    const handleThickness = 6.0;
    const handleColor = Colors.white;

    final handles = <Widget>[];

    final corners = [
      (_HandleType.topLeft, cropRect.topLeft),
      (_HandleType.topRight, cropRect.topRight),
      (_HandleType.bottomLeft, cropRect.bottomLeft),
      (_HandleType.bottomRight, cropRect.bottomRight),
    ];

    for (final (_, pos) in corners) {
      handles.add(
        Positioned(
          left: pos.dx - handleSize / 2,
          top: pos.dy - handleSize / 2,
          child: IgnorePointer(
            child: Container(
              width: handleSize,
              height: handleSize,
              decoration: BoxDecoration(
                color: handleColor,
                border: Border.all(color: Colors.black54, width: 1),
              ),
            ),
          ),
        ),
      );
    }

    final edges = [
      (_HandleType.top, Offset(cropRect.center.dx, cropRect.top)),
      (_HandleType.bottom, Offset(cropRect.center.dx, cropRect.bottom)),
      (_HandleType.left, Offset(cropRect.left, cropRect.center.dy)),
      (_HandleType.right, Offset(cropRect.right, cropRect.center.dy)),
    ];

    for (final (type, pos) in edges) {
      final isHorizontal =
          type == _HandleType.top || type == _HandleType.bottom;
      handles.add(
        Positioned(
          left: isHorizontal
              ? pos.dx - handleSize * 1.5
              : pos.dx - handleThickness / 2,
          top: isHorizontal
              ? pos.dy - handleThickness / 2
              : pos.dy - handleSize * 1.5,
          child: IgnorePointer(
            child: Container(
              width: isHorizontal ? handleSize * 3 : handleThickness,
              height: isHorizontal ? handleThickness : handleSize * 3,
              color: handleColor,
            ),
          ),
        ),
      );
    }

    return handles;
  }

  // ─── 坐标转换 ───────────────────────────────────────────────────

  Rect? _currentDisplayRect() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return null;
    final size = renderObject.size;
    return _calculateDisplayRect(
      size.width,
      size.height,
      widget.imageWidth,
      widget.imageHeight,
    );
  }

  Rect _calculateDisplayRect(
    double containerW,
    double containerH,
    int imageW,
    int imageH,
  ) {
    final imageRatio = imageW / imageH;
    final containerRatio = containerW / containerH;

    double w, h;
    if (imageRatio > containerRatio) {
      w = containerW;
      h = containerW / imageRatio;
    } else {
      h = containerH;
      w = containerH * imageRatio;
    }

    return Rect.fromLTWH((containerW - w) / 2, (containerH - h) / 2, w, h);
  }

  Rect _cropRectToDisplay(Rect displayRect, EditParams params) {
    return Rect.fromLTWH(
      displayRect.left + displayRect.width * params.cropX,
      displayRect.top + displayRect.height * params.cropY,
      displayRect.width * params.cropWidth,
      displayRect.height * params.cropHeight,
    );
  }

  EditParams _displayRectToCropParams(Rect displayRect, Rect cropRect) {
    final clampedLeft = cropRect.left.clamp(displayRect.left, displayRect.right);
    final clampedTop = cropRect.top.clamp(displayRect.top, displayRect.bottom);
    final clampedRight =
        cropRect.right.clamp(displayRect.left, displayRect.right);
    final clampedBottom =
        cropRect.bottom.clamp(displayRect.top, displayRect.bottom);

    final x = (clampedLeft - displayRect.left) / displayRect.width;
    final y = (clampedTop - displayRect.top) / displayRect.height;
    final w = (clampedRight - clampedLeft) / displayRect.width;
    final h = (clampedBottom - clampedTop) / displayRect.height;

    return widget.params.copyWith(
      cropX: x.clamp(0.0, 1.0),
      cropY: y.clamp(0.0, 1.0),
      cropWidth: w.clamp(0.01, 1.0),
      cropHeight: h.clamp(0.01, 1.0),
    );
  }

  Offset _clampToDisplay(Offset point, Rect displayRect) {
    return Offset(
      point.dx.clamp(displayRect.left, displayRect.right),
      point.dy.clamp(displayRect.top, displayRect.bottom),
    );
  }

  Rect _clampRect(Rect rect, Rect bounds) {
    final left = rect.left.clamp(bounds.left, bounds.right - rect.width);
    final top = rect.top.clamp(bounds.top, bounds.bottom - rect.height);
    return Rect.fromLTWH(
      left.clamp(bounds.left, bounds.right),
      top.clamp(bounds.top, bounds.bottom),
      rect.width,
      rect.height,
    ).intersect(bounds);
  }
}

/// 手柄类型。
enum _HandleType {
  move,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  bottom,
  left,
  right,
}

/// 裁剪矩形辅助类。
class _CropRect {
  final double left, top, width, height;

  _CropRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  factory _CropRect.fromRect(Rect rect) => _CropRect(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
      );

  double get right => left + width;
  double get bottom => top + height;
}

/// 遮罩画笔 — 裁剪框外区域半透明。
class _MaskPainter extends CustomPainter {
  final Rect displayRect;
  final Rect cropRect;

  _MaskPainter({required this.displayRect, required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.5);

    canvas.drawRect(
      Rect.fromLTRB(
          displayRect.left, displayRect.top, displayRect.right, cropRect.top),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTRB(displayRect.left, cropRect.bottom, displayRect.right,
          displayRect.bottom),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTRB(
          displayRect.left, cropRect.top, cropRect.left, cropRect.bottom),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTRB(
          cropRect.right, cropRect.top, displayRect.right, cropRect.bottom),
      paint,
    );
  }

  @override
  bool shouldRepaint(_MaskPainter oldDelegate) =>
      displayRect != oldDelegate.displayRect ||
      cropRect != oldDelegate.cropRect;
}

/// 对角线绘制画笔 — 边框 + 对角线 + 三分法网格。
class _DiagonalPainter extends CustomPainter {
  final Offset start;
  final Offset end;

  _DiagonalPainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Offset.zero & size, borderPaint);

    final diagPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1.0;
    canvas.drawLine(start, end, diagPaint);

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var i = 1; i < 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(_DiagonalPainter oldDelegate) =>
      start != oldDelegate.start || end != oldDelegate.end;
}

/// 裁剪网格画笔 — 三分法网格 + 边框。
class _CropGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Offset.zero & size, borderPaint);

    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var i = 1; i < 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(_CropGridPainter oldDelegate) => false;
}