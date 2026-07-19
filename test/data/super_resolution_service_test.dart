import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:spectra/data/services/ml_service.dart';
import 'package:spectra/data/services/super_resolution_service.dart';

void main() {
  group('SuperResolutionService', () {
    late MlService mlService;
    late SuperResolutionService srService;

    setUp(() {
      mlService = MlService();
      srService = SuperResolutionService(mlService);
    });

    tearDown(() {
      mlService.dispose();
    });

    test('modelStatus 初始为 notLoaded', () {
      expect(srService.modelStatus, MlModelStatus.notLoaded);
    });

    test('upscaleImage 回退到 Lanczos 放大', () async {
      // Create 32×32 test image
      final testImage = img.Image(width: 32, height: 32);
      for (final pixel in testImage) {
        pixel..r = 100..g = 150..b = 200;
      }

      // Falls back to Lanczos when no ONNX model is available
      final result = await srService.upscaleImage(testImage);

      expect(result, isNotNull);
      // 3x upscale → 96×96
      expect(result!.width, 96);
      expect(result.height, 96);
    });

    test('upscale 写入输出文件', () async {
      final testImage = img.Image(width: 32, height: 32);
      for (final pixel in testImage) {
        pixel..r = 100..g = 150..b = 200;
      }

      final tempDir = Directory.systemTemp;
      final inputFile = File('${tempDir.path}/sr_input.png');
      final outputFile = File('${tempDir.path}/sr_output.jpg');
      await inputFile.writeAsBytes(img.encodePng(testImage));

      final result = await srService.upscale(
        inputFile.path,
        outputPath: outputFile.path,
      );

      expect(result, isNotNull);
      expect(await outputFile.exists(), true);
      expect(outputFile.lengthSync(), greaterThan(0));

      await inputFile.delete();
      if (await outputFile.exists()) await outputFile.delete();
    });

    test('upscale 不存在的文件返回 null', () async {
      final result = await srService.upscale(
        '/nonexistent/path.png',
        outputPath: '/tmp/sr_out.jpg',
      );
      expect(result, isNull);
    });
  });
}