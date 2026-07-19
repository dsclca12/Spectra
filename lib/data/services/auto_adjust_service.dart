import 'dart:math' as math;

import '../models/edit_params.dart';
import '../../core/constants.dart' show FeatureFlags;
import '../../core/logging.dart';
import 'image_analysis.dart';
import 'neural_auto_adjust_service.dart';

/// Auto-adjust engine type.
enum AutoAdjustEngine {
  /// Neural network driven (IAT model).
  neural,
  /// Histogram heuristic algorithm.
  heuristic,
  /// Auto-select: neural first, fall back to heuristic.
  auto,
}

/// Auto-adjust service — Facade, unified interface supporting multiple engines.
///
/// Engine options:
/// - **neural**: Based on IAT (Illumination-Adaptive Transformer) neural network,
///   outputs color matrix + gamma → mapped to EditParams. Requires ONNX Runtime or pure Dart simulation.
/// - **heuristic**: Scene-aware histogram analysis based on thumbnails (256px long edge):
///   - Scene classification (low-light/highlight/backlit/flat/high-contrast/color-cast)
///   - Adaptive exposure: adjusts target brightness based on scene type
///   - Adaptive contrast: percentile stretching + scene intensity adjustment
///   - Smart white balance: gray-world assumption + color temperature protection
///   - Highlight/shadow recovery: clip detection based
///   - Vibrance: protects skin tones, boosts low-saturation areas
/// - **auto**: Prioritizes neural engine, falls back to heuristic when unavailable
class AutoAdjustService {
  final NeuralAutoAdjustService? _neuralService;
  final ImageAnalysisService _analysisService;

  AutoAdjustService({
    NeuralAutoAdjustService? neuralService,
    required ImageAnalysisService analysisService,
  })  : _neuralService = neuralService,
        _analysisService = analysisService;

  /// Analyze an image and return auto-adjusted edit parameters.
  ///
  /// [imagePath] Path to the image file.
  /// [preserveUserEdits] Whether to preserve user-adjusted parameters (true=fill unadjusted only).
  /// [currentParams] Current edit parameters (used for preserveUserEdits mode).
  /// [engine] Which engine to use (default auto).
  /// [strength] Neural engine enhancement strength 0.0-1.0.
  Future<EditParams> analyze(
    String imagePath, {
    bool preserveUserEdits = false,
    EditParams currentParams = EditParams.defaultParams,
    AutoAdjustEngine engine = AutoAdjustEngine.auto,
    double strength = 1.0,
  }) async {
    if (!FeatureFlags.aiMlEnabled) return EditParams.defaultParams;
    EditParams autoParams;

    switch (engine) {
      case AutoAdjustEngine.neural:
        autoParams = await analyzeNeural(
          imagePath,
          currentParams: currentParams,
          strength: strength,
        );
        break;
      case AutoAdjustEngine.heuristic:
        autoParams = await analyzeHeuristic(
          imagePath,
          preserveUserEdits: preserveUserEdits,
          currentParams: currentParams,
        );
        break;
      case AutoAdjustEngine.auto:
        // Neural first, fall back to heuristic
        if (_neuralService != null) {
          AppLogger.debug('AutoAdjust', '自动模式：尝试神经引擎…');
          autoParams = await analyzeNeural(
            imagePath,
            currentParams: currentParams,
            strength: strength,
          );
          // If neural engine returns default values (failure), fall back to heuristic
          if (autoParams == EditParams.defaultParams) {
            AppLogger.info('AutoAdjust', '神经引擎未就绪，回退到启发式引擎');
            autoParams = await analyzeHeuristic(
              imagePath,
              preserveUserEdits: preserveUserEdits,
              currentParams: currentParams,
            );
          } else {
            AppLogger.info('AutoAdjust', '使用神经引擎调整');
          }
        } else {
          AppLogger.info('AutoAdjust', '使用启发式引擎调整');
          autoParams = await analyzeHeuristic(
            imagePath,
            preserveUserEdits: preserveUserEdits,
            currentParams: currentParams,
          );
        }
        break;
    }

    if (preserveUserEdits) {
      return _mergePreservingUserEdits(autoParams, currentParams);
    }

    return autoParams;
  }

