import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;

import 'package:spectra/data/database/app_database.dart';
import 'package:spectra/data/database/daos/photo_dao.dart';
import 'package:spectra/data/database/daos/tag_dao.dart';
import 'package:spectra/core/enums.dart';

void main() {
  late AppDatabase db;
  late PhotoDao photoDao;
  late TagDao tagDao;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    photoDao = db.photoDao;
    tagDao = db.tagDao;
  });

  tearDown(() async => await db.close());

  group('PhotoDao', () {
    test('插入并查询照片', () async {
      final id = await photoDao.insertPhoto(PhotosCompanion(
        path: const Value('/test/photo.jpg'),
        fileName: const Value('photo.jpg'),
        fileHash: const Value('abc123'),
        fileSize: const Value(1024),
        modifiedAt: Value(DateTime.now()),
        importedAt: Value(DateTime.now()),
      ));

      final photo = await photoDao.getById(id);
      expect(photo, isNotNull);
      expect(photo!.fileName, 'photo.jpg');
      expect(photo.path, '/test/photo.jpg');
    });

    test('按路径查询', () async {
      await photoDao.insertPhoto(PhotosCompanion(
        path: const Value('/test/path.jpg'),
        fileName: const Value('path.jpg'),
        fileHash: const Value('hash1'),
        fileSize: const Value(2048),
        modifiedAt: Value(DateTime.now()),
        importedAt: Value(DateTime.now()),
      ));

      final photo = await photoDao.getByPath('/test/path.jpg');
      expect(photo, isNotNull);
      expect(photo!.fileName, 'path.jpg');
    });

    test('设置评分', () async {
      final id = await photoDao.insertPhoto(PhotosCompanion(
        path: const Value('/test/rating.jpg'),
        fileName: const Value('rating.jpg'),
        fileHash: const Value('hash2'),
        fileSize: const Value(512),
        modifiedAt: Value(DateTime.now()),
        importedAt: Value(DateTime.now()),
      ));

      await photoDao.setRating(id, 4);
      final photo = await photoDao.getById(id);
      expect(photo!.rating, 4);
    });

    test('批量设置评分', () async {
      final ids = <int>[];
      for (var i = 0; i < 5; i++) {
        ids.add(await photoDao.insertPhoto(PhotosCompanion(
          path: Value('/test/batch_$i.jpg'),
          fileName: Value('batch_$i.jpg'),
          fileHash: Value('hash_$i'),
          fileSize: const Value(256),
          modifiedAt: Value(DateTime.now()),
          importedAt: Value(DateTime.now()),
        )));
      }

      await photoDao.batchSetRating(ids, 3);
      for (final id in ids) {
        final photo = await photoDao.getById(id);
        expect(photo!.rating, 3);
      }
    });

    test('设置旗标和色标', () async {
      final id = await photoDao.insertPhoto(PhotosCompanion(
        path: const Value('/test/labels.jpg'),
        fileName: const Value('labels.jpg'),
        fileHash: const Value('hash3'),
        fileSize: const Value(128),
        modifiedAt: Value(DateTime.now()),
        importedAt: Value(DateTime.now()),
      ));

      await photoDao.setPickLabel(id, PickLabel.pick);
      await photoDao.setColorLabel(id, ColorLabel.red);

      final photo = await photoDao.getById(id);
      expect(photo!.pickLabel, PickLabel.pick);
      expect(photo.colorLabel, ColorLabel.red);
    });

    test('删除照片', () async {
      final id = await photoDao.insertPhoto(PhotosCompanion(
        path: const Value('/test/delete.jpg'),
        fileName: const Value('delete.jpg'),
        fileHash: const Value('hash4'),
        fileSize: const Value(64),
        modifiedAt: Value(DateTime.now()),
        importedAt: Value(DateTime.now()),
      ));

      await photoDao.deletePhoto(id);
      final photo = await photoDao.getById(id);
      expect(photo, isNull);
    });

    test('计数', () async {
      await photoDao.insertPhoto(PhotosCompanion(
        path: const Value('/test/count1.jpg'),
        fileName: const Value('count1.jpg'),
        fileHash: const Value('h1'),
        fileSize: const Value(32),
        modifiedAt: Value(DateTime.now()),
        importedAt: Value(DateTime.now()),
      ));
      await photoDao.insertPhoto(PhotosCompanion(
        path: const Value('/test/count2.jpg'),
        fileName: const Value('count2.jpg'),
        fileHash: const Value('h2'),
        fileSize: const Value(32),
        modifiedAt: Value(DateTime.now()),
        importedAt: Value(DateTime.now()),
      ));

      final count = await photoDao.countAll();
      expect(count, 2);
    });
  });

  group('TagDao', () {
    test('创建和查询标签', () async {
      final id = await tagDao.insertTag(TagsCompanion(
        name: const Value('人像'),
        createdAt: Value(DateTime.now()),
      ));

      final tag = await tagDao.getById(id);
      expect(tag, isNotNull);
      expect(tag!.name, '人像');
    });

    test('层级标签', () async {
      final parentId = await tagDao.insertTag(TagsCompanion(
        name: const Value('婚礼'),
        createdAt: Value(DateTime.now()),
      ));
      await tagDao.insertTag(TagsCompanion(
        name: const Value('新娘'),
        parentId: Value(parentId),
        createdAt: Value(DateTime.now()),
      ));

      final children = await tagDao.getChildTags(parentId);
      expect(children.length, 1);
      expect(children.first.name, '新娘');
    });

    test('搜索标签', () async {
      await tagDao.insertTag(TagsCompanion(
        name: const Value('风景'),
        createdAt: Value(DateTime.now()),
      ));
      await tagDao.insertTag(TagsCompanion(
        name: const Value('人像'),
        createdAt: Value(DateTime.now()),
      ));

      final results = await tagDao.search('风');
      expect(results.length, 1);
      expect(results.first.name, '风景');
    });
  });
}