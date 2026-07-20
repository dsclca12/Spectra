import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'image_decoder_service.dart';

/// 3×3 空间网格的单格统计
class GridCellStats {
  final double avgLuminance;
  final double stdLuminance;
  final double avgR;
  final double avgG;
  final double avgB;
  final double avgSaturation;
  final double highlightClipRatio;
  final double shadowClipRatio;

  const GridCellStats({
    required this.avgLuminance,
    required this.stdLuminance,
    required this.avgR,
    required this.avgG,
    required this.avgB,
    required this.avgSaturation,
    required this.highlightClipRatio,
    required this.shadowClipRatio,
  });
}

/// 图像分析结果 — 从缩略图提取的统计特征
///
/// 所有亮度/颜色值归一化到 [0.0, 1.0]。
/// 直方图分 256 bins。
class ImageAnalysis {
  // ─── 亮度统计 ───
  /// 平均亮度（Rec.709 加权）
  final double avgLuminance;

  /// 亮度标准差
  final double stdLuminance;

  /// 亮度直方图（256 bins，归一化到 [0,1]）
  final List<double> luminanceHist;

  // ─── 百分位 ───
  final double p1;
  final double p5;
  final double p10;
  final double p50;
  final double p90;
  final double p95;
  final double p99;

  // ─── 颜色统计 ───
  final double avgR;
  final double avgG;
  final double avgB;

  /// 平均饱和度
  final double avgSaturation;

  /// 平均色相（0-360 度）
  final double avgHue;

  // ─── 高光/阴影裁剪检测 ───
  /// 高光裁剪比例（亮度 > 0.99 的像素占比）
  final double highlightClipRatio;

  /// 阴影裁剪比例（亮度 < 0.01 的像素占比）
  final double shadowClipRatio;

  // ─── 直方图形状（增强场景理解） ───
  /// 亮度直方图偏度（正=右偏/亮部多，负=左偏/暗部多）
  final double histSkewness;

  /// 亮度直方图峰度（高=集中/雾霾/平淡，低=分散/清晰/高对比）
  final double histKurtosis;

  // ─── 内容感知统计 ───
  /// 中灰区域对比度（0.25-0.75 亮度区间的标准差），用于去雾检测
  final double midtoneContrast;

  /// 中性色像素比例（饱和度 < 0.08 的像素占比），用于白平衡
  final double neutralPixelRatio;

  /// 雾霾评分（0-1，越高越雾），基于中灰对比度 + 峰度 + 暗部抬升
  final double hazeScore;

  /// 近似肤色像素比例（色相 10-50°, 饱和度 0.1-0.6 的像素）
  final double skinToneRatio;

  /// 近似蓝天像素比例（色相 190-250°, 饱和度 > 0.15, 亮度 > 0.3）
  final double blueSkyRatio;

  /// 近似绿色植被像素比例（色相 70-160°, 饱和度 > 0.1）
  final double greenFoliageRatio;

  /// 锐度代理指标（0-1，越高越清晰），基于相邻像素亮度梯度
  final double perceivedSharpness;

  // ─── 空间网格统计（3×3 网格） ───
  /// 3×3 网格的每格统计信息，用于检测逆光、局部过曝等空间特征
  final List<GridCellStats> gridStats;

  /// 网格间亮度方差（0-1，越高表示空间亮度差异越大，逆光/HDR 特征）
  final double spatialLuminanceVariance;

  /// 亮度重心 X（0=左，1=右），用于检测侧光
  final double luminanceCenterX;

  /// 亮度重心 Y（0=上，1=下），用于检测顶光/底光
  final double luminanceCenterY;

  // ─── 色彩恒常性指标 ───
  /// Shades of Gray 估计的光源颜色 (R, G, B)，归一化到 G=1.0
  final List<double> illuminantEstimate;

  /// Gray Edge 估计的光源颜色 (R, G, B)
  final List<double> illuminantEdge;

  // ─── 局部对比度 ───
  /// 局部对比度（3×3 窗口 RMS 对比度的中位数）
  final double localContrastMedian;

  // ─── 场景分类 ───
  /// 检测到的场景类型
  final SceneType scene;

