import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:spectra/data/database/daos/photo_dao.dart';
import 'package:spectra/data/services/image_decoder_service.dart';
import 'package:spectra/data/services/thumbnail_service.dart';

class _MockPhotoDao extends Mock implements PhotoDao {}

class _MockImageDecoderService extends Mock implements ImageDecoderService {}

void main() {
  late _MockPhotoDao mockPhotoDao;
  late _MockImageDecoderService mockDecoder;
  late ThumbnailService thumbnailService;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Mock path_provider channel to return a temp directory
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'getApplicationSupportDirectory') {
          return Directory.systemTemp.path;
        }
        return null;
      },
    );
  });

  setUp(() {
    mockPhotoDao = _MockPhotoDao();
    mockDecoder = _MockImageDecoderService();
    thumbnailService = ThumbnailService(
      photoDao: mockPhotoDao,
      imageDecoder: mockDecoder,
    );
  });

  group('ThumbnailService', () {
    group('getThumbnailPath', () {
      test('返回 PNG 路径', () async {
        final path = await thumbnailService.getThumbnailPath(1, 128);

        expect(path, endsWith('1_128.png'));
        expect(path, contains('thumbnails'));
      });

      test('不同尺寸返回不同路径', () async {
        final path128 = await thumbnailService.getThumbnailPath(1, 128);
        final path512 = await thumbnailService.getThumbnailPath(1, 512);

        expect(path128, isNot(equals(path512)));
        expect(path128, contains('1_128'));
        expect(path512, contains('1_512'));
      });

      test('不同 photoId 返回不同路径', () async {
        final path1 = await thumbnailService.getThumbnailPath(1, 128);
        final path2 = await thumbnailService.getThumbnailPath(2, 128);

        expect(path1, isNot(equals(path2)));
        expect(path1, contains('1_128'));
        expect(path2, contains('2_128'));
      });
    });

    group('getThumbnailPath caching', () {
      test('同一 photoId+size 返回缓存路径', () async {
        final path1 = await thumbnailService.getThumbnailPath(1, 128);
        final path2 = await thumbnailService.getThumbnailPath(1, 128);

        expect(path1, equals(path2));
      });
    });
  });
}
