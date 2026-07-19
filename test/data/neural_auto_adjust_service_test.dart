import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:spectra/data/models/edit_params.dart';
import 'package:spectra/data/services/auto_adjust_service.dart';
import 'package:spectra/data/services/image_analysis.dart';
import 'package:spectra/data/services/image_decoder_service.dart';
import 'package:spectra/data/services/ml_service.dart';
import 'package:spectra/data/services/neural_auto_adjust_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ImageDecoderService decoder;
  late ImageAnalysisService analysisService;
  late MlService mlService;
  late NeuralAutoAdjustService neuralService;
  late AutoAdjustService autoAdjustService;

  setUp(() {
    decoder = ImageDecoderService();
    analysisService = ImageAnalysisService(decoder);
    mlService = MlService();
    neuralService = NeuralAutoAdjustService(mlService, analysisService);
    autoAdjustService = AutoAdjustService(
      neuralService: neuralService,
      analysisService: analysisService,
    );
  });

  tearDown(() {
    mlService.dispose();
  });

  group('ImageAnalysisService', () {
    test('analyze 对纯黑图片检测低光场景', () async {
      final blackImage = img.Image(width: 64, height: 64);
      for (final pixel in blackImage) {
        pixel..r = 0..g = 0..b = 0..a = 255;
      }

      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_black_analysis.png');
      await testFile.writeAsBytes(img.encodePng(blackImage));

      final result = await analysisService.analyze(testFile.path);

      expect(result, isNotNull);
      expect(result!.avgLuminance, lessThan(0.05));
      expect(result.scene, SceneType.lowLight);
      expect(result.shadowClipRatio, greaterThan(0.5));

      await testFile.delete();
    });

    test('analyze 对纯白图片检测高光场景', () async {
      final whiteImage = img.Image(width: 64, height: 64);
      for (final pixel in whiteImage) {
        pixel..r = 255..g = 255..b = 255..a = 255;
      }

      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_white_analysis.png');
      await testFile.writeAsBytes(img.encodePng(whiteImage));

      final result = await analysisService.analyze(testFile.path);

      expect(result, isNotNull);
      expect(result!.avgLuminance, greaterThan(0.9));
      expect(result.highlightClipRatio, greaterThan(0.5));

      await testFile.delete();
    });

    test('analyze 对中灰图片返回正常场景', () async {
      final grayImage = img.Image(width: 64, height: 64);
      for (final pixel in grayImage) {
        pixel..r = 128..g = 128..b = 128..a = 255;
      }

      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_gray_analysis.png');
      await testFile.writeAsBytes(img.encodePng(grayImage));

      final result = await analysisService.analyze(testFile.path);

      expect(result, isNotNull);
      expect(result!.avgLuminance, closeTo(0.5, 0.05));

      await testFile.delete();
    });

    test('analyze 不存在的文件返回 null', () async {
      final result = await analysisService.analyze('/nonexistent/path.png');
      expect(result, isNull);
    });
  });

  group('NeuralAutoAdjustService', () {
    test('modelStatus 初始为 notLoaded', () {
      expect(neuralService.modelStatus, MlModelStatus.notLoaded);
    });

    test('analyze 对纯黑图片返回合理参数', () async {
      final blackImage = img.Image(width: 64, height: 64);
      for (final pixel in blackImage) {
        pixel..r = 0..g = 0..b = 0..a = 255;
      }

      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_black.png');
      await testFile.writeAsBytes(img.encodePng(blackImage));

      final result = await neuralService.analyze(testFile.path);

      // Pure black image should need brightening → exposure > 0
      expect(result.exposure, greaterThan(0.0));

      await testFile.delete();
    });

    test('analyze 对纯白图片返回合理参数', () async {
      final whiteImage = img.Image(width: 64, height: 64);
      for (final pixel in whiteImage) {
        pixel..r = 255..g = 255..b = 255..a = 255;
      }

      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_white.png');
      await testFile.writeAsBytes(img.encodePng(whiteImage));

      final result = await neuralService.analyze(testFile.path);

      // Pure white image should need darkening → exposure < 0
      expect(result.exposure, lessThan(0.0));

      await testFile.delete();
    });

    test('analyze 对中灰图片返回接近零的曝光', () async {
      final grayImage = img.Image(width: 64, height: 64);
      for (final pixel in grayImage) {
        pixel..r = 128..g = 128..b = 128..a = 255;
      }

      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_gray.png');
      await testFile.writeAsBytes(img.encodePng(grayImage));

      final result = await neuralService.analyze(testFile.path);

      // Mid-gray image exposure adjustment should be small
      expect(result.exposure.abs(), lessThan(0.5));

      await testFile.delete();
    });

    test('analyze 保留几何参数', () async {
      final grayImage = img.Image(width: 64, height: 64);
      for (final pixel in grayImage) {
        pixel..r = 128..g = 128..b = 128..a = 255;
      }

      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_gray2.png');
      await testFile.writeAsBytes(img.encodePng(grayImage));

      final current = const EditParams(
        cropX: 0.1,
        cropY: 0.2,
        cropWidth: 0.8,
        cropHeight: 0.9,
        rotation: 90,
        flipH: true,
      );

      final result = await neuralService.analyze(
        testFile.path,
        currentParams: current,
      );

      expect(result.cropX, 0.1);
      expect(result.cropY, 0.2);
      expect(result.cropWidth, 0.8);
      expect(result.cropHeight, 0.9);
      expect(result.rotation, 90);
      expect(result.flipH, true);

      await testFile.delete();
    });

    test('analyze strength=0 返回零调整', () async {
      final blackImage = img.Image(width: 64, height: 64);
      for (final pixel in blackImage) {
        pixel..r = 0..g = 0..b = 0..a = 255;
      }

      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_black2.png');
      await testFile.writeAsBytes(img.encodePng(blackImage));

      final result = await neuralService.analyze(
        testFile.path,
        strength: 0.0,
      );

      // strength=0 → all adjustment values are 0
      expect(result.exposure, 0.0);
      expect(result.contrast, 0.0);
      expect(result.temperature, 0.0);

      await testFile.delete();
    });

    test('analyze 不存在的文件返回默认参数', () async {
      final result = await neuralService.analyze('/nonexistent/path.png');
      expect(result, EditParams.defaultParams);
    });
  });

  group('AutoAdjustService Facade', () {
    test('analyzeHeuristic 对中灰图片返回接近零的曝光', () async {
      final grayImage = img.Image(width: 64, height: 64);
      for (final pixel in grayImage) {
        pixel..r = 128..g = 128..b = 128..a = 255;
      }

      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_heuristic.png');
      await testFile.writeAsBytes(img.encodePng(grayImage));

      final result = await autoAdjustService.analyzeHeuristic(testFile.path);

      // Mid-gray image exposure should be small
      expect(result.exposure.abs(), lessThan(0.5));

      await testFile.delete();
    });

    test('analyze with engine=heuristic 使用启发式', () async {
      final blackImage = img.Image(width: 64, height: 64);
      for (final pixel in blackImage) {
        pixel..r = 0..g = 0..b = 0..a = 255;
      }

      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_facade.png');
      await testFile.writeAsBytes(img.encodePng(blackImage));

      final result = await autoAdjustService.analyze(
        testFile.path,
        engine: AutoAdjustEngine.heuristic,
      );

      // Heuristic should brighten pure black image
      expect(result.exposure, greaterThan(0.0));

      await testFile.delete();
    });

    test('analyze with engine=neural 无 ONNX 模型时回退模拟路径', () async {
      final blackImage = img.Image(width: 64, height: 64);
      for (final pixel in blackImage) {
        pixel..r = 0..g = 0..b = 0..a = 255;
      }

      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_neural_sim.png');
      await testFile.writeAsBytes(img.encodePng(blackImage));

      final result = await autoAdjustService.analyze(
        testFile.path,
        engine: AutoAdjustEngine.neural,
      );

      // Without ONNX model, uses pure Dart simulation path, should brighten pure black image
      expect(result.exposure, greaterThan(0.0));

      await testFile.delete();
    });

    test('analyze with engine=auto 无 ONNX 时回退启发式', () async {
      final blackImage = img.Image(width: 64, height: 64);
      for (final pixel in blackImage) {
        pixel..r = 0..g = 0..b = 0..a = 255;
      }

      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_auto_fallback.png');
      await testFile.writeAsBytes(img.encodePng(blackImage));

      final result = await autoAdjustService.analyze(
        testFile.path,
        engine: AutoAdjustEngine.auto,
      );

      // Should fall back to heuristic, brightening pure black image
      expect(result.exposure, greaterThan(0.0));

      await testFile.delete();
    });

    test('preserveUserEdits 仅填充未调整参数', () async {
      final blackImage = img.Image(width: 64, height: 64);
      for (final pixel in blackImage) {
        pixel..r = 0..g = 0..b = 0..a = 255;
      }

      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_preserve.png');
      await testFile.writeAsBytes(img.encodePng(blackImage));

      final current = const EditParams(exposure: 1.5);

      final result = await autoAdjustService.analyze(
        testFile.path,
        preserveUserEdits: true,
        currentParams: current,
        engine: AutoAdjustEngine.heuristic,
      );

      // User-adjusted exposure should be preserved
      expect(result.exposure, 1.5);

      await testFile.delete();
    });

    test('低光场景曝光调整幅度受限', () async {
      // Create extremely dark image (luminance ≈ 0.05)
      final darkImage = img.Image(width: 64, height: 64);
      for (final pixel in darkImage) {
        pixel..r = 12..g = 12..b = 12..a = 255;
      }

      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_lowlight.png');
      await testFile.writeAsBytes(img.encodePng(darkImage));

      final result = await autoAdjustService.analyzeHeuristic(testFile.path);

      // Low-light exposure should not exceed 1.5
      expect(result.exposure, lessThanOrEqualTo(1.5));
      // Shadows should be brightened
      expect(result.shadows, greaterThan(0.0));

      await testFile.delete();
    });

    test('高光场景压暗且恢复高光', () async {
      // Create extremely bright image (luminance ≈ 0.9)
      final brightImage = img.Image(width: 64, height: 64);
      for (final pixel in brightImage) {
        pixel..r = 230..g = 230..b = 230..a = 255;
      }

      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_highlight.png');
      await testFile.writeAsBytes(img.encodePng(brightImage));

      final result = await autoAdjustService.analyzeHeuristic(testFile.path);

      // Highlight scene should be darkened
      expect(result.exposure, lessThan(0.0));
      // Highlights should be recovered
      expect(result.highlights, lessThan(0.0));

      await testFile.delete();
    });

    test('偏暖场景白平衡校正幅度受限', () async {
      // Create warm-toned image (R > B)
      final warmImage = img.Image(width: 64, height: 64);
      for (final pixel in warmImage) {
        pixel..r = 200..g = 150..b = 80..a = 255;
      }

      final tempDir = Directory.systemTemp;
      final testFile = File('${tempDir.path}/test_warm.png');
      await testFile.writeAsBytes(img.encodePng(warmImage));

      final result = await autoAdjustService.analyzeHeuristic(testFile.path);

      // Warm scene correction is limited, temperature should not be excessive
      expect(result.temperature.abs(), lessThanOrEqualTo(50.0));

      await testFile.delete();
    });
  });
}