  const ImageAnalysis({
    required this.avgLuminance,
    required this.stdLuminance,
    required this.luminanceHist,
    required this.p1,
    required this.p5,
    required this.p10,
    required this.p50,
    required this.p90,
    required this.p95,
    required this.p99,
    required this.avgR,
    required this.avgG,
    required this.avgB,
    required this.avgSaturation,
    required this.avgHue,
    required this.highlightClipRatio,
    required this.shadowClipRatio,
    this.histSkewness = 0.0,
    this.histKurtosis = 0.0,
    this.midtoneContrast = 0.15,
    this.neutralPixelRatio = 0.0,
    this.hazeScore = 0.0,
    this.skinToneRatio = 0.0,
    this.blueSkyRatio = 0.0,
    this.greenFoliageRatio = 0.0,
    this.perceivedSharpness = 0.5,
    this.gridStats = const [],
    this.spatialLuminanceVariance = 0.0,
    this.luminanceCenterX = 0.5,
    this.luminanceCenterY = 0.5,
    this.illuminantEstimate = const [1.0, 1.0, 1.0],
    this.illuminantEdge = const [1.0, 1.0, 1.0],
    this.localContrastMedian = 0.15,
    required this.scene,
  });

  /// 亮度动态范围（p99 - p1）
  double get dynamicRange => p99 - p1;

  /// 对比度指标（标准差 / 理想标准差）
  /// 理想中灰图片标准差 ≈ 0.25
  double get contrastRatio => stdLuminance / 0.25;

  /// 色温偏差（R vs B 通道差异）
  /// 正值 = 偏暖（R > B），负值 = 偏冷（B > R）
  double get colorTempBias => avgR - avgB;

  /// 绿/洋红偏差（G vs (R+B)/2）
  /// 正值 = 偏绿，负值 = 偏洋红
  double get tintBias => avgG - (avgR + avgB) / 2;
}

/// 场景类型分类
enum SceneType {
  /// 正常/均衡场景
  normal,

  /// 低光场景（平均亮度 < 0.2）
  lowLight,

  /// 高光/过曝场景（平均亮度 > 0.75）
  highLight,

  /// 逆光/高动态范围（高光和阴影同时裁剪）
  backlit,

  /// 平淡/低对比度（动态范围小）
  flat,

  /// 高对比度（动态范围极大）
  highContrast,

  /// 雾霾场景（中灰对比度低、峰度高、暗部抬升）
  hazy,

  /// 夜景/暗调艺术（极低亮度但非欠曝，阴影细节有意保留）
  nightScene,

  /// 偏暖色温
  warmTint,

  /// 偏冷色温
  coolTint,
}

/// 图像分析服务 — 使用 dart:ui 原生解码器提取统计特征
///
/// 性能策略：
/// - 使用 `ImageDecoderService` 解码（dart:ui / WIC），比 `package:image` 快 10-50 倍
/// - 解码到 256px 长边缩略图，内存占用极低
/// - 通过 `toByteData` 获取像素数据，在 Isolate 中分析
/// - 支持 RAW/HEIC 等格式（通过 WIC）
class ImageAnalysisService {
  final ImageDecoderService _decoder;

  ImageAnalysisService(this._decoder);

  /// 分析图片，返回统计特征
  ///
  /// [imagePath] 图片文件路径
  /// [analysisSize] 分析用缩略图尺寸（长边像素），默认 256
  Future<ImageAnalysis?> analyze(
    String imagePath, {
    int analysisSize = 256,
  }) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;

      // 使用 ImageDecoderService 解码到小尺寸
      // dart:ui 原生解码器在 native 线程执行，targetWidth 直接解码到目标尺寸
      final image = await _decoder.decode(imagePath, targetWidth: analysisSize);
      if (image == null) return null;