  /// Neural network-driven auto-adjustment.
  Future<EditParams> analyzeNeural(
    String imagePath, {
    EditParams currentParams = EditParams.defaultParams,
    double strength = 1.0,
  }) async {
    if (_neuralService == null) return EditParams.defaultParams;

    try {
      return await _neuralService.analyze(
        imagePath,
        currentParams: currentParams,
        strength: strength,
      );
    } catch (_) {
      return EditParams.defaultParams;
    }
  }

  /// Heuristic auto-adjustment — scene-aware intelligent histogram algorithm.
  Future<EditParams> analyzeHeuristic(
    String imagePath, {
    bool preserveUserEdits = false,
    EditParams currentParams = EditParams.defaultParams,
  }) async {
    try {
      final analysis = await _analysisService.analyze(imagePath);
      if (analysis == null) return EditParams.defaultParams;

      final autoParams = _computeAutoParams(analysis);

      // Preserve geometry params, override color params
      return autoParams.copyWith(
        cropX: currentParams.cropX,
        cropY: currentParams.cropY,
        cropWidth: currentParams.cropWidth,
        cropHeight: currentParams.cropHeight,
        rotation: currentParams.rotation,
        flipH: currentParams.flipH,
        flipV: currentParams.flipV,
      );
    } catch (_) {
      return EditParams.defaultParams;
    }
  }

  /// Merge auto-adjust params with user-adjusted params (fill unadjusted items only).
  EditParams _mergePreservingUserEdits(
    EditParams autoParams,
    EditParams current,
  ) {
    return EditParams(
      exposure: current.exposure != 0.0 ? current.exposure : autoParams.exposure,
      contrast: current.contrast != 0.0 ? current.contrast : autoParams.contrast,
      highlights: current.highlights != 0.0 ? current.highlights : autoParams.highlights,
      shadows: current.shadows != 0.0 ? current.shadows : autoParams.shadows,
      whites: current.whites != 0.0 ? current.whites : autoParams.whites,
      blacks: current.blacks != 0.0 ? current.blacks : autoParams.blacks,
      saturation: current.saturation != 0.0 ? current.saturation : autoParams.saturation,
      vibrance: current.vibrance != 0.0 ? current.vibrance : autoParams.vibrance,
      temperature: current.temperature != 0.0 ? current.temperature : autoParams.temperature,
      tint: current.tint != 0.0 ? current.tint : autoParams.tint,
      sharpness: current.sharpness != 0.0 ? current.sharpness : autoParams.sharpness,
      // Keep geometry parameters unchanged
      cropX: current.cropX,
      cropY: current.cropY,
      cropWidth: current.cropWidth,
      cropHeight: current.cropHeight,
      rotation: current.rotation,
      flipH: current.flipH,
      flipV: current.flipV,
    );
  }

  // ─── Scene-Aware Parameter Computation ─────────────────────────

  /// Compute auto-adjust parameters based on image analysis results.
  ///
  /// The algorithm adapts its strategy based on scene type:
  /// - **Low-light/Night**: brighten primarily, protect shadow detail
  /// - **Highlight**: darken primarily, recover highlight detail
  /// - **Backlit**: recover both highlights and shadows, HDR-style
  /// - **Hazy**: dehaze processing (contrast + highlights/shadows + whites/blacks combination)
  /// - **Flat**: enhance contrast and saturation
  /// - **High-contrast**: moderately reduce contrast, recover extreme regions
  /// - **Color cast**: neutral reference white balance correction
  EditParams _computeAutoParams(ImageAnalysis stats) {
    // ─── 1. Adaptive Exposure ───
    final exposure = _computeExposure(stats);

    // ─── 2. Adaptive Contrast + Dehaze ───
    final contrast = _computeContrast(stats);

    // ─── 3. Highlight/Shadow Recovery (enhanced for haze scenes) ───
    final highlights = _computeHighlights(stats);
    final shadows = _computeShadows(stats);

    // ─── 4. White/Black Levels ───
    final whites = _computeWhites(stats);
    final blacks = _computeBlacks(stats);

    // ─── 5. Smart White Balance (neutral reference) ───
    final (temperature, tint) = _computeWhiteBalance(stats);

    // ─── 6. Vibrance (content-aware) ───
    final vibrance = _computeVibrance(stats);

    // ─── 7. Saturation ───
    final saturation = _computeSaturation(stats);

    // ─── 8. Sharpness ───
    final sharpness = _computeSharpness(stats);

    return EditParams(
      exposure: _round2(exposure),
      contrast: contrast.roundToDouble(),
      highlights: highlights.roundToDouble(),
      shadows: shadows.roundToDouble(),
      whites: whites.roundToDouble(),
      blacks: blacks.roundToDouble(),
      saturation: saturation.roundToDouble(),
      vibrance: vibrance.roundToDouble(),
      temperature: temperature.roundToDouble(),
      tint: tint.roundToDouble(),
      sharpness: sharpness.roundToDouble(),
    );
  }

