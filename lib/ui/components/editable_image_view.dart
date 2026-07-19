import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/edit_params.dart';

/// 可编辑图片预览组件 — 实时显示编辑参数效果
///
/// 使用 ColorFilter.matrix 实现 GPU 加速的实时色彩调整预览，
/// 使用 Transform 实现旋转/翻转预览，使用 ClipRect 实现裁剪预览。
///
/// 对于复杂的调整（高光/阴影/暗角/颗粒），使用 ColorMatrix 近似模拟。
/// 最终导出时由 ImageEditService 进行精确的像素级处理。
class EditableImageView extends StatefulWidget {
  final String imagePath;
  final EditParams params;
  final bool isCurrentPage;
  final TransformationController? transformController;
  final VoidCallback? onDoubleTap;
  final void Function(ScaleStartDetails)? onTransformStart;
  final void Function(ScaleEndDetails)? onTransformEnd;

  const EditableImageView({
    super.key,
    required this.imagePath,
    required this.params,
    this.isCurrentPage = true,
    this.transformController,
    this.onDoubleTap,
    this.onTransformStart,
    this.onTransformEnd,
  });

  @override
  State<EditableImageView> createState() => _EditableImageViewState();
}

class _EditableImageViewState extends State<EditableImageView> {
  FragmentShader? _shader;
  bool _shaderLoaded = false;
  ui.Image? _decodedImage;

  @override
  void initState() {
    super.initState();
    _loadShader();
    _decodeImage();
  }

