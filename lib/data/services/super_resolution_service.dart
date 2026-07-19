import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../core/constants.dart' show FeatureFlags;
import 'ml_service.dart';

/// 超分辨率服务 — 基于 ONNX Model Zoo Sub-Pixel CNN
///
/// 模型来源：https://huggingface.co/onnxmodelzoo/super-resolution-10
/// - 输入：[1, 1, 224, 224] float32（Y 通道，YCbCr 色彩空间）
/// - 输出：[1, 1, 672, 672] float32（3 倍放大的 Y 通道）
/// - 模型大小：~240KB
/// - 许可证：Apache-2.0
///
/// 工作流程：
/// 1. 解码输入图片 → 转为 YCbCr
/// 2. 提取 Y 通道 → 缩放到 224×224（如需要）
/// 3. 送入 ONNX 模型推理 → 获取 3 倍放大的 Y 通道 (672×672)
/// 4. 对 Cb/Cr 通道使用双三次插值放大到对应尺寸
/// 5. 合并 YCbCr → 转回 RGB → 输出高分辨率图片
///
/// 当 ONNX Runtime 不可用时，回退到 Lanczos 重采样放大。
class SuperResolutionService {
  final MlService _mlService;

  /// 超分辨率模型在 MlService 中的标识符
  static const _modelId = 'super_resolution';

  /// 模型路径（开源分支不内嵌模型文件，需从 HuggingFace 下载）
  /// 参考: https://huggingface.co/onnxmodelzoo/super-resolution-10
  static const _modelAsset = '';

  /// 模型输入尺寸
  static const _inputSize = 224;

  /// 放大倍数
  static const _scaleFactor = 3;

  SuperResolutionService(this._mlService);

  /// 模型是否已加载并就绪
  bool get isModelReady =>
      _mlService.getStatus(_modelId) == MlModelStatus.ready;

  /// 模型状态
  MlModelStatus get modelStatus => _mlService.getStatus(_modelId);

  /// 初始化：尝试加载 ONNX 模型
  Future<void> initialize() async {
    if (modelStatus == MlModelStatus.notLoaded ||
        modelStatus == MlModelStatus.error) {
      await _mlService.loadModel(_modelAsset, _modelId);
    }
  }

  /// 对图片进行超分辨率放大
  ///
  /// [inputPath] 输入图片路径
  /// [outputPath] 输出图片路径
  /// [quality] JPEG 输出质量（1-100）
  ///
  /// 返回 outputPath 表示成功，null 表示失败。
  Future<String?> upscale(
    String inputPath, {
    required String outputPath,
    int quality = 95,
  }) async {
    if (!FeatureFlags.superResolutionEnabled) return null;
    try {
      final file = File(inputPath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;

      // 尝试 ONNX 推理路径
      img.Image? result;
      if (isModelReady) {
        result = await _upscaleWithOnnx(image);
      }

      // 回退到 Lanczos 重采样
      result ??= _upscaleWithLanczos(image);

      // 编码输出
      final outputBytes = img.encodeJpg(result, quality: quality);
      final outputFile = File(outputPath);
      await outputFile.create(recursive: true);
      await outputFile.writeAsBytes(outputBytes);

      return outputPath;
    } catch (_) {
      return null;
    }
  }

  /// 在内存中对图片进行超分辨率放大（不写文件）
  Future<img.Image?> upscaleImage(img.Image image) async {
    if (!FeatureFlags.superResolutionEnabled) return null;
    img.Image? result;
    if (isModelReady) {
      result = await _upscaleWithOnnx(image);
    }
    result ??= _upscaleWithLanczos(image);
    return result;
  }

  // ─── ONNX 推理路径 ──────────────────────────────────────────

  /// 使用 ONNX 超分辨率模型放大图片
  Future<img.Image?> _upscaleWithOnnx(img.Image image) async {
    try {
      final w = image.width;
      final h = image.height;

      // 模型输入固定 224×224，输出 672×672（3 倍）
      // 对于不同尺寸的图片，我们分块处理或缩放后处理

      // 简化方案：将图片缩放到 224×224 → 推理 → 放大到 672×672
      // 然后按原始宽高比裁剪/缩放

      // 转为 YCbCr 并提取 Y 通道
      final yChannel = _extractYChannel(image);
      final yResized = _resizeYChannel(yChannel, w, h, _inputSize, _inputSize);

      // 预处理为 [1, 1, 224, 224] float32
      final input = Float32List(1 * 1 * _inputSize * _inputSize);
      for (int i = 0; i < yResized.length; i++) {
        input[i] = yResized[i] / 255.0;
      }

      final result = await _mlService.runInference(
        _modelId,
        [input],
        [[1, 1, _inputSize, _inputSize]],
      );

      if (result == null || result.outputs.isEmpty) return null;

      // 解析输出 Y 通道 [1, 1, 672, 672]
      final outputY = result.outputs[0];
      final outputSize = _inputSize * _scaleFactor; // 672

      // 提取 Cb/Cr 通道并放大
      final cbcr = _extractCbCrChannels(image);
      final cbUpscaled = _resizeChannel(
        cbcr[0], w, h, outputSize, outputSize,
      );
      final crUpscaled = _resizeChannel(
        cbcr[1], w, h, outputSize, outputSize,
      );

      // 合并 YCbCr → RGB
      final outputImage = img.Image(width: outputSize, height: outputSize);
      for (int y = 0; y < outputSize; y++) {
        for (int x = 0; x < outputSize; x++) {
          final idx = y * outputSize + x;
          final yVal = (outputY[idx] * 255.0).clamp(0.0, 255.0);
          final cbVal = cbUpscaled[idx].toDouble();
          final crVal = crUpscaled[idx].toDouble();
          outputImage.setPixelRgba(x, y,
            _yclamp(yVal + 1.402 * (crVal - 128)),
            _yclamp(yVal - 0.344 * (cbVal - 128) - 0.714 * (crVal - 128)),
            _yclamp(yVal + 1.772 * (cbVal - 128)),
            255,
          );
        }
      }

      // 按原始宽高比裁剪
      final targetW = (w * _scaleFactor).toInt();
      final targetH = (h * _scaleFactor).toInt();
      if (targetW != outputSize || targetH != outputSize) {
        return img.copyResize(outputImage, width: targetW, height: targetH);
      }

      return outputImage;
    } catch (_) {
      return null;
    }
  }

  // ─── Lanczos 回退路径 ────────────────────────────────────────

  /// 使用 Lanczos 重采样放大图片（无 ONNX 时的回退）
  img.Image _upscaleWithLanczos(img.Image image) {
    final targetW = image.width * _scaleFactor;
    final targetH = image.height * _scaleFactor;
    return img.copyResize(
      image,
      width: targetW,
      height: targetH,
      interpolation: img.Interpolation.cubic,
    );
  }

  // ─── YCbCr 通道处理 ──────────────────────────────────────────

  /// 提取 Y 通道（亮度）
  Uint8List _extractYChannel(img.Image image) {
    final w = image.width;
    final h = image.height;
    final yChannel = Uint8List(w * h);

    for (int i = 0; i < w * h; i++) {
      final pixel = image.getPixel(i % w, i ~/ w);
      final r = pixel.r;
      final g = pixel.g;
      final b = pixel.b;
      // BT.601 Y 计算
      yChannel[i] = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255);
    }

    return yChannel;
  }

