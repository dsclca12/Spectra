import 'package:flutter_test/flutter_test.dart';

import 'package:spectra/core/constants.dart';
import 'package:spectra/core/enums.dart';

void main() {
  group('AppConstants', () {
    test('supportedImageExtensions 包含常见格式', () {
      expect(AppConstants.supportedImageExtensions.contains('jpg'), isTrue);
      expect(AppConstants.supportedImageExtensions.contains('jpeg'), isTrue);
      expect(AppConstants.supportedImageExtensions.contains('png'), isTrue);
      expect(AppConstants.supportedImageExtensions.contains('webp'), isTrue);
      expect(AppConstants.supportedImageExtensions.contains('bmp'), isTrue);
      expect(AppConstants.supportedImageExtensions.contains('gif'), isTrue);
      expect(AppConstants.supportedImageExtensions.contains('raw'), isTrue);
    });

    test('supportedImageExtensions 包含 RAW 格式', () {
      // Canon
      expect(AppConstants.supportedImageExtensions.contains('cr2'), isTrue);
      expect(AppConstants.supportedImageExtensions.contains('cr3'), isTrue);
      expect(AppConstants.supportedImageExtensions.contains('crw'), isTrue);
      // Nikon
      expect(AppConstants.supportedImageExtensions.contains('nef'), isTrue);
      expect(AppConstants.supportedImageExtensions.contains('nrw'), isTrue);
      // Sony
      expect(AppConstants.supportedImageExtensions.contains('arw'), isTrue);
      expect(AppConstants.supportedImageExtensions.contains('sr2'), isTrue);
      // Adobe
      expect(AppConstants.supportedImageExtensions.contains('dng'), isTrue);
      // Fujifilm
      expect(AppConstants.supportedImageExtensions.contains('raf'), isTrue);
      // Panasonic
      expect(AppConstants.supportedImageExtensions.contains('rw2'), isTrue);
      // Olympus
      expect(AppConstants.supportedImageExtensions.contains('orf'), isTrue);
      // Pentax
      expect(AppConstants.supportedImageExtensions.contains('pef'), isTrue);
    });

    test('supportedImageExtensions 包含 HEIC/HEIF/AVIF', () {
      expect(AppConstants.supportedImageExtensions.contains('heic'), isTrue);
      expect(AppConstants.supportedImageExtensions.contains('heif'), isTrue);
      expect(AppConstants.supportedImageExtensions.contains('avif'), isTrue);
    });

    test('supportedImageExtensions 包含 TIFF', () {
      expect(AppConstants.supportedImageExtensions.contains('tif'), isTrue);
      expect(AppConstants.supportedImageExtensions.contains('tiff'), isTrue);
    });

    test('缩略图尺寸常量正确', () {
      expect(AppConstants.thumbnailSmall, 128);
      expect(AppConstants.thumbnailMedium, 512);
    });
  });

  group('Rating', () {
    test('isValid 验证', () {
      expect(Rating.isValid(0), isTrue);
      expect(Rating.isValid(5), isTrue);
      expect(Rating.isValid(6), isFalse);
      expect(Rating.isValid(-1), isFalse);
    });
  });

  group('PickLabel', () {
    test('isValid 验证', () {
      expect(PickLabel.isValid(0), isTrue);
      expect(PickLabel.isValid(1), isTrue);
      expect(PickLabel.isValid(2), isTrue);
      expect(PickLabel.isValid(3), isFalse);
    });
  });

  group('ColorLabel', () {
    test('isValid 验证', () {
      expect(ColorLabel.isValid(0), isTrue);
      expect(ColorLabel.isValid(6), isTrue);
      expect(ColorLabel.isValid(7), isFalse);
    });
  });
}