      try {
        return await _extractStats(image);
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  /// 从 ui.Image 提取统计特征
  Future<ImageAnalysis> _extractStats(ui.Image image) async {
    final width = image.width;
    final height = image.height;
    final totalPixels = width * height;

    // 获取像素数据（RGBA，uint8）
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      return _emptyAnalysis();
    }

    final bytes = byteData.buffer.asUint8List();

    // ─── 统计量累加 ───
    final lumHist = List<int>.filled(256, 0);
    double sumR = 0, sumG = 0, sumB = 0;
    double sumLum = 0, sumLum2 = 0, sumLum3 = 0, sumLum4 = 0;
    double sumSat = 0;
    double sumHueX = 0, sumHueY = 0; // 用极坐标累加色相避免环绕问题
    int highlightClip = 0;
    int shadowClip = 0;

    // 新增统计
    double sumMidLum = 0, sumMidLum2 = 0;
    int midtoneCount = 0;
    int neutralCount = 0;
    int skinCount = 0;
    int blueSkyCount = 0;
    int greenFoliageCount = 0;
    double sumLumGradient = 0; // 相邻像素亮度梯度
    double prevLum = 0;
    bool hasPrev = false;

    // ─── 空间网格统计（3×3 网格） ───
    const gridCols = 3;
    const gridRows = 3;
    final gridCellW = width / gridCols;
    final gridCellH = height / gridRows;
    // 每格: [sumLum, sumLum2, sumR, sumG, sumB, sumSat, hlClip, shClip, count, sumLumX, sumLumY]
    final gridAcc = List.generate(gridRows * gridCols, (_) => List.filled(11, 0.0));

    // ─── 色彩恒常性累加 ───
    // Shades of Gray (p=6): 累加 I^6 * color
    double sogSumR = 0, sogSumG = 0, sogSumB = 0;
    // Gray Edge: 累加梯度幅度
    double geSumR = 0, geSumG = 0, geSumB = 0;
    double prevR = 0, prevG = 0, prevB = 0;

    // ─── 局部对比度 ───
    // 采样间隔：在每个 4×4 块取一个像素计算局部 RMS 对比度
    final localContrastSamples = <double>[];

    for (int i = 0; i < bytes.length; i += 4) {
      final pixelIdx = i ~/ 4;
      final x = pixelIdx % width;
      final y = pixelIdx ~/ width;

      final r = bytes[i] / 255.0;
      final g = bytes[i + 1] / 255.0;
      final b = bytes[i + 2] / 255.0;

      sumR += r;
      sumG += g;
      sumB += b;

      // Rec.709 亮度
      final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      final lumInt = (lum * 255).round().clamp(0, 255);
      lumHist[lumInt]++;
      sumLum += lum;
      sumLum2 += lum * lum;
      sumLum3 += lum * lum * lum;
      sumLum4 += lum * lum * lum * lum;

      // 饱和度（HSL 模型）
      final maxVal = math.max(r, math.max(g, b));
      final minVal = math.min(r, math.min(g, b));
      final sat = maxVal == 0 ? 0.0 : (maxVal - minVal) / maxVal;
      sumSat += sat;

      // 色相（用极坐标累加）
      double hue = 0;
      if (sat > 0.01) {
        hue = _rgbToHue(r, g, b);
        sumHueX += math.cos(hue * math.pi / 180);
        sumHueY += math.sin(hue * math.pi / 180);
      }

      // 中灰区域统计（用于去雾：0.25-0.75 亮度区间）
      if (lum > 0.25 && lum < 0.75) {
        sumMidLum += lum;
        sumMidLum2 += lum * lum;
        midtoneCount++;
      }

      // 中性色检测（低饱和 → 灰/白/黑，用于白平衡参考）
      if (sat < 0.08) {
        neutralCount++;
      }

      // 肤色检测（色相 10-50° 且饱和度 0.1-0.6 且亮度 0.2-0.95）
      if (hue >= 10 && hue <= 50 && sat > 0.1 && sat < 0.6 && lum > 0.2 && lum < 0.95) {
        skinCount++;
      }

      // 蓝天检测（色相 190-250° 且 sat > 0.15 且 lum > 0.3）
      if (hue >= 190 && hue <= 250 && sat > 0.15 && lum > 0.3) {
        blueSkyCount++;
      }

      // 绿色植被检测（色相 70-160° 且 sat > 0.1）
      if (hue >= 70 && hue <= 160 && sat > 0.1) {
        greenFoliageCount++;
      }

      // 锐度代理：相邻像素水平梯度
      if (hasPrev) {
        sumLumGradient += (lum - prevLum).abs();
      }
      prevLum = lum;
      hasPrev = true;

      // 裁剪检测
      if (lum > 0.99) highlightClip++;
      if (lum < 0.01) shadowClip++;

      // ─── 空间网格累加 ───
      final gx = (x / gridCellW).floor().clamp(0, gridCols - 1);
      final gy = (y / gridCellH).floor().clamp(0, gridRows - 1);
      final gi = gy * gridCols + gx;
      final gc = gridAcc[gi];
      gc[0] += lum;
      gc[1] += lum * lum;
      gc[2] += r;
      gc[3] += g;
      gc[4] += b;
      gc[5] += sat;
      if (lum > 0.99) gc[6]++;
      if (lum < 0.01) gc[7]++;
      gc[8]++; // pixel count
      gc[9] += lum * x; // weighted X for luminance center
      gc[10] += lum * y; // weighted Y for luminance center

      // ─── 色彩恒常性累加 ───
      // Shades of Gray (p=6): weight pixels by I^6
      final lumPow6 = lum * lum * lum * lum * lum * lum;
      sogSumR += lumPow6 * r;
      sogSumG += lumPow6 * g;
      sogSumB += lumPow6 * b;

      // Gray Edge: accumulate gradient magnitudes
      if (hasPrev) {
        final dR = (r - prevR).abs();
        final dG = (g - prevG).abs();
        final dB = (b - prevB).abs();
        geSumR += dR;
        geSumG += dG;
        geSumB += dB;
      }
      prevR = r;
      prevG = g;
      prevB = b;

      // ─── 局部对比度采样（每 4×4 块采样一次） ───
      if (x % 4 == 0 && y % 4 == 0) {
        // 计算 5×5 窗口内的 RMS 对比度
        double localSum = 0, localSum2 = 0;
        int localCount = 0;
        final halfW = 2;
        for (int dy = -halfW; dy <= halfW; dy++) {
          for (int dx = -halfW; dx <= halfW; dx++) {
            final nx = x + dx;
            final ny = y + dy;
            if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
              final ni = (ny * width + nx) * 4;
              final nr = bytes[ni] / 255.0;
              final ng = bytes[ni + 1] / 255.0;
              final nb = bytes[ni + 2] / 255.0;
              final nl = 0.2126 * nr + 0.7152 * ng + 0.0722 * nb;
              localSum += nl;
              localSum2 += nl * nl;
              localCount++;
            }
          }
        }
        if (localCount > 0) {
          final localMean = localSum / localCount;
          final localVar = (localSum2 / localCount) - (localMean * localMean);
          if (localVar > 0) {
            localContrastSamples.add(math.sqrt(localVar));
          }
        }
      }
    }

