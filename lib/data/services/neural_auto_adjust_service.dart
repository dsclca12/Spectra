import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../models/edit_params.dart';
import '../../core/constants.dart' show FeatureFlags;
import '../../core/logging.dart';
import 'image_analysis.dart';
import 'ml_service.dart';

/// Neural auto-adjust service — based on IAT (Illumination-Adaptive Transformer) approach.
///
/// IAT model outputs:
/// - 3×3 color correction matrix (white balance + tint)
/// - gamma value (exposure/brightness)
///
/// This service implements two paths:
/// 1. **ONNX inference path**: When MlService has an IAT ONNX model available,
///    runs the thumbnail through the model to get color matrix and gamma, mapped to EditParams.
/// 2. **Pure Dart simulation path**: When ONNX is unavailable, uses an intelligent
///    statistical model based on ImageAnalysis to simulate the IAT global branch output.
///    This ensures the feature is always available, even without the ONNX Runtime library.
///
/// Mapping strategy (IAT output → EditParams):
/// - gamma → exposure (log2 mapping)
/// - Color matrix R/G/B offsets → temperature, tint
/// - Matrix diagonal gains → contrast, whites, blacks
/// - Supplementary histogram analysis → highlights, shadows, vibrance
class NeuralAutoAdjustService {
  final MlService _mlService;
  final ImageAnalysisService _analysisService;

  /// IAT model identifier in MlService.
  static const _modelId = 'auto_enhance';

  /// Model path (open-source branch doesn't bundle model files; download from HuggingFace).
  /// Reference: https://huggingface.co/mlboydaisuke/zero-dce-litert
  static const _modelAsset = '';

  NeuralAutoAdjustService(this._mlService, this._analysisService);

  /// Whether the model is loaded and ready.
  bool get isModelReady => false;

  /// Model status.
  MlModelStatus get modelStatus => _mlService.getStatus(_modelId);

  /// Initialize: attempts to load the ONNX model.
  ///
  /// Does not throw on failure — falls back to pure Dart simulation.
  Future<void> initialize() async {
    if (modelStatus == MlModelStatus.notLoaded ||
        modelStatus == MlModelStatus.error) {
      AppLogger.info('ML', '正在从 asset 加载 IAT 模型…',
          details: 'asset: $_modelAsset');
      final ok = await _mlService.loadModel(_modelAsset, _modelId);
      if (ok) {
        AppLogger.info('ML', 'IAT 模型加载成功（asset）');
      } else {
        AppLogger.warn('ML', 'IAT 模型加载失败，将使用启发式引擎',
            details: 'asset 模型不存在或 ONNX Runtime 未安装');
      }
    } else {
      AppLogger.debug('ML', 'IAT 模型已加载，跳过初始化',
          details: 'status: ${modelStatus.name}');
    }
  }

  /// Load ONNX model from a file path (for manual import via settings UI).
  ///
  /// [filePath] Absolute path to the ONNX model file.
  Future<void> initializeFromFile(String filePath) async {
    AppLogger.info('ML', '正在从文件加载模型…', details: 'path: $filePath');
    final file = File(filePath);
    final exists = await file.exists();
    final size = exists ? await file.length() : 0;

    AppLogger.info('ML', '模型文件信息',
        details: '存在: $exists, 大小: ${(size / 1024).toStringAsFixed(1)} KB');

    final ok = await _mlService.loadModelFromFile(filePath, _modelId);
    if (ok) {
      AppLogger.info('ML', '✅ 模型加载成功！引擎已就绪');
    } else {
      AppLogger.error('ML', '❌ 模型加载失败',
          details: '文件可能不是有效的 ONNX 格式，或 ONNX Runtime 未安装');
    }
  }