  /// 提取 Cb/Cr 通道
  List<Uint8List> _extractCbCrChannels(img.Image image) {
    final w = image.width;
    final h = image.height;
    final cbChannel = Uint8List(w * h);
    final crChannel = Uint8List(w * h);

    for (int i = 0; i < w * h; i++) {
      final pixel = image.getPixel(i % w, i ~/ w);
      final r = pixel.r;
      final g = pixel.g;
      final b = pixel.b;
      // BT.601 Cb/Cr
      cbChannel[i] = (-0.169 * r - 0.331 * g + 0.500 * b + 128)
          .round()
          .clamp(0, 255);
      crChannel[i] = (0.500 * r - 0.419 * g - 0.081 * b + 128)
          .round()
          .clamp(0, 255);
    }

    return [cbChannel, crChannel];
  }

  /// 缩放 Y 通道到目标尺寸（双线性插值）
  Float32List _resizeYChannel(
    Uint8List src, int srcW, int srcH, int dstW, int dstH,
  ) {
    final dst = Float32List(dstW * dstH);
    final xRatio = (srcW - 1) / (dstW - 1).clamp(1, 999999);
    final yRatio = (srcH - 1) / (dstH - 1).clamp(1, 999999);

    for (int y = 0; y < dstH; y++) {
      for (int x = 0; x < dstW; x++) {
        final sx = x * xRatio;
        final sy = y * yRatio;
        final x0 = sx.floor();
        final y0 = sy.floor();
        final x1 = (x0 + 1).clamp(0, srcW - 1);
        final y1 = (y0 + 1).clamp(0, srcH - 1);
        final dx = sx - x0;
        final dy = sy - y0;

        final v00 = src[y0 * srcW + x0].toDouble();
        final v01 = src[y0 * srcW + x1].toDouble();
        final v10 = src[y1 * srcW + x0].toDouble();
        final v11 = src[y1 * srcW + x1].toDouble();

        final v = v00 * (1 - dx) * (1 - dy) +
            v01 * dx * (1 - dy) +
            v10 * (1 - dx) * dy +
            v11 * dx * dy;
        dst[y * dstW + x] = v;
      }
    }

    return dst;
  }

  /// 缩放单通道到目标尺寸（双三次插值）
  Uint8List _resizeChannel(
    Uint8List src, int srcW, int srcH, int dstW, int dstH,
  ) {
    final dst = Uint8List(dstW * dstH);
    final xRatio = srcW / dstW;
    final yRatio = srcH / dstH;

    for (int y = 0; y < dstH; y++) {
      for (int x = 0; x < dstW; x++) {
        final sx = (x * xRatio).floor().clamp(0, srcW - 1);
        final sy = (y * yRatio).floor().clamp(0, srcH - 1);
        dst[y * dstW + x] = src[sy * srcW + sx];
      }
    }

    return dst;
  }

  /// 限制到 [0, 255] 并取整
  int _yclamp(double v) => v.round().clamp(0, 255);
}