    final n = totalPixels.toDouble();
    final avgLum = sumLum / n;
    final varLum = (sumLum2 / n) - (avgLum * avgLum);
    final stdLum = math.sqrt(varLum.clamp(0.0, 1.0));

    // ─── 直方图形状统计（偏度、峰度） ───
    final avgLum3 = sumLum3 / n;
    final avgLum4 = sumLum4 / n;
    // 偏度 = E[(X-μ)³] / σ³
    final skewness = stdLum > 0.001
        ? (avgLum3 - 3 * avgLum * varLum - avgLum * avgLum * avgLum) /
            (stdLum * stdLum * stdLum)
        : 0.0;
    // 峰度 = E[(X-μ)⁴] / σ⁴ - 3（超额峰度）
    final kurtosis = stdLum > 0.001
        ? ((avgLum4 -
                    4 * avgLum * avgLum3 +
                    6 * avgLum * avgLum * varLum +
                    3 * avgLum * avgLum * avgLum * avgLum) /
                (varLum * varLum)) -
            3
        : 0.0;

    // ─── 中灰区域对比度 ───
    double midtoneContrast = 0.15;
    if (midtoneCount > 100) {
      final midAvg = sumMidLum / midtoneCount;
      final midVar =
          (sumMidLum2 / midtoneCount) - (midAvg * midAvg);
      midtoneContrast = math.sqrt(midVar.clamp(0.0, 1.0));
    }