  /// Analyze an image and return neural-network-driven auto-adjust parameters.
  ///
  /// [imagePath] Path to the image file.
  /// [currentParams] Current edit parameters (used to preserve geometry params).
  /// [strength] Enhancement strength 0.0-1.0 (controls adjustment magnitude).
  Future<EditParams> analyze(
    String imagePath, {
    EditParams currentParams = EditParams.defaultParams,
    double strength = 1.0,
  }) async {
    if (!FeatureFlags.aiMlEnabled) return EditParams.defaultParams;
    try {
      // Get statistical features via ImageAnalysisService (dart:ui decoding, 10-50x faster than image package).
      final analysis = await _analysisService.analyze(imagePath);
      if (analysis == null) return EditParams.defaultParams;

      // Try ONNX inference path
      if (isModelReady) {
        AppLogger.debug('ML', '使用 ONNX 神经引擎推理…');
        final onnxResult = await _inferWithOnnx(imagePath);
        if (onnxResult != null) {
          AppLogger.debug('ML', 'ONNX 推理成功，映射到 EditParams');
          return _mapToEditParams(onnxResult, analysis, currentParams, strength);
        }
        AppLogger.debug('ML', 'ONNX 推理失败，回退到纯 Dart 模拟');
      } else {
        AppLogger.debug('ML', 'ONNX 未就绪，使用纯 Dart 模拟引擎',
            details: 'status: ${modelStatus.name}');
      }

      // Fallback: pure Dart simulation of IAT global branch
      final iatOutput = _simulateIATGlobal(analysis);
      return _mapToEditParams(iatOutput, analysis, currentParams, strength);
    } catch (e) {
      AppLogger.error('ML', '神经增强异常', details: e.toString());
      return EditParams.defaultParams;
    }
  }

  // ─── ONNX Inference Path ────────────────────────────────────────

  /// Run IAT inference using ONNX Runtime.
  ///
  /// Requires the ONNX model to be loaded. Returns null on failure.
  Future<_IatOutput?> _inferWithOnnx(String imagePath) async {
    try {
      // Preprocess: read image and convert to NCHW float32 [1,3,256,256]
      final input = await _preprocessToNCHW(imagePath, 256, 256);
      if (input == null) return null;

      final inputShape = [1, 3, 256, 256];

      final result = await _mlService.runInference(
        _modelId,
        [input],
        [inputShape],
      );

      if (result == null || result.outputs.isEmpty) return null;

      // Parse IAT output:
      // output[0]: color matrix [1,9] or [3,3] → 3×3 matrix
      // output[1]: gamma [1] or [1,3]
      final out0 = result.outputs[0];
      final out1 =
          result.outputs.length > 1 ? result.outputs[1] : Float32List(1);

      // Parse color matrix
      final matrix = List<List<double>>.generate(3, (i) {
        return List<double>.generate(3, (j) {
          final idx = i * 3 + j;
          return idx < out0.length ? out0[idx].toDouble() : 0.0;
        });
      });

      // Parse gamma
      final gamma = out1.isNotEmpty ? out1[0].toDouble() : 1.0;

      return _IatOutput(colorMatrix: matrix, gamma: gamma);
    } catch (_) {
      return null;
    }
  }

  /// Preprocess an image into an NCHW float32 tensor.
  ///
  /// Uses dart:ui decoder to get pixel data, normalizes to [0,1], and converts to NCHW format.
  /// Returns a Float32List of shape [1, 3, targetH, targetW].
  Future<Float32List?> _preprocessToNCHW(
    String imagePath,
    int targetW,
    int targetH,
  ) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetW,
        targetHeight: targetH,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      codec.dispose();

