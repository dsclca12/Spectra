import 'package:flutter/material.dart';

import '../../data/models/edit_params.dart';

/// 裁剪比例预设
enum CropAspectRatio {
  free,    // 自由比例
  original, // 原始比例
  ratio1_1, // 1:1
  ratio4_3, // 4:3
  ratio3_2, // 3:2
  ratio16_9, // 16:9
  ratio2_3, // 2:3
  ratio3_4, // 3:4
}

extension CropAspectRatioX on CropAspectRatio {
  String get label {
    return switch (this) {
      CropAspectRatio.free => '自由',
      CropAspectRatio.original => '原始',
      CropAspectRatio.ratio1_1 => '1:1',
      CropAspectRatio.ratio4_3 => '4:3',
      CropAspectRatio.ratio3_2 => '3:2',
      CropAspectRatio.ratio16_9 => '16:9',
      CropAspectRatio.ratio2_3 => '2:3',
      CropAspectRatio.ratio3_4 => '3:4',
    };
  }

  /// 返回宽高比，null 表示自由/原始
  double? get ratio {
    return switch (this) {
      CropAspectRatio.free => null,
      CropAspectRatio.original => null,
      CropAspectRatio.ratio1_1 => 1.0,
      CropAspectRatio.ratio4_3 => 4.0 / 3.0,
      CropAspectRatio.ratio3_2 => 3.0 / 2.0,
      CropAspectRatio.ratio16_9 => 16.0 / 9.0,
      CropAspectRatio.ratio2_3 => 2.0 / 3.0,
      CropAspectRatio.ratio3_4 => 3.0 / 4.0,
    };
  }
}

/// 裁剪交互叠加层 — 在图片上方显示可拖拽的裁剪框
///
/// 功能：
/// - 8 个拖拽手柄（四角 + 四边）
/// - 裁剪框内拖拽平移
/// - 三分法网格叠加
/// - 可锁定宽高比
/// - 实时显示裁剪后尺寸
class CropOverlay extends StatefulWidget {
  /// 图片原始宽度（像素）
  final int imageWidth;

  /// 图片原始高度（像素）
  final int imageHeight;

  /// 当前裁剪参数
  final EditParams params;

  /// 裁剪参数变化回调
  final ValueChanged<EditParams> onChanged;

  /// 当前选中的宽高比预设
  final CropAspectRatio aspectRatio;

  /// 宽高比预设变化回调
  final ValueChanged<CropAspectRatio> onAspectRatioChanged;

  const CropOverlay({
    super.key,
    required this.imageWidth,
    required this.imageHeight,
    required this.params,
    required this.onChanged,
    this.aspectRatio = CropAspectRatio.free,
    required this.onAspectRatioChanged,
  });

  @override
  State<CropOverlay> createState() => _CropOverlayState();
}

class _CropOverlayState extends State<CropOverlay> {
  /// 拖拽中的手柄类型
  _HandleType? _draggingHandle;

  /// 拖拽起始时的裁剪区域
  _CropRect? _dragStartRect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 计算图片在容器中的实际显示区域（BoxFit.contain）
        final displayRect = _calculateDisplayRect(
          constraints.maxWidth,
          constraints.maxHeight,
          widget.imageWidth,
          widget.imageHeight,
        );

        // 计算裁剪框在显示区域中的位置
        final cropRect = _cropRectToDisplay(displayRect, widget.params);

