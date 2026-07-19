import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'edit_history_dao.g.dart';

/// 编辑操作历史数据访问对象
@DriftAccessor(tables: [EditHistory])
class EditHistoryDao extends DatabaseAccessor<AppDatabase>
    with _$EditHistoryDaoMixin {
  EditHistoryDao(super.db);

  /// 获取指定照片的操作历史（按时间倒序，最新的在前）
  Future<List<EditHistoryData>> getByPhotoId(int photoId) async {
    return (select(editHistory)
          ..where((t) => t.photoId.equals(photoId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// 添加历史记录
  Future<int> add(EditHistoryCompanion companion) async {
    return into(editHistory).insert(companion);
  }

  /// 删除指定照片的所有历史
  Future<void> deleteByPhotoId(int photoId) async {
    await (delete(editHistory)..where((t) => t.photoId.equals(photoId))).go();
  }

  /// 清理历史，保留最近 [keepCount] 条
  Future<void> pruneHistory(int photoId, int keepCount) async {
    final all = await (select(editHistory)
          ..where((t) => t.photoId.equals(photoId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();

    if (all.length <= keepCount) return;

    // 删除超出上限的旧记录
    final toDelete = all.skip(keepCount).map((e) => e.id).toList();
    for (final id in toDelete) {
      await (delete(editHistory)..where((t) => t.id.equals(id))).go();
    }
  }

  /// 获取历史记录数量
  Future<int> countByPhotoId(int photoId) async {
    final count = countAll();
    final query = selectOnly(editHistory)
      ..addColumns([count])
      ..where(editHistory.photoId.equals(photoId));
    final result = await query.get();
    return result.first.read(count) ?? 0;
  }
}