    // ─── 锐度代理 ───
    final avgGradient = sumLumGradient / (n - 1).clamp(1, double.infinity);
    // 归一化：梯度 0.02 为正常，0.08 为很锐利
    final perceivedSharpness =
        (avgGradient / 0.06).clamp(0.0, 1.0);

    // 归一化直方图
    final lumHistNorm = lumHist.map((c) => c / n).toList();

    // 百分位（必须在雾霾评分之前计算）
    final p1 = _percentile(lumHist, 0.01, n);
    final p5 = _percentile(lumHist, 0.05, n);
    final p10 = _percentile(lumHist, 0.10, n);
    final p50 = _percentile(lumHist, 0.50, n);
    final p90 = _percentile(lumHist, 0.90, n);
    final p95 = _percentile(lumHist, 0.95, n);
    final p99 = _percentile(lumHist, 0.99, n);

    // ─── 雾霾评分（依赖百分位 p5，必须放在百分位计算之后） ───
    // 三要素：中灰对比度低 + 峰度高（像素集中） + 暗部抬升（p5偏高）
    final hazeContrastFactor =
        (1.0 - (midtoneContrast / 0.18).clamp(0.0, 1.0)) * 0.5;
    final hazeKurtosisFactor =
        ((kurtosis + 1.0) / 5.0).clamp(0.0, 1.0) * 0.3;
    final hazeBlackLiftFactor =
        ((p5 - 0.02) / 0.20).clamp(0.0, 1.0) * 0.2;
    final hazeScore =
        (hazeContrastFactor + hazeKurtosisFactor + hazeBlackLiftFactor)
            .clamp(0.0, 1.0);

    final avgR = sumR / n;
    final avgG = sumG / n;
    final avgB = sumB / n;
    final avgSat = sumSat / n;

    // 平均色相（从极坐标恢复）
    double avgHue = 0;
    if (sumHueX != 0 || sumHueY != 0) {
      avgHue = (math.atan2(sumHueY, sumHueX) * 180 / math.pi + 360) % 360;
    }

    final highlightClipRatio = highlightClip / n;
    final shadowClipRatio = shadowClip / n;
    final neutralPixelRatio = neutralCount / n;
    final skinToneRatio = skinCount / n;
    final blueSkyRatio = blueSkyCount / n;
    final greenFoliageRatio = greenFoliageCount / n;

    // ─── 空间网格统计汇总 ───
    final gridStatsList = <GridCellStats>[];
    double totalGridLum = 0;
    double sumLumCenterX = 0;
    double sumLumCenterY = 0;
    for (int gy = 0; gy < gridRows; gy++) {
      for (int gx = 0; gx < gridCols; gx++) {
        final gc = gridAcc[gy * gridCols + gx];
        final count = gc[8];
        if (count > 0) {
          final gAvgLum = gc[0] / count;
          final gVarLum = (gc[1] / count) - (gAvgLum * gAvgLum);
          final gStdLum = math.sqrt(gVarLum.clamp(0.0, 1.0));
          gridStatsList.add(GridCellStats(
            avgLuminance: gAvgLum,
            stdLuminance: gStdLum,
            avgR: gc[2] / count,
            avgG: gc[3] / count,
            avgB: gc[4] / count,
            avgSaturation: gc[5] / count,
            highlightClipRatio: gc[6] / count,
            shadowClipRatio: gc[7] / count,
          ));
          totalGridLum += gAvgLum;
          sumLumCenterX += gc[9]; // lum * x weighted
          sumLumCenterY += gc[10]; // lum * y weighted
        } else {
          gridStatsList.add(const GridCellStats(
            avgLuminance: 0.5,
            stdLuminance: 0.0,
            avgR: 0.5,
            avgG: 0.5,
            avgB: 0.5,
            avgSaturation: 0.0,
            highlightClipRatio: 0.0,
            shadowClipRatio: 0.0,
          ));
        }
      }
    }