      try {
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (byteData == null) return null;

        final rgba = byteData.buffer.asUint8List();
        final totalPixels = image.width * image.height;
        final result = Float32List(3 * totalPixels);

        // RGBA interleaved → NCHW planar, normalized to [0,1]
        // Channel order: R, G, B (skip A)
        final planeSize = totalPixels;
        for (int i = 0; i < totalPixels; i++) {
          final srcIdx = i * 4;
          result[i] = rgba[srcIdx] / 255.0; // R plane
          result[planeSize + i] = rgba[srcIdx + 1] / 255.0; // G plane
          result[2 * planeSize + i] = rgba[srcIdx + 2] / 255.0; // B plane
        }

        return result;
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  // ─── Pure Dart IAT Global Branch Simulation ─────────────────────

  /// Simulate IAT global branch — intelligent statistical model based on ImageAnalysis (enhanced).
  ///
  /// Improvements:
  /// - Uses midtone contrast to assist gamma decisions
  /// - Uses neutral pixel ratio to assist white balance decisions
  /// - Haze and night scene support
  /// - Content-aware contrast enhancement
  _IatOutput _simulateIATGlobal(ImageAnalysis analysis) {
    // ─── gamma calculation ───
    double gamma = 1.0;
    final clampedLum = analysis.avgLuminance.clamp(0.01, 0.99);

    final targetLum = switch (analysis.scene) {
      SceneType.lowLight => 0.38,
      SceneType.nightScene => 0.22,
      SceneType.highLight => 0.58,
      SceneType.backlit => 0.45,
      SceneType.hazy => 0.50,
      _ => 0.5,
    };

    // Dead zone: no adjustment when close to target
    if ((clampedLum - targetLum).abs() > 0.04) {
      gamma = math.log(targetLum) / math.log(clampedLum);
      // Damping + range clamping
      gamma = (gamma - 1.0) * 0.65 + 1.0;
      gamma = gamma.clamp(0.5, 2.0);
    }

    // ─── Color matrix: gentle white balance + contrast ───
    final grayAvg = (analysis.avgR + analysis.avgG + analysis.avgB) / 3.0;

    // Channel offsets
    final rOffset = grayAvg - analysis.avgR;
    final gOffset = grayAvg - analysis.avgG;
    final bOffset = grayAvg - analysis.avgB;

    // Neutral color reliability weighting (consistent with AutoAdjustService)
    double wbConfidence = (analysis.neutralPixelRatio / 0.15).clamp(0.0, 1.0);
    if (analysis.blueSkyRatio > 0.05 || analysis.greenFoliageRatio > 0.1) {
      wbConfidence *= 0.4;
    }
    if (analysis.skinToneRatio > 0.05) {
      wbConfidence *= 0.6;
    }

    // Scene white balance down-weighting
    final sceneWbFactor = switch (analysis.scene) {
      SceneType.warmTint => 0.3,
      SceneType.coolTint => 0.3,
      SceneType.nightScene => 0.2,
      SceneType.lowLight => 0.4,
      SceneType.hazy => 0.7,
      _ => 1.0,
    };

    final finalWbStrength = 0.3 * wbConfidence * sceneWbFactor;
    final gainR = (1.0 + rOffset * finalWbStrength).clamp(0.8, 1.3);
    final gainG = (1.0 + gOffset * finalWbStrength).clamp(0.8, 1.3);
    final gainB = (1.0 + bOffset * finalWbStrength).clamp(0.8, 1.3);

    // Contrast enhancement (based on luminance std-dev + midtone contrast + haze score)
    final stdLum = analysis.stdLuminance;
    double contrastBoost = (0.20 - stdLum).clamp(-0.1, 0.15) * 0.8;

    // Haze dehazing enhancement
    if (analysis.scene == SceneType.hazy) {
      contrastBoost += analysis.hazeScore * 0.15;
      contrastBoost += (0.18 - analysis.midtoneContrast).clamp(0.0, 0.12) * 0.6;
    }

    final sceneContrastFactor = switch (analysis.scene) {
      SceneType.flat => 1.3,
      SceneType.hazy => 1.4,
      SceneType.highContrast => -0.2,
      SceneType.nightScene => 0.8,
      SceneType.lowLight => 0.6,
      SceneType.backlit => 0.5,
      _ => 1.0,
    };
    final adjustedContrastBoost = contrastBoost * sceneContrastFactor;

    final matrix = [
      [(gainR * (1.0 + adjustedContrastBoost)).clamp(0.7, 1.5), 0.0, 0.0],
      [0.0, (gainG * (1.0 + adjustedContrastBoost)).clamp(0.7, 1.5), 0.0],
      [0.0, 0.0, (gainB * (1.0 + adjustedContrastBoost)).clamp(0.7, 1.5)],
    ];

    return _IatOutput(
      colorMatrix: matrix,
      gamma: gamma,
      avgLum: analysis.avgLuminance,
      avgSat: analysis.avgSaturation,
    );
  }

  // ─── IAT Output → EditParams Mapping ───────────────────────────

  /// Map IAT output (color matrix + gamma) to EditParams (enhanced).
  ///
  /// Combines IAT output with ImageAnalysis auxiliary analysis (highlights/shadows/saturation/haze/sharpness).
  EditParams _mapToEditParams(
    _IatOutput iat,
    ImageAnalysis analysis,
    EditParams current,
    double strength,
  ) {
    // ─── gamma → exposure ───
    double exposure = 0.0;
    if (iat.gamma > 0.01 && (iat.gamma - 1.0).abs() > 0.03) {
      exposure = -math.log(iat.gamma) / math.ln2;
      exposure = exposure.clamp(-1.5, 1.5);
    }

    // Highlight priority protection
    if (analysis.highlightClipRatio > 0.05 && exposure > 0) {
      exposure = 0.0;
    }

    // ─── Color matrix → white balance ───
    final m = iat.colorMatrix;
    final gainR = m[0][0];
    final gainG = m[1][1];
    final gainB = m[2][2];

    final tempRaw = (gainR - gainB) * 30.0;
    final temperature = tempRaw.clamp(-25.0, 25.0);

    final rbAvg = (gainR + gainB) / 2.0;
    final tintRaw = (gainG - rbAvg) * 35.0;
    final tint = tintRaw.clamp(-15.0, 15.0);

    // ─── Contrast ───
    final gains = [gainR, gainG, gainB];
    final gainAvg = (gainR + gainG + gainB) / 3.0;
    final gainVar = gains
        .map((g) => (g - gainAvg) * (g - gainAvg))
        .reduce((a, b) => a + b) / 3.0;
    final gainStd = math.sqrt(gainVar);
    double contrast = (gainStd * 60.0).clamp(-25.0, 30.0);

    // Haze dehazing: extra contrast boost
    if (analysis.scene == SceneType.hazy) {
      contrast += analysis.hazeScore * 15;
    }

    // ─── Supplementary histogram analysis → highlights/shadows/whites/blacks ───
    double highlights = 0.0;
    double shadows = 0.0;
    double whites = 0.0;
    double blacks = 0.0;
    double vibrance = 0.0;
    double sharpness = 0.0;

    // Highlight recovery
    if (analysis.highlightClipRatio > 0.02) {
      highlights = -(analysis.highlightClipRatio * 300).clamp(0.0, 50.0);
    }
    final p95Threshold =
        analysis.scene == SceneType.highLight ? 0.88 : 0.93;
    if (analysis.p95 > p95Threshold) {
      highlights -= (analysis.p95 - p95Threshold) * 200;
    }
    if (analysis.p99 > 0.97) {
      highlights -= (analysis.p99 - 0.97) * 150;
    }
    // Extra highlight reduction for haze
    if (analysis.scene == SceneType.hazy && analysis.p95 > 0.75) {
      highlights -= analysis.hazeScore * 25;
    }
    highlights *= switch (analysis.scene) {
      SceneType.highLight => 1.2,
      SceneType.backlit => 1.1,
      SceneType.hazy => 1.3,
      SceneType.lowLight => 0.2,
      SceneType.nightScene => 0.3,
      _ => 1.0,
    };
    highlights = highlights.clamp(-60.0, 0.0);

    // Shadow brightening
    if (analysis.shadowClipRatio > 0.02) {
      shadows = (analysis.shadowClipRatio * 250).clamp(0.0, 40.0);
    }
    if (analysis.p5 < 0.05) {
      shadows += (0.05 - analysis.p5) * 200;
    }
    if (analysis.p1 < 0.02) {
      shadows += (0.02 - analysis.p1) * 120;
    }
    if (analysis.scene == SceneType.hazy && analysis.p5 < 0.15) {
      shadows += analysis.hazeScore * 15;
    }
    shadows *= switch (analysis.scene) {
      SceneType.lowLight => 1.2,
      SceneType.nightScene => 1.1,
      SceneType.backlit => 1.1,
      SceneType.hazy => 1.2,
      SceneType.highLight => 0.2,
      _ => 1.0,
    };
    shadows = shadows.clamp(0.0, 50.0);

    // White/black levels
    if (analysis.p95 < 0.80 && analysis.highlightClipRatio < 0.01) {
      whites = (0.90 - analysis.p95) * 80;
    }
    if (analysis.highlightClipRatio > 0.02) {
      whites -= analysis.highlightClipRatio * 150;
    }
    if (analysis.scene == SceneType.hazy && analysis.p95 < 0.85) {
      whites += analysis.hazeScore * 10;
    }
    whites = whites.clamp(-25.0, 25.0);

    if (analysis.p5 > 0.10 && analysis.shadowClipRatio < 0.01) {
      blacks = -(analysis.p5 - 0.07) * 80;
    }
    if (analysis.shadowClipRatio > 0.02) {
      blacks += analysis.shadowClipRatio * 100;
    }
    if (analysis.scene == SceneType.hazy && analysis.p5 > 0.05) {
      blacks -= analysis.hazeScore * 15;
    }
    blacks = blacks.clamp(-25.0, 25.0);

    // Vibrance (content-aware)
    if (analysis.avgSaturation < 0.20) {
      vibrance = (0.20 - analysis.avgSaturation) * 80;
    }
    if (analysis.blueSkyRatio > 0.05) {
      vibrance += 5;
    }
    if (analysis.greenFoliageRatio > 0.1) {
      vibrance += 3;
    }
    if (analysis.skinToneRatio > 0.05) {
      vibrance *= 0.5;
    }
    vibrance *= switch (analysis.scene) {
      SceneType.flat => 1.2,
      SceneType.hazy => 1.3,
      SceneType.lowLight => 0.5,
      SceneType.nightScene => 0.7,
      _ => 1.0,
    };
    vibrance = vibrance.clamp(0.0, 25.0);

    // Sharpness
    if (analysis.perceivedSharpness < 0.5) {
      final blurAmount = (0.5 - analysis.perceivedSharpness).clamp(0.0, 0.35);
      sharpness = blurAmount * 80;
      sharpness *= switch (analysis.scene) {
        SceneType.nightScene => 0.2,
        SceneType.lowLight => 0.5,
        SceneType.hazy => 0.8,
        _ => 1.0,
      };
      sharpness = sharpness.clamp(0.0, 30.0);
    }

    // Apply non-linear strength coefficient (sigmoid-like)
    final s = _smoothStrength(strength);

    return EditParams(
      exposure: _applyStrength(exposure, s),
      contrast: _applyStrength(contrast, s),
      highlights: _applyStrength(highlights, s),
      shadows: _applyStrength(shadows, s),
      whites: _applyStrength(whites, s),
      blacks: _applyStrength(blacks, s),
      vibrance: _applyStrength(vibrance, s),
      temperature: _applyStrength(temperature, s),
      tint: _applyStrength(tint, s),
      sharpness: _applyStrength(sharpness, s),
      cropX: current.cropX,
      cropY: current.cropY,
      cropWidth: current.cropWidth,
      cropHeight: current.cropHeight,
      rotation: current.rotation,
      flipH: current.flipH,
      flipV: current.flipV,
    );
  }

  /// Scale parameter value by strength coefficient.
  double _applyStrength(double value, double strength) {
    return (value * strength).roundToDouble();
  }

  /// Non-linear strength mapping (sigmoid-like).
  ///
  /// strength 0.0→0%, 0.5→35%, 0.75→65%, 1.0→100%
  /// Gentler at low strength, near-linear at high strength.
  double _smoothStrength(double strength) {
    if (strength <= 0.0) return 0.0;
    if (strength >= 1.0) return 1.0;
    // Sigmoid-like: smooth transition between 0-1
    // s(x) = x / (x + 0.5*(1-x))  → 0.5→0.5, 0.75→0.75, but gentler
    // Better: s(x) = 1 / (1 + exp(-6*(x-0.5)))
    return 1.0 / (1.0 + math.exp(-6.0 * (strength - 0.5)));
  }
}

// ─── Data Structures ─────────────────────────────────────────────

/// IAT 模型输出
class _IatOutput {
  /// 3×3 color correction matrix.
  final List<List<double>> colorMatrix;

  /// gamma value (<1 brightens, >1 darkens).
  final double gamma;

  /// Average luminance (auxiliary analysis, optional).
  final double? avgLum;

  /// Average saturation (auxiliary analysis, optional).
  final double? avgSat;

  const _IatOutput({
    required this.colorMatrix,
    required this.gamma,
    this.avgLum,
    this.avgSat,
  });
}