  /// Compute adaptive exposure (enhanced — spatial awareness).
  ///
  /// Improvements:
  /// - Night scene: more restrained brightening (preserve night atmosphere), target luminance 0.22
  /// - Highlight-first strategy: protect highlights when clipping is detected
  /// - Uses median p50 as auxiliary (mean is susceptible to extreme values)
  /// - Stronger highlight protection: no brightening when clipping > 5%
  /// - Spatial awareness: backlit scenes consider bottom (foreground) brightness
  /// - High local contrast images get moderate brightening for clarity
  double _computeExposure(ImageAnalysis stats) {
    final targetLum = switch (stats.scene) {
      SceneType.lowLight => 0.38,
      SceneType.nightScene => 0.22, // Keep night scene atmosphere
      SceneType.highLight => 0.58,
      SceneType.backlit => 0.45,
      SceneType.hazy => 0.5,
      _ => 0.5,
    };

    // Spatial awareness: backlit scenes use bottom 1/3 (foreground) brightness
    double effectiveLum;
    if (stats.scene == SceneType.backlit && stats.gridStats.length >= 9) {
      // Bottom row (indices 6,7,8) = foreground
      double bottomLum = 0;
      for (int i = 6; i < 9; i++) {
        bottomLum += stats.gridStats[i].avgLuminance;
      }
      bottomLum /= 3;
      // Foreground is dark → needs more brightening, also reference global
      effectiveLum = bottomLum * 0.7 + stats.avgLuminance * 0.3;
    } else {
      effectiveLum = stats.avgLuminance * 0.6 + stats.p50 * 0.4;
    }
    final avgLum = effectiveLum.clamp(0.005, 0.995);
    final diff = targetLum - avgLum;

    // Adaptive dead zone: higher local contrast = larger dead zone (clear images need less adjustment)
    final deadZone = 0.04 + stats.localContrastMedian * 0.06;
    if (diff.abs() < deadZone) return 0.0;

    // Damped log2 curve
    double exposure = (math.log(targetLum / avgLum) / math.ln2) * 0.65;

    // Highlight-first protection: no brightening when severe clipping
    if (stats.highlightClipRatio > 0.05 && exposure > 0) {
      return 0.0; // Protect highlights, skip brightening
    }
    if (stats.highlightClipRatio > 0.02 && exposure > 0) {
      exposure *= (1.0 - stats.highlightClipRatio * 8).clamp(0.0, 1.0);
    }

    // Scene limits
    final maxExposure = switch (stats.scene) {
      SceneType.lowLight => 1.2,
      SceneType.nightScene => 0.6, // Don't over-brighten night scenes
      SceneType.highLight => 0.0,
      SceneType.backlit => 0.8,
      SceneType.hazy => 0.7,
      _ => 1.0,
    };
    final minExposure = switch (stats.scene) {
      SceneType.highLight => -1.2,
      SceneType.lowLight => 0.0,
      SceneType.nightScene => 0.0,
      _ => -1.0,
    };

    exposure = exposure.clamp(minExposure, maxExposure);

    // Shadow clipping protection
    if (stats.shadowClipRatio > 0.03 && exposure < 0) {
      exposure *= (1.0 - stats.shadowClipRatio.clamp(0.0, 0.4));
    }

    return exposure;
  }