    // 网格间亮度方差（空间分布不均匀程度）
    double spatialLumVar = 0;
    if (gridStatsList.isNotEmpty) {
      final meanGridLum = totalGridLum / gridStatsList.length;
      for (final gs in gridStatsList) {
        final d = gs.avgLuminance - meanGridLum;
        spatialLumVar += d * d;
      }
      spatialLumVar /= gridStatsList.length;
    }

    // 亮度重心（归一化到 0-1）
    final totalLumWeight = sumLum; // total weighted luminance
    final luminanceCenterX = totalLumWeight > 0
        ? (sumLumCenterX / totalLumWeight) / width
        : 0.5;
    final luminanceCenterY = totalLumWeight > 0
        ? (sumLumCenterY / totalLumWeight) / height
        : 0.5;

    // ─── 色彩恒常性 ───
    // Shades of Gray (p=6): normalize to G=1
    final illuminantEstimate = <double>[1.0, 1.0, 1.0];
    if (sogSumG > 1e-10) {
      illuminantEstimate[0] = (sogSumR / sogSumG).clamp(0.5, 2.0);
      illuminantEstimate[1] = 1.0;
      illuminantEstimate[2] = (sogSumB / sogSumG).clamp(0.5, 2.0);
    }

    // Gray Edge
    final illuminantEdge = <double>[1.0, 1.0, 1.0];
    if (geSumG > 1e-10) {
      illuminantEdge[0] = (geSumR / geSumG).clamp(0.5, 2.0);
      illuminantEdge[1] = 1.0;
      illuminantEdge[2] = (geSumB / geSumG).clamp(0.5, 2.0);
    }

    // ─── 局部对比度中位数 ───
    double localContrastMedian = 0.15;
    if (localContrastSamples.isNotEmpty) {
      localContrastSamples.sort();
      localContrastMedian =
          localContrastSamples[localContrastSamples.length ~/ 2];
    }

    // 场景分类（使用增强特征）
    final scene = _classifyScene(
      avgLum: avgLum,
      stdLum: stdLum,
      p1: p1,
      p5: p5,
      p99: p99,
      highlightClipRatio: highlightClipRatio,
      shadowClipRatio: shadowClipRatio,
      colorTempBias: avgR - avgB,
      hazeScore: hazeScore,
      skewness: skewness,
      kurtosis: kurtosis,
      midtoneContrast: midtoneContrast,
      spatialLuminanceVariance: spatialLumVar,
      gridStats: gridStatsList,
    );