        return Stack(
          children: [
            // 遮罩层 — 裁剪框外区域变暗
            _buildMask(displayRect, cropRect),

            // 裁剪框 + 网格 + 手柄
            Positioned(
              left: cropRect.left,
              top: cropRect.top,
              width: cropRect.width,
              height: cropRect.height,
              child: _buildCropBox(cropRect),
            ),

            // 手柄层
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
      },
    );
  }

  /// 计算 BoxFit.contain 的显示区域
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

    return Rect.fromLTWH(
      (containerW - w) / 2,
      (containerH - h) / 2,
      w,
      h,
    );
  }

  /// 将 EditParams 的裁剪比例转换为显示坐标中的 Rect
  Rect _cropRectToDisplay(Rect displayRect, EditParams params) {
    return Rect.fromLTWH(
      displayRect.left + displayRect.width * params.cropX,
      displayRect.top + displayRect.height * params.cropY,
      displayRect.width * params.cropWidth,
      displayRect.height * params.cropHeight,
    );
  }

  /// 将显示坐标中的 Rect 转换回 EditParams 裁剪比例
  EditParams _displayRectToCropParams(Rect displayRect, Rect cropRect) {
    // 确保裁剪框不超出显示区域
    final clampedLeft = cropRect.left.clamp(
      displayRect.left,
      displayRect.right,
    );
    final clampedTop = cropRect.top.clamp(
      displayRect.top,
      displayRect.bottom,
    );
    final clampedRight = cropRect.right.clamp(
      displayRect.left,
      displayRect.right,
    );
    final clampedBottom = cropRect.bottom.clamp(
      displayRect.top,
      displayRect.bottom,
    );

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

  /// 构建遮罩层 — 裁剪框外区域半透明黑色
  Widget _buildMask(Rect displayRect, Rect cropRect) {
    return CustomPaint(
      painter: _MaskPainter(
        displayRect: displayRect,
        cropRect: cropRect,
      ),
      size: Size.infinite,
    );
  }

  /// 构建裁剪框 — 边框 + 三分法网格
  Widget _buildCropBox(Rect cropRect) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) {
        _draggingHandle = _HandleType.move;
        _dragStartRect = _CropRect.fromRect(cropRect);
      },
      onPanUpdate: (details) => _onHandleDrag(details.delta),
      onPanEnd: (_) {
        _draggingHandle = null;
        _dragStartRect = null;
      },
      child: CustomPaint(
        painter: _CropGridPainter(),
        size: Size.infinite,
      ),
    );
  }

  /// 构建 8 个拖拽手柄
  List<Widget> _buildHandles(Rect cropRect) {
    const handleSize = 24.0;
    const handleThickness = 6.0;
    const handleColor = Colors.white;

    final handles = <Widget>[];

    // 四角手柄
    final corners = [
      (_HandleType.topLeft, cropRect.topLeft),
      (_HandleType.topRight, cropRect.topRight),
      (_HandleType.bottomLeft, cropRect.bottomLeft),
      (_HandleType.bottomRight, cropRect.bottomRight),
    ];

    for (final (type, pos) in corners) {
      handles.add(
        Positioned(
          left: pos.dx - handleSize / 2,
          top: pos.dy - handleSize / 2,
          child: GestureDetector(
            onPanStart: (details) {
              _draggingHandle = type;
              _dragStartRect = _CropRect.fromRect(cropRect);
            },
            onPanUpdate: (details) => _onHandleDrag(details.delta),
            onPanEnd: (_) {
              _draggingHandle = null;
              _dragStartRect = null;
            },
            child: Container(
              width: handleSize,
              height: handleSize,
              decoration: BoxDecoration(
                color: handleColor,
                border: Border.all(
                  color: Colors.black54,
                  width: 1,
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 四边手柄（中间）
    final edges = [
      (_HandleType.top, Offset(cropRect.center.dx, cropRect.top)),
      (_HandleType.bottom, Offset(cropRect.center.dx, cropRect.bottom)),
      (_HandleType.left, Offset(cropRect.left, cropRect.center.dy)),
      (_HandleType.right, Offset(cropRect.right, cropRect.center.dy)),
    ];

    for (final (type, pos) in edges) {
      final isHorizontal = type == _HandleType.top || type == _HandleType.bottom;
      handles.add(
        Positioned(
          left: isHorizontal
              ? pos.dx - handleSize * 1.5
              : pos.dx - handleThickness / 2,
          top: isHorizontal
              ? pos.dy - handleThickness / 2
              : pos.dy - handleSize * 1.5,
          child: GestureDetector(
            onPanStart: (details) {
              _draggingHandle = type;
              _dragStartRect = _CropRect.fromRect(cropRect);
            },
            onPanUpdate: (details) => _onHandleDrag(details.delta),
            onPanEnd: (_) {
              _draggingHandle = null;
              _dragStartRect = null;
            },
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

  /// 处理手柄拖拽
  void _onHandleDrag(Offset delta) {
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

    // 应用宽高比约束
    final ratio = widget.aspectRatio.ratio;
    if (ratio != null && _draggingHandle != _HandleType.move) {
      newRect = _applyAspectRatio(newRect, start, ratio, _draggingHandle!);
    }

    // 确保最小尺寸
    const minSize = 20.0;
    if (newRect.width < minSize || newRect.height < minSize) return;

    // 转换回 EditParams
    final displayRect = _calculateDisplayRect(
      context.size?.width ?? 0,
      context.size?.height ?? 0,
      widget.imageWidth,
      widget.imageHeight,
    );

    final newParams = _displayRectToCropParams(displayRect, newRect);
    widget.onChanged(newParams);
  }

  /// 应用宽高比约束
  Rect _applyAspectRatio(
    Rect newRect,
    _CropRect startRect,
    double ratio,
    _HandleType handle,
  ) {
    final width = newRect.width.abs();
    final height = newRect.height.abs();

    // 根据拖拽方向决定以宽还是高为基准
    if (handle == _HandleType.left ||
        handle == _HandleType.right ||
        handle == _HandleType.topLeft ||
        handle == _HandleType.topRight ||
        handle == _HandleType.bottomLeft ||
        handle == _HandleType.bottomRight) {
      // 以宽度为基准调整高度
      final newHeight = width / ratio;
      switch (handle) {
        case _HandleType.topLeft:
        case _HandleType.topRight:
        case _HandleType.top:
          return Rect.fromLTRB(
            newRect.left,
            newRect.bottom - newHeight,
            newRect.right,
            newRect.bottom,
          );
        default:
          return Rect.fromLTRB(
            newRect.left,
            newRect.top,
            newRect.right,
            newRect.top + newHeight,
          );
      }
    } else {
      // 以高度为基准调整宽度
      final newWidth = height * ratio;
      switch (handle) {
        case _HandleType.left:
          return Rect.fromLTRB(
            newRect.right - newWidth,
            newRect.top,
            newRect.right,
            newRect.bottom,
          );
        default:
          return Rect.fromLTRB(
            newRect.left,
            newRect.top,
            newRect.left + newWidth,
            newRect.bottom,
          );
      }
    }
  }
}

/// 手柄类型
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

/// 裁剪矩形辅助类
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

/// 遮罩画笔 — 裁剪框外区域半透明
class _MaskPainter extends CustomPainter {
  final Rect displayRect;
  final Rect cropRect;

  _MaskPainter({required this.displayRect, required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.5);

    // 上方遮罩
    canvas.drawRect(
      Rect.fromLTRB(displayRect.left, displayRect.top, displayRect.right, cropRect.top),
      paint,
    );
    // 下方遮罩
    canvas.drawRect(
      Rect.fromLTRB(displayRect.left, cropRect.bottom, displayRect.right, displayRect.bottom),
      paint,
    );
    // 左方遮罩
    canvas.drawRect(
      Rect.fromLTRB(displayRect.left, cropRect.top, cropRect.left, cropRect.bottom),
      paint,
    );
    // 右方遮罩
    canvas.drawRect(
      Rect.fromLTRB(cropRect.right, cropRect.top, displayRect.right, cropRect.bottom),
      paint,
    );
  }

  @override
  bool shouldRepaint(_MaskPainter oldDelegate) =>
      displayRect != oldDelegate.displayRect ||
      cropRect != oldDelegate.cropRect;
}

/// 裁剪网格画笔 — 三分法网格 + 边框
class _CropGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 边框
    final borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Offset.zero & size, borderPaint);

    // 三分法网格
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = 0.8;

    // 垂直线
    for (var i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    // 水平线
    for (var i = 1; i < 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(_CropGridPainter oldDelegate) => false;
}