  @override
  void didUpdateWidget(EditableImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _decodedImage = null;
      _decodeImage();
    }
  }

  Future<void> _loadShader() async {
    try {
      final program = await FragmentProgram.fromAsset(
        'assets/shaders/photo_edit.frag',
      );
      _shader = program.fragmentShader();
      if (mounted) setState(() => _shaderLoaded = true);
    } catch (e) {
      // Shader 加载失败时回退到 ColorFilter 方案
      debugPrint('Shader 加载失败: $e');
    }
  }

  Future<void> _decodeImage() async {
    try {
      final file = File(widget.imagePath);
      if (!await file.exists()) return;
      final bytes = await file.readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      // targetWidth 限制解码分辨率 — 避免超大图片（如 50MP）解码为全尺寸
      // GPU 纹理，超出部分集成显卡 4096×4096 上限导致黑屏/崩溃。
      // 2048px 在编辑预览中足够清晰，shader 逐像素处理后输出画质无损。
      final codec = await ui.instantiateImageCodecFromBuffer(
        buffer,
        targetWidth: 2048,
      );
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() => _decodedImage = frame.image);
      }
    } catch (e) {
      debugPrint('图片解码失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 使用 LayoutBuilder 获取可用空间，计算 BoxFit.contain 的适配尺寸
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportW = constraints.maxWidth;
        final viewportH = constraints.maxHeight;

        Widget imageWidget;

        if (_decodedImage != null && _shader != null && _shaderLoaded) {
          // Shader 方案 — 精确的实时预览
          imageWidget = _buildShaderImage(viewportW, viewportH);
        } else if (_decodedImage != null) {
          // ColorFilter 回退方案
          imageWidget = _buildColorFilterImage();
        } else {
          // 图片加载中
          imageWidget = _buildLoadingImage();
        }

        // 应用几何变换（裁剪 + 旋转 + 翻转）
        imageWidget = _applyGeometry(imageWidget);

        // InteractiveViewer 缩放/平移 — child 已适配视口尺寸
        if (widget.transformController != null) {
          imageWidget = InteractiveViewer(
            panEnabled: widget.isCurrentPage,
            scaleEnabled: widget.isCurrentPage,
            maxScale: 5.0,
            minScale: 0.8,
            transformationController: widget.transformController,
            onInteractionStart: widget.onTransformStart,
            onInteractionEnd: widget.onTransformEnd,
            child: imageWidget,
          );
        }

        return GestureDetector(
          onDoubleTap: widget.isCurrentPage ? widget.onDoubleTap : null,
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: imageWidget,
          ),
        );
      },
    );
  }

  /// 使用 fragment shader 渲染 — 精确的实时预览
  ///
  /// [viewportW] / [viewportH] 为可用视口尺寸。
  /// shader 在 BoxFit.contain 适配后的尺寸上渲染，
  /// 而非图片原始像素尺寸，确保 InteractiveViewer 缩放行为正常。
  Widget _buildShaderImage(double viewportW, double viewportH) {
    final shader = _shader!;
    final image = _decodedImage!;

    // 计算 BoxFit.contain 适配后的显示尺寸
    final imageRatio = image.width / image.height;
    final viewportRatio = viewportW / viewportH;

    double displayW, displayH;
    if (imageRatio > viewportRatio) {
      // 图片更宽 — 以宽度为准
      displayW = viewportW;
      displayH = viewportW / imageRatio;
    } else {
      // 图片更高 — 以高度为准
      displayH = viewportH;
      displayW = viewportH * imageRatio;
    }

    shader.setImageSampler(0, image);
    // uResolution 设为显示尺寸 — shader 内部用此值计算 UV 坐标
    shader.setFloat(0, displayW);   // uResolution.x
    shader.setFloat(1, displayH);   // uResolution.y

    // 基础调整
    shader.setFloat(2, widget.params.exposure);           // uExposure
    shader.setFloat(3, widget.params.contrast);           // uContrast
    shader.setFloat(4, widget.params.highlights);         // uHighlights
    shader.setFloat(5, widget.params.shadows);            // uShadows
    shader.setFloat(6, widget.params.whites);             // uWhites
    shader.setFloat(7, widget.params.blacks);             // uBlacks

    // 色彩调整
    shader.setFloat(8, widget.params.saturation);         // uSaturation
    shader.setFloat(9, widget.params.vibrance);           // uVibrance
    shader.setFloat(10, widget.params.temperature);       // uTemperature
    shader.setFloat(11, widget.params.tint);              // uTint

    // 效果
    shader.setFloat(12, widget.params.vignette);          // uVignette
    shader.setFloat(13, widget.params.grain);             // uGrain
    shader.setFloat(14, widget.params.fade);              // uFade

    return SizedBox(
      width: displayW,
      height: displayH,
      child: CustomPaint(
        painter: _ShaderImagePainter(
          shader: shader,
          displayWidth: displayW,
          displayHeight: displayH,
        ),
        size: Size(displayW, displayH),
      ),
    );
  }

  /// 使用 ColorFilter.matrix 回退方案 — 近似预览
  Widget _buildColorFilterImage() {
    final image = _decodedImage!;
    final matrix = _buildColorMatrix(widget.params);

    return ColorFiltered(
      colorFilter: ColorFilter.matrix(matrix),
      child: RawImage(
        image: image,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }

  /// 加载中的图片显示
  Widget _buildLoadingImage() {
    return Image.file(
      File(widget.imagePath),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) => const Center(
        child: Icon(Icons.broken_image, size: 64, color: Colors.white54),
      ),
    );
  }

  /// 应用几何变换：裁剪 → 旋转 → 翻转
  Widget _applyGeometry(Widget child) {
    // 裁剪预览 — 使用 ClipRect + FractionalOffset
    if (widget.params.cropWidth < 1.0 ||
        widget.params.cropHeight < 1.0 ||
        widget.params.cropX > 0.0 ||
        widget.params.cropY > 0.0) {
      child = ClipRect(
        child: FractionallySizedBox(
          widthFactor: widget.params.cropWidth,
          heightFactor: widget.params.cropHeight,
          alignment: FractionalOffset(
            widget.params.cropX /
                (1.0 - widget.params.cropWidth).clamp(0.001, 1.0),
            widget.params.cropY /
                (1.0 - widget.params.cropHeight).clamp(0.001, 1.0),
          ),
          child: child,
        ),
      );
    }

    // 旋转
    if (widget.params.rotation != 0) {
      child = Transform.rotate(
        angle: widget.params.rotation * math.pi / 180.0,
        child: child,
      );
    }

    // 翻转
    if (widget.params.flipH) {
      child = Transform.flip(flipX: true, child: child);
    }
    if (widget.params.flipV) {
      child = Transform.flip(flipY: true, child: child);
    }

    return child;
  }

  /// 构建 ColorMatrix（4×5 矩阵）— 用于 ColorFilter 回退方案
  ///
  /// 近似模拟曝光、对比度、饱和度、色温、色调。
  /// 高光/阴影/暗角/颗粒等复杂效果在回退方案中不实现。
  List<double> _buildColorMatrix(EditParams p) {
    // 曝光
    final exposureFactor = math.pow(2.0, p.exposure).toDouble();

    // 对比度
    final contrastFactor = 1.0 + p.contrast * 0.01;
    final contrastOffset = 0.5 * (1.0 - contrastFactor) * 255.0;

    // 饱和度
    final satFactor = 1.0 + p.saturation * 0.01;

    // 色温/色调
    final tempR = p.temperature * 0.003 * 255.0;
    final tempB = -p.temperature * 0.003 * 255.0;
    final tintR = p.tint * 0.002 * 255.0;
    final tintG = -p.tint * 0.002 * 255.0;
    final tintB = p.tint * 0.002 * 255.0;

    // 组合矩阵：曝光 × 对比度 × 饱和度 × 色温/色调
    // 矩阵格式：[R', G', B', A', 1] 每行
    return <double>[
      // R 行
      exposureFactor * (0.213 + 0.787 * satFactor), // R→R
      exposureFactor * 0.715 * (1.0 - satFactor),   // G→R
      exposureFactor * 0.072 * (1.0 - satFactor),   // B→R
      0.0,                                            // A→R
      contrastOffset + tempR + tintR,                // offset
      // G 行
      exposureFactor * 0.213 * (1.0 - satFactor),   // R→G
      exposureFactor * (0.715 + 0.285 * satFactor), // G→G
      exposureFactor * 0.072 * (1.0 - satFactor),   // B→G
      0.0,
      contrastOffset + tintG,
      // B 行
      exposureFactor * 0.213 * (1.0 - satFactor),   // R→B
      exposureFactor * 0.715 * (1.0 - satFactor),   // G→B
      exposureFactor * (0.072 + 0.928 * satFactor), // B→B
      0.0,
      contrastOffset + tempB + tintB,
      // A 行
      0.0, 0.0, 0.0, 1.0, 0.0,
    ];
  }
}

/// Shader 图片画笔 — 将 fragment shader 绘制到画布
///
/// size 已是 BoxFit.contain 适配后的尺寸，直接填充整个绘制区域。
class _ShaderImagePainter extends CustomPainter {
  final FragmentShader shader;
  final double displayWidth;
  final double displayHeight;

  _ShaderImagePainter({
    required this.shader,
    required this.displayWidth,
    required this.displayHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // size 已是适配后的尺寸，直接填充
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_ShaderImagePainter oldDelegate) {
    // shader 是同一实例（setFloat 已更新），总是重绘
    return true;
  }
}