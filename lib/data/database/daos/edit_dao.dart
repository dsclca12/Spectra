import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'edit_dao.g.dart';

/// 照片编辑参数数据访问对象
@DriftAccessor(tables: [PhotoEdits])
class EditDao extends DatabaseAccessor<AppDatabase> with _$EditDaoMixin {
  EditDao(super.db);

  /// 获取指定照片的编辑参数
  Future<PhotoEdit?> getByPhotoId(int photoId) async {
    final result = await (select(photoEdits)
          ..where((t) => t.photoId.equals(photoId)))
        .get();
    return result.isEmpty ? null : result.first;
  }

  /// 保存编辑参数（upsert — 存在则更新，不存在则插入）
  Future<void> upsert(PhotoEditsCompanion companion) async {
    await into(photoEdits).insertOnConflictUpdate(companion);
  }

  /// 删除指定照片的编辑参数（重置）
  Future<void> deleteByPhotoId(int photoId) async {
    await (delete(photoEdits)..where((t) => t.photoId.equals(photoId))).go();
  }

  /// 检查指定照片是否有编辑参数
  Future<bool> hasEdits(int photoId) async {
    final result = await (select(photoEdits)
          ..where((t) => t.photoId.equals(photoId)))
        .get();
    return result.isNotEmpty;
  }

  /// 获取所有有编辑参数的照片 ID
  Future<List<int>> getEditedPhotoIds() async {
    final query = selectOnly(photoEdits)..addColumns([photoEdits.photoId]);
    final rows = await query.get();
    return rows.map((row) => row.read(photoEdits.photoId)!).toList();
  }
}