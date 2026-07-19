import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:exif/exif.dart';
import 'package:spectra/data/database/app_database.dart';
import 'package:spectra/data/services/metadata_service.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;

/// Tests the full chain of EXIF reading and database writing.
void main() {
  late AppDatabase db;
  late MetadataService metadataService;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // Run migration to create tables
    await db.photoDao.insertPhoto(PhotosCompanion(
      path: const Value('/test/placeholder.jpg'),
      fileName: const Value('placeholder.jpg'),
      fileHash: const Value(''),
      fileSize: const Value(0),
      modifiedAt: Value(DateTime.now()),
      importedAt: Value(DateTime.now()),
    ));
    await db.photoDao.deletePhoto(1);
    
    metadataService = MetadataService();
  });

  tearDown(() async => await db.close());

  /// Resolve the exif package test data directory across different machines.
  String? _findExifTestDir() {
    final home = Platform.environment['USERPROFILE'] ?? '';
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
    final candidates = [
      // Standard Windows Pub cache location
      if (localAppData.isNotEmpty)
        '$localAppData\\Pub\\Cache\\hosted\\pub.dev\\exif-3.3.0\\test\\data',
      // Alternative: .pub-cache in user profile
      if (home.isNotEmpty)
        '$home\.pub-cache\\hosted\\pub.dev\\exif-3.3.0\\test\\data',
      // Chocolatey / manual install location
      if (home.isNotEmpty)
        '$home\\AppData\\Local\\Pub\\Cache\\hosted\\pub.dev\\exif-3.3.0\\test\\data',
    ];
    for (final path in candidates) {
      if (Directory(path).existsSync()) return path;
    }
    return null;
  }

  test('readExifFromBytes reads exif package test files', () async {
    final cacheDirPath = _findExifTestDir();
    if (cacheDirPath == null) {
      print('exif test data not found in any known Pub cache location');
      print('To run this test, ensure exif-3.3.0 is fetched via "flutter pub get"');
      return;
    }
    final cacheDir = Directory(cacheDirPath);

    final testFiles = await cacheDir
        .list()
        .where((e) => e is File && (e.path.endsWith('.png') || e.path.endsWith('.heic')))
        .cast<File>()
        .toList();

    if (testFiles.isEmpty) {
      print('No test files found');
      return;
    }

    for (final file in testFiles) {
      print('\n=== Testing: ${file.path} ===');
      final bytes = await file.readAsBytes();

      Map<String, IfdTag>? exifData;
      try {
        exifData = await readExifFromBytes(bytes);
      } catch (e) {
        print('  ❌ readExifFromBytes threw: $e');
        continue;
      }

      print('EXIF entries: ${exifData.length}');
      if (exifData.isEmpty) {
        print('  ⚠ No EXIF data');
        continue;
      }

      for (final key in ['Image Make', 'Image Model', 'EXIF LensModel',
                          'EXIF FNumber', 'EXIF FocalLength', 'EXIF ISOSpeedRatings',
                          'EXIF ExposureTime', 'EXIF DateTimeOriginal']) {
        final tag = exifData[key];
        if (tag != null) {
          print('  $key => "${tag.printable}" (${tag.values.runtimeType})');
        }
      }
    }
  });

  test('MetadataService.readExif full pipeline', () async {
    final cacheDirPath = _findExifTestDir();
    if (cacheDirPath == null) {
      print('exif test data not found — skipping metadata pipeline test');
      return;
    }
    final cacheDir = Directory(cacheDirPath);

    final pngFile = File('${cacheDir.path}\\png-test.png');
    if (!await pngFile.exists()) {
      print('PNG test file not found');
      return;
    }

    final tempDir = Directory.systemTemp.createTempSync('spectra_exif_test_');
    final tempFile = File('${tempDir.path}\\test_exif.png');
    await pngFile.copy(tempFile.path);

    try {
      final result = await metadataService.readExif(tempFile.path);
      
      expect(result, isNotNull, reason: 'readExif should return a companion');
      
      print('Companion fields:');
      print('  width: ${result!.width}');
      print('  height: ${result.height}');
      print('  mimeType: ${result.mimeType}');
      print('  cameraMake: ${result.cameraMake}');
      print('  cameraModel: ${result.cameraModel}');
      print('  dateTaken: ${result.dateTaken}');
      print('  latitude: ${result.latitude}');
      print('  longitude: ${result.longitude}');

      // PNG test file has EXIF metadata including GPS
      final hasAnyExif = result.cameraMake.present ||
          result.cameraModel.present ||
          result.lensModel.present ||
          result.focalLength.present ||
          result.aperture.present ||
          result.iso.present ||
          result.dateTaken.present ||
          result.latitude.present ||
          result.longitude.present;

      print('\nHas EXIF: $hasAnyExif');
      
      // The test PNG should have GPS and description at minimum
      if (!hasAnyExif) {
        print('⚠ No EXIF fields extracted! Testing raw EXIF read...');
        final bytes = await tempFile.readAsBytes();
        final rawExif = await readExifFromBytes(bytes);
        print('Raw EXIF entries: ${rawExif.length}');
        for (final e in rawExif.entries) {
          print('  ${e.key}: ${e.value}');
        }
      }
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('数据库 updateExifByPath 能正确更新 EXIF 字段', () async {
    // Insert a photo record first
    final id = await db.photoDao.insertPhoto(PhotosCompanion(
      path: const Value('/test/exif_test.jpg'),
      fileName: const Value('exif_test.jpg'),
      fileHash: const Value(''),
      fileSize: const Value(1024),
      modifiedAt: Value(DateTime.now()),
      importedAt: Value(DateTime.now()),
    ));

    // Verify initial state: EXIF fields are null
    var photo = await db.photoDao.getById(id);
    expect(photo!.cameraMake, isNull);
    expect(photo.cameraModel, isNull);
    expect(photo.dateTaken, isNull);

    // Update EXIF data
    await db.photoDao.updateExifByPath('/test/exif_test.jpg', PhotosCompanion(
      cameraMake: const Value('TestCamera'),
      cameraModel: const Value('TestModel'),
      dateTaken: Value(DateTime(2024, 1, 15, 10, 30, 0)),
      focalLength: const Value(50.0),
      aperture: const Value(2.8),
      iso: const Value(400),
      shutterSpeed: const Value('1/125'),
    ));

    // Verify updated: EXIF fields have values
    photo = await db.photoDao.getById(id);
    expect(photo!.cameraMake, 'TestCamera');
    expect(photo.cameraModel, 'TestModel');
    expect(photo.dateTaken, DateTime(2024, 1, 15, 10, 30, 0));
    expect(photo.focalLength, 50.0);
    expect(photo.aperture, 2.8);
    expect(photo.iso, 400.0);
    expect(photo.shutterSpeed, '1/125');
  });
}
