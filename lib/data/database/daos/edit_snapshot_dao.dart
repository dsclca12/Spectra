import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'edit_snapshot_dao.g.dart';

/// 编辑快照数据访问对象
@DriftAccessor(tables: [EditSnapshots])
class EditSnapshotDao extends DatabaseAccessor<AppDatabase>
    with _$EditSnapshotDaoMixin {
  EditSnapshotDao(super.db);

  /// 获取指定照片的所有快照（按创建时间倒序）
  Future<List<EditSnapshot>> getByPhotoId(int photoId) async {
    return (select(editSnapshots)
          ..where((t) => t.photoId.equals(photoId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// 创建快照
  Future<int> create(EditSnapshotsCompanion companion) async {
    return into(editSnapshots).insert(companion);
  }

  /// 删除快照
  Future<void> deleteById(int id) async {
    await (delete(editSnapshots)..where((t) => t.id.equals(id))).go();
  }

  /// 删除指定照片的所有快照
  Future<void> deleteByPhotoId(int photoId) async {
    await (delete(editSnapshots)..where((t) => t.photoId.equals(photoId))).go();
  }

  /// 重命名快照
  Future<void> rename(int id, String name) async {
    await (update(editSnapshots)..where((t) => t.id.equals(id)))
        .write(EditSnapshotsCompanion(name: Value(name)));
  }
}