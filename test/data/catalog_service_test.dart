import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:spectra/data/database/app_database.dart';
import 'package:spectra/data/database/daos/photo_dao.dart';
import 'package:spectra/data/models/photo_filter.dart';
import 'package:spectra/data/services/catalog_service.dart';

class _MockPhotoDao extends Mock implements PhotoDao {}

void main() {
  late _MockPhotoDao mockPhotoDao;
  late CatalogService catalogService;

  setUp(() {
    mockPhotoDao = _MockPhotoDao();
    catalogService = CatalogService(photoDao: mockPhotoDao);
  });

  group('CatalogService', () {
    final testPhotos = [
      Photo(
        id: 1,
        path: '/test/photo1.jpg',
        fileName: 'photo1.jpg',
        fileHash: 'hash1',
        fileSize: 1024,
        modifiedAt: DateTime(2026, 1, 1),
        importedAt: DateTime(2026, 1, 1),
        rating: 0,
        pickLabel: 0,
        colorLabel: 0,
        thumbnailStatus: 0,
        syncStatus: 0,
      ),
      Photo(
        id: 2,
        path: '/test/photo2.jpg',
        fileName: 'photo2.jpg',
        fileHash: 'hash2',
        fileSize: 2048,
        modifiedAt: DateTime(2026, 1, 2),
        importedAt: DateTime(2026, 1, 2),
        rating: 3,
        pickLabel: 1,
        colorLabel: 2,
        thumbnailStatus: 2,
        syncStatus: 0,
      ),
    ];

    group('queryPhotos', () {
      test('无筛选条件时返回所有照片', () async {
        when(() => mockPhotoDao.queryFiltered(
              folderId: any(named: 'folderId'),
              minRating: any(named: 'minRating'),
              pickLabel: any(named: 'pickLabel'),
              colorLabels: any(named: 'colorLabels'),
              dateFrom: any(named: 'dateFrom'),
              dateTo: any(named: 'dateTo'),
              cameraModel: any(named: 'cameraModel'),
              searchQuery: any(named: 'searchQuery'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              sortBy: any(named: 'sortBy'),
              ascending: any(named: 'ascending'),
            )).thenAnswer((_) async => testPhotos);

        final result = await catalogService.queryPhotos(
          filter: PhotoFilter.empty,
        );

        expect(result, hasLength(2));
        expect(result[0].id, 1);
        expect(result[1].id, 2);
      });

      test('按文件夹筛选', () async {
        when(() => mockPhotoDao.queryFiltered(
              folderId: 5,
              minRating: any(named: 'minRating'),
              pickLabel: any(named: 'pickLabel'),
              colorLabels: any(named: 'colorLabels'),
              dateFrom: any(named: 'dateFrom'),
              dateTo: any(named: 'dateTo'),
              cameraModel: any(named: 'cameraModel'),
              searchQuery: any(named: 'searchQuery'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              sortBy: any(named: 'sortBy'),
              ascending: any(named: 'ascending'),
            )).thenAnswer((_) async => [testPhotos.first]);

        final result = await catalogService.queryPhotos(
          folderId: 5,
          filter: PhotoFilter.empty,
        );

        expect(result, hasLength(1));
        expect(result[0].id, 1);
      });

      test('按评分筛选', () async {
        const filter = PhotoFilter(minRating: 3);

        when(() => mockPhotoDao.queryFiltered(
              folderId: any(named: 'folderId'),
              minRating: 3,
              pickLabel: any(named: 'pickLabel'),
              colorLabels: any(named: 'colorLabels'),
              dateFrom: any(named: 'dateFrom'),
              dateTo: any(named: 'dateTo'),
              cameraModel: any(named: 'cameraModel'),
              searchQuery: any(named: 'searchQuery'),
              limit: any(named: 'limit'),
              offset: any(named: 'offset'),
              sortBy: any(named: 'sortBy'),
              ascending: any(named: 'ascending'),
            )).thenAnswer((_) async => [testPhotos.last]);

        final result = await catalogService.queryPhotos(filter: filter);

        expect(result, hasLength(1));
        expect(result[0].rating, 3);
      });

      test('分页参数传递', () async {
        when(() => mockPhotoDao.queryFiltered(
              folderId: any(named: 'folderId'),
              minRating: any(named: 'minRating'),
              pickLabel: any(named: 'pickLabel'),
              colorLabels: any(named: 'colorLabels'),
              dateFrom: any(named: 'dateFrom'),
              dateTo: any(named: 'dateTo'),
              cameraModel: any(named: 'cameraModel'),
              searchQuery: any(named: 'searchQuery'),
              limit: 50,
              offset: 100,
              sortBy: any(named: 'sortBy'),
              ascending: any(named: 'ascending'),
            )).thenAnswer((_) async => []);

        final result = await catalogService.queryPhotos(
          filter: PhotoFilter.empty,
          limit: 50,
          offset: 100,
        );

        expect(result, isEmpty);
        verify(() => mockPhotoDao.queryFiltered(
              limit: 50,
              offset: 100,
              folderId: any(named: 'folderId'),
              minRating: any(named: 'minRating'),
              pickLabel: any(named: 'pickLabel'),
              colorLabels: any(named: 'colorLabels'),
              dateFrom: any(named: 'dateFrom'),
              dateTo: any(named: 'dateTo'),
              cameraModel: any(named: 'cameraModel'),
              searchQuery: any(named: 'searchQuery'),
              sortBy: any(named: 'sortBy'),
              ascending: any(named: 'ascending'),
            )).called(1);
      });
    });

    group('countPhotos', () {
      test('返回计数', () async {
        when(() => mockPhotoDao.countFiltered(
              folderId: any(named: 'folderId'),
              minRating: any(named: 'minRating'),
              pickLabel: any(named: 'pickLabel'),
              colorLabels: any(named: 'colorLabels'),
            )).thenAnswer((_) async => 42);

        final count = await catalogService.countPhotos(
          filter: PhotoFilter.empty,
        );

        expect(count, 42);
      });

      test('带筛选条件的计数', () async {
        const filter = PhotoFilter(pickLabel: 1);

        when(() => mockPhotoDao.countFiltered(
              folderId: any(named: 'folderId'),
              minRating: any(named: 'minRating'),
              pickLabel: 1,
              colorLabels: any(named: 'colorLabels'),
            )).thenAnswer((_) async => 5);

        final count = await catalogService.countPhotos(filter: filter);

        expect(count, 5);
      });
    });

    group('batch operations', () {
      test('batchRate', () async {
        when(() => mockPhotoDao.batchSetRating([1, 2, 3], 4))
            .thenAnswer((_) async => 3);

        await catalogService.batchRate([1, 2, 3], 4);

        verify(() => mockPhotoDao.batchSetRating([1, 2, 3], 4)).called(1);
      });

      test('batchSetPick', () async {
        when(() => mockPhotoDao.batchSetPickLabel([1, 2], 1))
            .thenAnswer((_) async => 2);

        await catalogService.batchSetPick([1, 2], 1);

        verify(() => mockPhotoDao.batchSetPickLabel([1, 2], 1)).called(1);
      });

      test('batchSetColor', () async {
        when(() => mockPhotoDao.batchSetColorLabel([1], 3))
            .thenAnswer((_) async => 1);

        await catalogService.batchSetColor([1], 3);

        verify(() => mockPhotoDao.batchSetColorLabel([1], 3)).called(1);
      });
    });

    group('single photo operations', () {
      test('setRating', () async {
        when(() => mockPhotoDao.setRating(1, 5))
            .thenAnswer((_) async => 1);

        await catalogService.setRating(1, 5);

        verify(() => mockPhotoDao.setRating(1, 5)).called(1);
      });

      test('setPickLabel', () async {
        when(() => mockPhotoDao.setPickLabel(1, 2))
            .thenAnswer((_) async => 1);

        await catalogService.setPickLabel(1, 2);

        verify(() => mockPhotoDao.setPickLabel(1, 2)).called(1);
      });

      test('setColorLabel', () async {
        when(() => mockPhotoDao.setColorLabel(1, 4))
            .thenAnswer((_) async => 1);

        await catalogService.setColorLabel(1, 4);

        verify(() => mockPhotoDao.setColorLabel(1, 4)).called(1);
      });
    });

    group('getCameraModels', () {
      test('返回相机型号计数', () async {
        when(() => mockPhotoDao.getCameraModelCounts())
            .thenAnswer((_) async => {'Canon EOS R5': 10, 'Sony A7 IV': 5});

        final models = await catalogService.getCameraModels();

        expect(models, hasLength(2));
        expect(models['Canon EOS R5'], 10);
      });
    });
  });
}