  /// Compute adaptive contrast (enhanced — dehaze support).
  ///
  /// Improvements:
  /// - Haze scenes: significantly boost contrast (simulates dehazing)
  /// - Night scenes: gentle contrast boost (separate lights from shadows)
  /// - Uses midtone contrast as auxiliary metric
  double _computeContrast(ImageAnalysis stats) {
    final stdLum = stats.stdLuminance;

    // Dead zone: no adjustment when std dev is reasonable (haze and night scenes excepted)
    final inDeadZone = stdLum > 0.15 && stdLum < 0.28;
    if (inDeadZone && stats.scene != SceneType.hazy && stats.scene != SceneType.nightScene) {
      return 0.0;
    }

    // Based on standard deviation deviation
    double contrast = (0.20 - stdLum) * 70;

    // Percentile correction
    final p5Dev = 0.05 - stats.p5;
    final p95Dev = stats.p95 - 0.95;
    if (p5Dev > 0 && p95Dev < 0) {
      contrast += (p5Dev + p95Dev.abs()) * 60;
    } else if (p5Dev > 0.02) {
      contrast += p5Dev * 50;
    } else if (p95Dev < -0.02) {
      contrast += p95Dev.abs() * 50;
    }

    // Haze dehazing: significant contrast boost
    if (stats.scene == SceneType.hazy) {
      contrast += stats.hazeScore * 40;
      // Lower midtone contrast = more enhancement needed
      contrast += (0.18 - stats.midtoneContrast).clamp(0.0, 0.12) * 200;
    }

    // Scene adjustment
    contrast *= switch (stats.scene) {
      SceneType.flat => 1.3,
      SceneType.hazy => 1.4,
      SceneType.highContrast => -0.3,
      SceneType.lowLight => 0.6,
      SceneType.nightScene => 0.8,
      SceneType.highLight => 0.6,
      SceneType.backlit => 0.5,
      _ => 1.0,
    };

    // Extra boost when dynamic range is very small
    if (stats.dynamicRange < 0.4) {
      contrast += (0.4 - stats.dynamicRange) * 40;
    }

    // Clamp: haze scenes allow wider range
    final maxContrast = stats.scene == SceneType.hazy ? 45.0 : 35.0;
    return contrast.clamp(-25.0, maxContrast);
  }

  /// Compute highlight recovery (enhanced — dehaze support).
  double _computeHighlights(ImageAnalysis stats) {
    double highlights = 0.0;

    // Highlight clipping recovery
    if (stats.highlightClipRatio > 0.02) {
      highlights = -(stats.highlightClipRatio * 300).clamp(0.0, 50.0);
    }

    final p95Threshold = stats.scene == SceneType.highLight ? 0.88 : 0.93;
    if (stats.p95 > p95Threshold) {
      highlights -= (stats.p95 - p95Threshold) * 200;
    }

    if (stats.p99 > 0.97) {
      highlights -= (stats.p99 - 0.97) * 150;
    }

    // Haze scenes: reduce highlights for clarity
    if (stats.scene == SceneType.hazy && stats.p95 > 0.75) {
      highlights -= stats.hazeScore * 25;
    }

    // Scene adjustment
    highlights *= switch (stats.scene) {
      SceneType.highLight => 1.2,
      SceneType.backlit => 1.1,
      SceneType.hazy => 1.3,
      SceneType.lowLight => 0.2,
      SceneType.nightScene => 0.3,
      _ => 1.0,
    };

    return highlights.clamp(-60.0, 0.0);
  }

  /// Compute shadow brightening (enhanced — dehaze support).

  double _computeShadows(ImageAnalysis stats) {
    double shadows = 0.0;

    // Shadow clipping brightening
    if (stats.shadowClipRatio > 0.02) {
      shadows = (stats.shadowClipRatio * 250).clamp(0.0, 40.0);
    }

    if (stats.p5 < 0.05) {
      shadows += (0.05 - stats.p5) * 200;
    }

    if (stats.p1 < 0.02) {
      shadows += (0.02 - stats.p1) * 120;
    }

    // Haze scenes: brighten shadows for depth
    if (stats.scene == SceneType.hazy && stats.p5 < 0.15) {
      shadows += stats.hazeScore * 15;
    }

    // Scene adjustment
    shadows *= switch (stats.scene) {
      SceneType.lowLight => 1.2,
      SceneType.nightScene => 1.1,
      SceneType.backlit => 1.1,
      SceneType.hazy => 1.2,
      SceneType.highLight => 0.2,
      SceneType.highContrast => 0.8,
      _ => 1.0,
    };

    return shadows.clamp(0.0, 50.0);
  }

