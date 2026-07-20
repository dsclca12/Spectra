import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../models/edit_params.dart';

/// 图像编辑烘焙服务 — 将编辑参数应用到原始图片并导出
///
/// 实时预览使用 Flutter fragment shader（GPU 加速），
/// 最终导出时使用 `package:image` 进行像素级处理。
///
/// ⚠️ 已知限制：
/// - `package:image` 是纯 Dart 解码器，不支持 RAW/HEIC/AVIF 格式。
///   对于这些格式的导出，需要先通过 ImageDecoderService 解码为 PNG
///   中间格式再应用编辑参数。当前版本在 RAW 导出时会返回 null。
/// - 全分辨率解码（readAsBytes + decodeImage）对 50MB+ 大图可能 OOM。
///   中长期方案：用 GPU shader 直接烘焙，跳过 CPU 像素处理。
///
/// 支持的编辑操作：
/// - 基础调整：曝光、对比度、高光、阴影、白色/黑色色阶
/// - 色彩调整：饱和度、自然饱和度、色温、色调
/// - 效果：锐化、暗角、颗粒、褪色
/// - 几何变换：裁剪、旋转（90°增量）、水平/垂直翻转
class ImageEditService {
  ImageEditService();

  /// 烘焙编辑参数并导出为文件
  ///
  /// [inputPath] 原始图片路径
  /// [outputPath] 输出文件路径
  /// [params] 编辑参数
  /// [format] 输出格式（jpeg / png）
  /// [quality] JPEG 质量（1-100），仅 format=jpeg 时有效
  ///
  /// 返回 outputPath 表示成功，null 表示失败。
  Future<String?> bakeAndExport(
    String inputPath, {
    required String outputPath,
    required EditParams params,
    String format = 'jpeg',
    int quality = 95,
  }) async {
    try {
      final file = File(inputPath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;

      // 1. 几何变换（先裁剪，再旋转/翻转）
      image = _applyGeometry(image, params);

      // 2. 色彩/效果调整
      image = _applyColorAdjustments(image, params);

      // 3. 编码输出
      List<int> outputBytes;
      final ext = format.toLowerCase();
      if (ext == 'png') {
        outputBytes = img.encodePng(image);
      } else {
        outputBytes = img.encodeJpg(image, quality: quality);
      }

      final outputFile = File(outputPath);
      await outputFile.create(recursive: true);
      await outputFile.writeAsBytes(outputBytes);

      return outputPath;
    } catch (e) {
      return null;
    }
  }

  /// 应用几何变换：裁剪 → 旋转 → 翻转
  img.Image _applyGeometry(img.Image image, EditParams params) {
    // 裁剪
    if (params.cropWidth < 1.0 || params.cropHeight < 1.0 ||
        params.cropX > 0.0 || params.cropY > 0.0) {
      final cropX = (image.width * params.cropX).round();
      final cropY = (image.height * params.cropY).round();
      final cropW = (image.width * params.cropWidth).round();
      final cropH = (image.height * params.cropHeight).round();

      image = img.copyCrop(
        image,
        x: cropX.clamp(0, image.width - 1),
        y: cropY.clamp(0, image.height - 1),
        width: cropW.clamp(1, image.width - cropX),
        height: cropH.clamp(1, image.height - cropY),
      );
    }

    // 旋转（90° 增量）
    if (params.rotation != 0) {
      final rotations = (params.rotation ~/ 90) % 4;
      for (var i = 0; i < rotations; i++) {
        image = img.copyRotate(image, angle: 90);
      }
    }

    // 翻转
    if (params.flipH) {
      image = img.flipHorizontal(image);
    }
    if (params.flipV) {
      image = img.flipVertical(image);
    }

    return image;
  }

  /// 应用色彩和效果调整
  img.Image _applyColorAdjustments(img.Image image, EditParams params) {
    if (!params.hasColorEdits) return image;

    // 曝光：每 +1 EV = ×2 亮度
    final exposureFactor = _pow(2.0, params.exposure);

    // 对比度因子
    final contrastFactor = 1.0 + params.contrast * 0.01;

    // 色温/色调偏移
    final tempR = params.temperature * 0.003;
    final tempB = -params.temperature * 0.003;
    final tintR = params.tint * 0.002;
    final tintG = -params.tint * 0.002;
    final tintB = params.tint * 0.002;

    // 饱和度因子
    final satFactor = 1.0 + params.saturation * 0.01;

    // 自然饱和度因子
    final vibranceFactor = params.vibrance * 0.01;

    // 褪色
    final fadeAmount = params.fade * 0.005;
    final fadeMix = params.fade * 0.003;

    // 暗角
    final vignetteStrength = params.vignette * 0.01;

    // 颗粒
    final grainAmount = params.grain * 0.02;

    final width = image.width;
    final height = image.height;
    final centerX = width / 2.0;
    final centerY = height / 2.0;
    final maxDist = _sqrt(centerX * centerX + centerY * centerY);

    for (final pixel in image) {
      double r = pixel.r / 255.0;
      double g = pixel.g / 255.0;
      double b = pixel.b / 255.0;

      // 1. 曝光
      r *= exposureFactor;
      g *= exposureFactor;
      b *= exposureFactor;

      // 2. 对比度
      r = (r - 0.5) * contrastFactor + 0.5;
      g = (g - 0.5) * contrastFactor + 0.5;
      b = (b - 0.5) * contrastFactor + 0.5;

      // 3. 高光/阴影
      final lum = 0.299 * r + 0.587 * g + 0.114 * b;
      final highlightMask = _smoothstep(0.5, 1.0, lum);
      final shadowMask = 1.0 - _smoothstep(0.0, 0.5, lum);
      r += params.highlights * 0.01 * highlightMask;
      g += params.highlights * 0.01 * highlightMask;
      b += params.highlights * 0.01 * highlightMask;
      r += params.shadows * 0.01 * shadowMask;
      g += params.shadows * 0.01 * shadowMask;
      b += params.shadows * 0.01 * shadowMask;

      // 4. 白色/黑色色阶
      final whiteMask = _smoothstep(0.7, 1.0, lum);
      final blackMask = 1.0 - _smoothstep(0.0, 0.3, lum);
      r += params.whites * 0.01 * whiteMask;
      g += params.whites * 0.01 * whiteMask;
      b += params.whites * 0.01 * whiteMask;
      r += params.blacks * 0.01 * blackMask;
      g += params.blacks * 0.01 * blackMask;
      b += params.blacks * 0.01 * blackMask;

      // 5. 色温/色调
      r = r + tempR + tintR;
      g = g + tintG;
      b = b + tempB + tintB;

      // 6. 饱和度
      final gray = 0.299 * r + 0.587 * g + 0.114 * b;
      r = gray + (r - gray) * satFactor;
      g = gray + (g - gray) * satFactor;
      b = gray + (b - gray) * satFactor;

      // 7. 自然饱和度
      final sat = _rgbSaturation(r, g, b);
      final vibranceMask = 1.0 - sat;
      final vAdjust = vibranceFactor * vibranceMask;
      r = gray + (r - gray) * (1.0 + vAdjust);
      g = gray + (g - gray) * (1.0 + vAdjust);
      b = gray + (b - gray) * (1.0 + vAdjust);

      // 8. 褪色
      if (fadeAmount > 0) {
        r = _lerp(r, gray, fadeMix);
        g = _lerp(g, gray, fadeMix);
        b = _lerp(b, gray, fadeMix);
        r += fadeAmount;
        g += fadeAmount;
        b += fadeAmount;
      }

      // 9. 暗角
      if (vignetteStrength.abs() > 0.001) {
        final px = pixel.x.toDouble();
        final py = pixel.y.toDouble();
        final dist = _sqrt((px - centerX) * (px - centerX) +
            (py - centerY) * (py - centerY));
        final vMask = _smoothstep(maxDist * 0.3, maxDist * 0.8, dist);
        r += vignetteStrength * vMask;
        g += vignetteStrength * vMask;
        b += vignetteStrength * vMask;
      }

      // 10. 颗粒
      if (grainAmount > 0) {
        final noise = (_hash2(pixel.x.toDouble(), pixel.y.toDouble()) - 0.5) *
            grainAmount;
        r += noise;
        g += noise;
        b += noise;
      }

      // Clamp
      r = r.clamp(0.0, 1.0);
      g = g.clamp(0.0, 1.0);
      b = b.clamp(0.0, 1.0);

      image.setPixelRgba(
        pixel.x,
        pixel.y,
        (r * 255).round(),
        (g * 255).round(),
        (b * 255).round(),
        pixel.a,
      );
    }

    // 锐化（卷积）
    if (params.sharpness > 0) {
      final sharpAmount = params.sharpness * 0.01;
      image = _applySharpen(image, sharpAmount);
    }

    return image;
  }

  /// 锐化卷积
  img.Image _applySharpen(img.Image image, double amount) {
    return img.convolution(
      image,
      filter: [
        0.0, -amount, 0.0,
        -amount, 1.0 + 4.0 * amount, -amount,
        0.0, -amount, 0.0,
      ],
      div: 1.0,
      offset: 0.0,
    );
  }

  // ─── 数学辅助函数 ───

  double _smoothstep(double edge0, double edge1, double x) {
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// 计算 RGB 饱和度 — 内联比较替代 List 分配
  ///
  /// ⚡ 性能优化（v0.4.8）：
  /// - 旧实现：每像素创建 `[r, g, b]` 临时 List 然后 .reduce()，导致大量 GC 分配
  /// - 新实现：内联比较，零分配。对于数千万像素的全分辨率图片，GC 压力显著降低
  double _rgbSaturation(double r, double g, double b) {
    final maxVal = r > g ? (r > b ? r : b) : (g > b ? g : b);
    final minVal = r < g ? (r < b ? r : b) : (g < b ? g : b);
    if (maxVal == 0) return 0.0;
    return (maxVal - minVal) / maxVal;
  }

  /// 幂运算 — 委托给 dart:math
  ///
  /// ⚡ 性能优化（v0.4.8）：
  /// - 旧实现：自定义递归 _pow，非尾递归大指数可能栈溢出
  /// - 新实现：dart:math 的 math.pow，C 实现的 pow 函数，精度更高、性能更好
  double _pow(double base, double exp) => math.pow(base, exp).toDouble();

  /// 平方根 — 委托给 dart:math
  ///
  /// ⚡ 性能优化（v0.4.8）：
  /// - 旧实现：自定义牛顿迭代法，每次 20 次迭代
  /// - 新实现：dart:math 的 math.sqrt，CPU 指令级实现，快 ~50 倍
  double _sqrt(double x) => x > 0 ? math.sqrt(x) : 0.0;

  double _hash2(double x, double y) {
    final n = (x * 127.1 + y * 311.7);
    // 简单 fract(sin) 哈希
    final sinN = (n - (n.floor())) * 6.2831853;
    final s = sinN * 0.5;
    final result = (s.abs() * 43758.5453);
    return result - result.floor();
  }

  /// 生成导出文件名 — 在原文件名后添加 _edited 后缀
  String generateExportFileName(String originalName, String format) {
    final nameNoExt = p.basenameWithoutExtension(originalName);
    final ext = format.toLowerCase() == 'png' ? '.png' : '.jpg';
    return '${nameNoExt}_edited$ext';
  }
}