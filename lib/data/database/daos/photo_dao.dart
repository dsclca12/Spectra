import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'photo_dao.g.dart';

/// 照片数据访问对象
@DriftAccessor(tables: [Photos, PhotoTags, Tags, Folders])
class PhotoDao extends DatabaseAccessor<AppDatabase> with _$PhotoDaoMixin {
  PhotoDao(super.db);

  // ─── 查询 ───

  /// 获取所有照片（分页）
  Future<List<Photo>> getAll({int? limit, int? offset}) {
    final query = select(photos)
      ..orderBy([
        (p) => OrderingTerm(
              expression: p.importedAt,
              mode: OrderingMode.desc,
            )
      ]);
    if (limit != null) query.limit(limit, offset: offset ?? 0);
    return query.get();
  }

  /// 按 ID 获取
  Future<Photo?> getById(int id) async {
    final result = await (select(photos)..where((p) => p.id.equals(id))).get();
    return result.isEmpty ? null : result.first;
  }

  /// 按 ID 列表批量获取
  Future<List<Photo>> getByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    // 分批查询避免 SQLite IN 子句过长
    final result = <Photo>[];
    const batchSize = 500;
    for (var i = 0; i < ids.length; i += batchSize) {
      final chunk = ids.sublist(
        i,
        (i + batchSize > ids.length) ? ids.length : i + batchSize,
      );
      final rows = await (select(photos)..where((p) => p.id.isIn(chunk))).get();
      result.addAll(rows);
    }
    return result;
  }

  /// 按路径获取
  Future<Photo?> getByPath(String path) async {
    final result =
        await (select(photos)..where((p) => p.path.equals(path))).get();
    return result.isEmpty ? null : result.first;
  }

  /// 按文件夹获取
  Future<List<Photo>> getByFolder(
    int folderId, {
    int? limit,
    int? offset,
    String sortBy = 'dateTaken',
    bool ascending = true,
  }) {
    final query = select(photos)..where((p) => p.folderId.equals(folderId));

    final orderExpr = switch (sortBy) {
      'importedAt' => photos.importedAt,
      'rating' => photos.rating,
      'fileName' => photos.fileName,
      'dateTaken' => photos.dateTaken,
      _ => photos.dateTaken,
    };

    query.orderBy([
      (p) => OrderingTerm(
            expression: orderExpr,
            mode: ascending ? OrderingMode.asc : OrderingMode.desc,
          )
    ]);

    if (limit != null) query.limit(limit, offset: offset ?? 0);
    return query.get();
  }

  /// 组合筛选查询
  Future<List<Photo>> queryFiltered({
    int? folderId,
    int? minRating,
    int? maxRating,
    int? pickLabel,
    List<int>? colorLabels,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? cameraModel,
    String? searchQuery,
    int limit = 200,
    int offset = 0,
    String sortBy = 'dateTaken',
    bool ascending = true,
  }) {
    final query = select(photos);

    // 文件夹筛选
    if (folderId != null) {
      query.where((p) => p.folderId.equals(folderId));
    }

    // 星级筛选
    if (minRating != null && maxRating != null) {
      query.where((p) => p.rating.isBetweenValues(minRating, maxRating));
    } else if (minRating != null) {
      query.where((p) => p.rating.isBiggerOrEqualValue(minRating));
    }

    // 旗标筛选
    if (pickLabel != null) {
      query.where((p) => p.pickLabel.equals(pickLabel));
    }

    // 色标筛选（多选 OR）
    if (colorLabels != null && colorLabels.isNotEmpty) {
      query.where((p) => p.colorLabel.isIn(colorLabels));
    }

    // 日期范围
    if (dateFrom != null && dateTo != null) {
      query.where((p) => p.dateTaken.isBetweenValues(dateFrom, dateTo));
    } else if (dateFrom != null) {
      query.where((p) => p.dateTaken.isBiggerOrEqualValue(dateFrom));
    } else if (dateTo != null) {
      query.where((p) => p.dateTaken.isSmallerOrEqualValue(dateTo));
    }

    // 相机型号
    if (cameraModel != null && cameraModel.isNotEmpty) {
      query.where((p) => p.cameraModel.like('%$cameraModel%'));
    }

    // 搜索查询（文件名 + IPTC 标题 + 描述 + 相机型号 + 关键词）
    if (searchQuery != null && searchQuery.isNotEmpty) {
      final pattern = '%$searchQuery%';
      query.where(
        (p) =>
            p.fileName.like(pattern) |
            p.iptcTitle.like(pattern) |
            p.iptcDescription.like(pattern) |
            p.iptcKeywords.like(pattern) |
            p.cameraModel.like(pattern),
      );
    }

    // 排序
    final orderExpr = switch (sortBy) {
      'importedAt' => photos.importedAt,
      'rating' => photos.rating,
      'fileName' => photos.fileName,
      'dateTaken' => photos.dateTaken,
      _ => photos.dateTaken,
    };
    query.orderBy([
      (p) => OrderingTerm(
            expression: orderExpr,
            mode: ascending ? OrderingMode.asc : OrderingMode.desc,
          )
    ]);

    query.limit(limit, offset: offset);
    return query.get();
  }

  /// 计数
  Future<int> countAll() async {
    final result = await (selectOnly(photos)..addColumns([photos.id.count()])).get();
    return result.first.read(photos.id.count()) ?? 0;
  }

  Future<int> countByFolder(int folderId) async {
    final count = await
        (selectOnly(photos)..addColumns([photos.id.count()])
          ..where(photos.folderId.equals(folderId))).get();
    return count.first.read(photos.id.count()) ?? 0;
  }

  Future<int> countFiltered({
    int? folderId,
    int? minRating,
    int? pickLabel,
    List<int>? colorLabels,
  }) async {
    final query = selectOnly(photos)..addColumns([photos.id.count()]);

    if (folderId != null) {
      query.where(photos.folderId.equals(folderId));
    }
    if (minRating != null) {
      query.where(photos.rating.isBiggerOrEqualValue(minRating));
    }
    if (pickLabel != null) {
      query.where(photos.pickLabel.equals(pickLabel));
    }
    if (colorLabels != null && colorLabels.isNotEmpty) {
      query.where(photos.colorLabel.isIn(colorLabels));
    }

    final result = await query.get();
    return result.first.read(photos.id.count()) ?? 0;
  }

  // ─── 写入 ───

  /// 插入照片
  Future<int> insertPhoto(PhotosCompanion photo) =>
      into(photos).insert(photo);

  /// UPSERT — 按路径冲突时更新
  Future<int> insertOnConflictUpdate(PhotosCompanion photo) =>
      into(photos).insertOnConflictUpdate(photo);

  /// 批量插入
  Future<void> batchInsert(List<PhotosCompanion> photoList) async {
    await batch((b) => b.insertAll(photos, photoList));
  }

  /// 批量插入并返回插入的行（含自增 ID）
  ///
  /// 使用 drift batch API 真正批量插入，然后一次性查询取回所有新行
  /// 比逐条 insertReturning 事务开销低得多
  Future<List<Photo>> batchInsertReturning(List<PhotosCompanion> photoList) async {
    if (photoList.isEmpty) return [];
    // 批量插入（单事务，无逐条往返）
    await batch((b) => b.insertAll(photos, photoList));
    // 一次性查询刚插入的行（按 importedAt 降序取前 N 条）
    // 注意：这假设 photoList 中的 importedAt 相同（导入场景成立）
    final inserted = await (select(photos)
          ..orderBy([(p) => OrderingTerm(
                expression: p.importedAt,
                mode: OrderingMode.desc,
              )])
          ..limit(photoList.length))
        .get();
    return inserted;
  }

  /// 批量查询已存在的路径集合（用于导入去重）
  Future<Set<String>> getExistingPaths(List<String> paths) async {
    if (paths.isEmpty) return {};
    // 分批查询避免 SQLite IN 子句过长
    final result = <String>{};
    const batchSize = 500;
    for (var i = 0; i < paths.length; i += batchSize) {
      final chunk = paths.sublist(
        i,
        (i + batchSize > paths.length) ? paths.length : i + batchSize,
      );
      final query = selectOnly(photos)..addColumns([photos.path]);
      query.where(photos.path.isIn(chunk));
      final rows = await query.get();
      for (final row in rows) {
        result.add(row.read(photos.path)!);
      }
    }
    return result;
  }

  /// 更新照片
  Future<bool> updatePhoto(Photo photo) =>
      (update(photos)..where((p) => p.id.equals(photo.id))).write(photo).then(
            (rows) => rows > 0,
          );

  // ─── 分类操作 ───

  /// 设置单张评分
  Future<int> setRating(int photoId, int rating) =>
      (update(photos)..where((p) => p.id.equals(photoId)))
          .write(PhotosCompanion(rating: Value(rating)));

  /// 批量设置评分
  Future<int> batchSetRating(List<int> photoIds, int rating) =>
      (update(photos)..where((p) => p.id.isIn(photoIds)))
          .write(PhotosCompanion(rating: Value(rating)));

  /// 设置单张旗标
  Future<int> setPickLabel(int photoId, int label) =>
      (update(photos)..where((p) => p.id.equals(photoId)))
          .write(PhotosCompanion(pickLabel: Value(label)));

  /// 批量设置旗标
  Future<int> batchSetPickLabel(List<int> photoIds, int label) =>
      (update(photos)..where((p) => p.id.isIn(photoIds)))
          .write(PhotosCompanion(pickLabel: Value(label)));

  /// 设置单张色标
  Future<int> setColorLabel(int photoId, int label) =>
      (update(photos)..where((p) => p.id.equals(photoId)))
          .write(PhotosCompanion(colorLabel: Value(label)));

  /// 批量设置色标
  Future<int> batchSetColorLabel(List<int> photoIds, int label) =>
      (update(photos)..where((p) => p.id.isIn(photoIds)))
          .write(PhotosCompanion(colorLabel: Value(label)));

  // ─── 标签关联 ───

  /// 添加标签
  Future<void> addTag(int photoId, int tagId) async {
    await into(photoTags).insert(
      PhotoTagsCompanion(
        photoId: Value(photoId),
        tagId: Value(tagId),
        createdAt: Value(DateTime.now()),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// 移除标签
  Future<int> removeTag(int photoId, int tagId) =>
      (delete(photoTags)
            ..where((t) =>
                t.photoId.equals(photoId) & t.tagId.equals(tagId)))
          .go();

  /// 获取照片的所有标签
  Future<List<Tag>> getTagsForPhoto(int photoId) async {
    final query = select(tags).join([
      innerJoin(photoTags, photoTags.tagId.equalsExp(tags.id)),
    ])
      ..where(photoTags.photoId.equals(photoId));
    final rows = await query.get();
    return rows.map((row) => row.readTable(tags)).toList();
  }

  /// 按标签获取照片
  Future<List<Photo>> getPhotosByTag(List<int> tagIds) async {
    final query = selectOnly(photos).join([
      innerJoin(photoTags, photoTags.photoId.equalsExp(photos.id)),
    ])
      ..where(photoTags.tagId.isIn(tagIds))
      ..addColumns([photos.id]);
    final rows = await query.get();
    final photoIds = rows.map((row) => row.read(photos.id)!).toSet();
    if (photoIds.isEmpty) return [];
    return (select(photos)..where((p) => p.id.isIn(photoIds))).get();
  }

  // ─── 删除 ───

  Future<int> deletePhoto(int photoId) =>
      (delete(photos)..where((p) => p.id.equals(photoId))).go();

  /// 批量删除照片 — 单事务，避免逐条 DELETE 的 N 次 DB 往返
  Future<int> deletePhotos(List<int> photoIds) async {
    if (photoIds.isEmpty) return 0;
    // 分批处理避免 SQLite IN 子句过长
    var total = 0;
    const batchSize = 500;
    for (var i = 0; i < photoIds.length; i += batchSize) {
      final chunk = photoIds.sublist(
        i,
        (i + batchSize > photoIds.length) ? photoIds.length : i + batchSize,
      );
      total += await (delete(photos)..where((p) => p.id.isIn(chunk))).go();
    }
    return total;
  }

  Future<int> deleteByPath(String path) =>
      (delete(photos)..where((p) => p.path.equals(path))).go();

  /// 查询缺少 EXIF 数据的照片（用于启动时重试读取）
  /// 条件：camera_make/camera_model/date_taken 均为 null
  Future<List<Photo>> getPhotosWithoutExif({int limit = 100}) {
    final query = select(photos)
      ..where((p) =>
          p.cameraMake.isNull() &
          p.cameraModel.isNull() &
          p.dateTaken.isNull())
      ..orderBy([(p) => OrderingTerm(
            expression: p.importedAt,
            mode: OrderingMode.desc,
          )])
      ..limit(limit);
    return query.get();
  }

  // ─── 统计 ───

  /// 获取相机型号统计
  Future<Map<String, int>> getCameraModelCounts() async {
    final query = selectOnly(photos)
      ..addColumns([photos.cameraModel, photos.id.count()])
      ..where(photos.cameraModel.isNotNull())
      ..groupBy([photos.cameraModel]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(photos.cameraModel)!: row.read(photos.id.count()) ?? 0,
    };
  }

  /// 获取评分分布
  Future<Map<int, int>> getRatingDistribution() async {
    final query = selectOnly(photos)
      ..addColumns([photos.rating, photos.id.count()])
      ..groupBy([photos.rating]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(photos.rating)!: row.read(photos.id.count()) ?? 0,
    };
  }

  /// 更新缩略图状态
  Future<int> updateThumbnailStatus(int photoId, int status) =>
      (update(photos)..where((p) => p.id.equals(photoId))).write(
        PhotosCompanion(
          thumbnailStatus: Value(status),
          thumbnailGeneratedAt:
              status == 2 ? Value(DateTime.now()) : const Value.absent(),
        ),
      );

  /// 更新 EXIF 元数据
  Future<int> updateExif(int photoId, PhotosCompanion exif) =>
      (update(photos)..where((p) => p.id.equals(photoId))).write(exif);

  /// 按路径更新 EXIF 元数据（用于导入时 fire-and-forget，无需 photoId）
  Future<int> updateExifByPath(String filePath, PhotosCompanion exif) =>
      (update(photos)..where((p) => p.path.equals(filePath))).write(exif);

  /// 更新同步状态
  Future<int> updateSyncStatus(int photoId, int status) =>
      (update(photos)..where((p) => p.id.equals(photoId)))
          .write(PhotosCompanion(syncStatus: Value(status)));
}