  /// Compute white level (enhanced).
  double _computeWhites(ImageAnalysis stats) {
    double whites = 0.0;

    // Dead zone
    if (stats.p95 > 0.80 && stats.p95 < 0.92 && stats.highlightClipRatio < 0.01) {
      return 0.0;
    }

    if (stats.p95 < 0.80 && stats.highlightClipRatio < 0.01) {
      whites = (0.90 - stats.p95) * 80;
    }

    if (stats.highlightClipRatio > 0.02) {
      whites -= stats.highlightClipRatio * 150;
    }

    // Haze scenes: slightly increase whites for clarity
    if (stats.scene == SceneType.hazy && stats.p95 < 0.85) {
      whites += stats.hazeScore * 10;
    }

    return whites.clamp(-25.0, 25.0);
  }

  /// Compute black level (enhanced — dehaze support).
  double _computeBlacks(ImageAnalysis stats) {
    double blacks = 0.0;

    // Dead zone
    if (stats.p5 > 0.03 && stats.p5 < 0.10 && stats.shadowClipRatio < 0.01) {
      return 0.0;
    }

    if (stats.p5 > 0.10 && stats.shadowClipRatio < 0.01) {
      blacks = -(stats.p5 - 0.07) * 80;
    }

    if (stats.shadowClipRatio > 0.02) {
      blacks += stats.shadowClipRatio * 100;
    }

    // Haze scenes: reduce blacks for contrast
    if (stats.scene == SceneType.hazy && stats.p5 > 0.05) {
      blacks -= stats.hazeScore * 15;
    }

    return blacks.clamp(-25.0, 25.0);
  }

  /// Compute smart white balance (enhanced — Shades of Gray + content awareness).
  ///
  /// Improvements:
  /// - Uses Shades of Gray (p=6) color constancy algorithm to estimate illuminant color
  /// - Combines Gray Edge and traditional gray-world with weighted fusion
  /// - Scenes with many neutral pixels → three methods should agree → high confidence
  /// - Scenes with few neutral pixels (sunset, blue sky) → significantly reduce correction
  /// - Night scenes: white balance unreliable, significantly reduce correction
  /// - Skin tone protection: reduce temperature adjustment for skin-rich scenes
  (double, double) _computeWhiteBalance(ImageAnalysis stats) {
    // ─── Method 1: Shades of Gray ───
    final sog = stats.illuminantEstimate;
    final sogR = sog[0], sogB = sog[2];
    // Derive correction gain from illuminant estimate
    // illuminant is the estimated "light source color", correction gain is 1/illuminant
    final sogGainR = (1.0 / sogR).clamp(0.7, 1.4);
    final sogGainB = (1.0 / sogB).clamp(0.7, 1.4);
    final sogTemp = (sogGainR - sogGainB) * 30.0;
    final sogTint = ((sogGainR + sogGainB) / 2.0 - 1.0) * -25.0;

    // ─── Method 2: Gray Edge ───
    final ge = stats.illuminantEdge;
    final geGainR = (1.0 / ge[0]).clamp(0.7, 1.4);
    final geGainB = (1.0 / ge[2]).clamp(0.7, 1.4);
    final geTemp = (geGainR - geGainB) * 30.0;
    final geTint = ((geGainR + geGainB) / 2.0 - 1.0) * -25.0;

    // ─── Method 3: Gray World ───
    final gray = (stats.avgR + stats.avgG + stats.avgB) / 3.0;
    double gwTemp = 0, gwTint = 0;
    if (gray > 0.01) {
      final rOffset = gray - stats.avgR;
      final bOffset = gray - stats.avgB;
      final gOffset = gray - stats.avgG;
      gwTemp = (rOffset - bOffset) * 35;
      gwTint = -gOffset * 30;
    }

    // ─── Confidence Assessment ───
    // More neutral pixels → all methods are more reliable
    double wbConfidence = (stats.neutralPixelRatio / 0.15).clamp(0.0, 1.0);

    // Consistency check: if SoG and Gray World agree on direction → boost confidence
    final sogGwAgree = (sogTemp > 0) == (gwTemp > 0) || sogTemp.abs() < 3 || gwTemp.abs() < 3;
    if (sogGwAgree && wbConfidence > 0.3) {
      wbConfidence = (wbConfidence + 0.15).clamp(0.0, 1.0);
    }

    // Content-aware down-weighting
    if (stats.blueSkyRatio > 0.05 || stats.greenFoliageRatio > 0.1) {
      wbConfidence *= 0.4;
    }
    if (stats.skinToneRatio > 0.05) {
      wbConfidence *= 0.6;
    }

    // ─── Weighted Fusion: SoG (40%) + Gray Edge (20%) + Gray World (40%) ───
    double temperature = sogTemp * 0.4 + geTemp * 0.2 + gwTemp * 0.4;
    double tint = sogTint * 0.4 + geTint * 0.2 + gwTint * 0.4;

    temperature *= wbConfidence;
    tint *= wbConfidence;

    // Scene protection
    switch (stats.scene) {
      case SceneType.warmTint:
        temperature *= 0.3;
      case SceneType.coolTint:
        temperature *= 0.3;
      case SceneType.nightScene:
        // Night scene WB is very unreliable (varying artificial light color temps)
        temperature *= 0.2;
        tint *= 0.2;
      case SceneType.lowLight:
        temperature *= 0.4;
        tint *= 0.4;
      case SceneType.hazy:
        // Haze scene WB is somewhat reliable
        temperature *= 0.7;
        tint *= 0.7;
      default:
        break;
    }

    // Dead zone
    if (temperature.abs() < 3) temperature = 0.0;
    if (tint.abs() < 2) tint = 0.0;

    return (temperature.clamp(-25.0, 25.0), tint.clamp(-15.0, 15.0));
  }