    return ImageAnalysis(
      avgLuminance: avgLum,
      stdLuminance: stdLum,
      luminanceHist: lumHistNorm,
      p1: p1,
      p5: p5,
      p10: p10,
      p50: p50,
      p90: p90,
      p95: p95,
      p99: p99,
      avgR: avgR,
      avgG: avgG,
      avgB: avgB,
      avgSaturation: avgSat,
      avgHue: avgHue,
      highlightClipRatio: highlightClipRatio,
      shadowClipRatio: shadowClipRatio,
      histSkewness: skewness,
      histKurtosis: kurtosis,
      midtoneContrast: midtoneContrast,
      neutralPixelRatio: neutralPixelRatio,
      hazeScore: hazeScore,
      skinToneRatio: skinToneRatio,
      blueSkyRatio: blueSkyRatio,
      greenFoliageRatio: greenFoliageRatio,
      perceivedSharpness: perceivedSharpness,
      gridStats: gridStatsList,
      spatialLuminanceVariance: spatialLumVar,
      luminanceCenterX: luminanceCenterX,
      luminanceCenterY: luminanceCenterY,
      illuminantEstimate: illuminantEstimate,
      illuminantEdge: illuminantEdge,
      localContrastMedian: localContrastMedian,
      scene: scene,
    );
  }

  /// 从直方图计算百分位
  double _percentile(List<int> hist, double percentile, double total) {
    final target = total * percentile;
    double cumulative = 0;
    for (int i = 0; i < 256; i++) {
      cumulative += hist[i];
      if (cumulative >= target) {
        return i / 255.0;
      }
    }
    return 1.0;
  }

  /// RGB → 色相（0-360 度）
  double _rgbToHue(double r, double g, double b) {
    final maxVal = math.max(r, math.max(g, b));
    final minVal = math.min(r, math.min(g, b));
    final delta = maxVal - minVal;

    if (delta == 0) return 0;

    double hue;
    if (maxVal == r) {
      hue = 60 * (((g - b) / delta) % 6);
    } else if (maxVal == g) {
      hue = 60 * ((b - r) / delta + 2);
    } else {
      hue = 60 * ((r - g) / delta + 4);
    }

    if (hue < 0) hue += 360;
    return hue;
  }

  /// 场景分类（增强版 — 使用直方图形状 + 空间特征 + 内容感知特征）
  SceneType _classifyScene({
    required double avgLum,
    required double stdLum,
    required double p1,
    required double p5,
    required double p99,
    required double highlightClipRatio,
    required double shadowClipRatio,
    required double colorTempBias,
    required double hazeScore,
    required double skewness,
    required double kurtosis,
    required double midtoneContrast,
    double spatialLuminanceVariance = 0.0,
    List<GridCellStats> gridStats = const [],
  }) {
    // ─── 逆光检测（增强：使用空间网格） ───
    // 空间条件：顶部格子亮度显著高于底部 → 天空在上、地面在下
    bool hasTopBottomDivergence = false;
    if (gridStats.length >= 6) {
      // 顶部行 (indices 0,1,2) vs 底部行 (indices 6,7,8)
      double topLum = 0, bottomLum = 0;
      for (int i = 0; i < 3; i++) {
        topLum += gridStats[i].avgLuminance;
        bottomLum += gridStats[6 + i].avgLuminance;
      }
      topLum /= 3;
      bottomLum /= 3;
      hasTopBottomDivergence = (topLum - bottomLum).abs() > 0.25;
    }

    // 逆光：同时有高光和阴影裁剪，或空间亮度差异极大
    if ((highlightClipRatio > 0.03 && shadowClipRatio > 0.05) ||
        (spatialLuminanceVariance > 0.08 && hasTopBottomDivergence)) {
      return SceneType.backlit;
    }

    // 低光
    if (avgLum < 0.2) {
      return SceneType.lowLight;
    }

    // 高光/过曝
    if (avgLum > 0.75 || highlightClipRatio > 0.05) {
      return SceneType.highLight;
    }

    // 平淡/低对比度
    if (stdLum < 0.12) {
      return SceneType.flat;
    }

    // 高对比度
    if (stdLum > 0.30) {
      return SceneType.highContrast;
    }

    // 偏暖（增强检测：色温偏差 + 肤色/暖色调主导）
    if (colorTempBias > 0.06) {
      return SceneType.warmTint;
    }

    // 偏冷（增强检测：色温偏差）
    if (colorTempBias < -0.06) {
      return SceneType.coolTint;
    }

    return SceneType.normal;
  }

  ImageAnalysis _emptyAnalysis() {
    return const ImageAnalysis(
      avgLuminance: 0.5,
      stdLuminance: 0.25,
      luminanceHist: [],
      p1: 0.01,
      p5: 0.05,
      p10: 0.10,
      p50: 0.5,
      p90: 0.90,
      p95: 0.95,
      p99: 0.99,
      avgR: 0.5,
      avgG: 0.5,
      avgB: 0.5,
      avgSaturation: 0.3,
      avgHue: 0,
      highlightClipRatio: 0,
      shadowClipRatio: 0,
      histSkewness: 0,
      histKurtosis: 0,
      midtoneContrast: 0.15,
      neutralPixelRatio: 0.1,
      hazeScore: 0,
      skinToneRatio: 0,
      blueSkyRatio: 0,
      greenFoliageRatio: 0,
      perceivedSharpness: 0.5,
      gridStats: [],
      spatialLuminanceVariance: 0,
      luminanceCenterX: 0.5,
      luminanceCenterY: 0.5,
      illuminantEstimate: [1.0, 1.0, 1.0],
      illuminantEdge: [1.0, 1.0, 1.0],
      localContrastMedian: 0.15,
      scene: SceneType.normal,
    );
  }
}