  /// Compute vibrance (enhanced — content-aware).
  ///
  /// Improvements:
  /// - Blue sky scenes: moderately boost blue sky saturation
  /// - Foliage scenes: moderately boost green saturation
  /// - Skin tone protection: reduce vibrance for skin-rich scenes
  double _computeVibrance(ImageAnalysis stats) {
    double vibrance = 0.0;

    // Only boost when saturation is low
    if (stats.avgSaturation < 0.20) {
      vibrance = (0.20 - stats.avgSaturation) * 80;
    }

    // Content-aware adjustment
    if (stats.blueSkyRatio > 0.05) {
      vibrance += 5; // Blue sky prefers slightly higher saturation
    }
    if (stats.greenFoliageRatio > 0.1) {
      vibrance += 3; // Foliage prefers slightly higher saturation
    }
    if (stats.skinToneRatio > 0.05) {
      vibrance *= 0.5; // Skin tone protection
    }

    // Scene adjustment
    vibrance *= switch (stats.scene) {
      SceneType.flat => 1.2,
      SceneType.hazy => 1.3, // Boost saturation after dehazing
      SceneType.lowLight => 0.5,
      SceneType.nightScene => 0.7,
      SceneType.highLight => 0.8,
      _ => 1.0,
    };

    return vibrance.clamp(0.0, 25.0);
  }

  /// Compute saturation.
  double _computeSaturation(ImageAnalysis stats) {
    // Slight boost for extremely low saturation (near black & white)
    if (stats.avgSaturation < 0.03) {
      return 5.0;
    }
    return 0.0;
  }

  /// Compute sharpness (enhanced — global + local dual metrics).
  ///
  /// Based on perceivedSharpness (global gradient) and localContrastMedian (local RMS contrast):
  /// - Both low (< 0.3) → severe blur → sharpen 20-30
  /// - One low, one normal → moderate sharpen 10-15
  /// - Both normal (> 0.5) → no sharpen
  double _computeSharpness(ImageAnalysis stats) {
    final globalSharp = stats.perceivedSharpness;
    final localSharp = (stats.localContrastMedian / 0.15).clamp(0.0, 1.0);

    // Combined sharpness: global weight 0.4, local weight 0.6 (local contrast is more reliable)
    final combinedSharp = globalSharp * 0.4 + localSharp * 0.6;

    if (combinedSharp >= 0.55) return 0.0;

    // Map blur amount to sharpening amount
    final blurAmount = (0.55 - combinedSharp).clamp(0.0, 0.4);
    double sharpness = blurAmount * 75; // 0.4 * 75 = 30 max

    // Scene adjustment: no sharpening for night scenes (noisy)
    sharpness *= switch (stats.scene) {
      SceneType.nightScene => 0.2,
      SceneType.lowLight => 0.5,
      SceneType.hazy => 0.8,
      _ => 1.0,
    };

    return sharpness.clamp(0.0, 30.0);
  }

  /// Round to two decimal places.
  double _round2(double value) {
    return double.parse(value.toStringAsFixed(2));
  }
}