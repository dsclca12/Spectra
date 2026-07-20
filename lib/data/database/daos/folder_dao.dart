import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'folder_dao.g.dart';

/// 文件夹数据访问对象
@DriftAccessor(tables: [Folders, Photos])
class FolderDao extends DatabaseAccessor<AppDatabase> with _$FolderDaoMixin {
  FolderDao(super.db);

  /// 获取所有文件夹
  Future<List<Folder>> getAll() =>
      (select(folders)..orderBy([(f) => OrderingTerm(expression: f.name)]))
          .get();

  /// 获取根文件夹
  Future<List<Folder>> getRootFolders() =>
      (select(folders)..where((f) => f.parentId.isNull())).get();

  /// 获取子文件夹
  Future<List<Folder>> getChildFolders(int parentId) =>
      (select(folders)..where((f) => f.parentId.equals(parentId))).get();

  /// 按路径获取
  Future<Folder?> getByPath(String path) async {
    final result =
        await (select(folders)..where((f) => f.path.equals(path))).get();
    return result.isEmpty ? null : result.first;
  }

  /// 按 ID 获取
  Future<Folder?> getById(int id) async {
    final result = await (select(folders)..where((f) => f.id.equals(id))).get();
    return result.isEmpty ? null : result.first;
  }

  /// 插入或更新文件夹（按路径冲突时更新）
  Future<int> insertOnConflictUpdate(FoldersCompanion folder) =>
      into(folders).insertOnConflictUpdate(folder);

  /// 更新文件夹
  Future<bool> updateFolder(Folder folder) =>
      (update(folders)..where((f) => f.id.equals(folder.id)))
          .write(folder)
          .then((rows) => rows > 0);

  /// 删除文件夹
  Future<int> deleteFolder(int folderId) =>
      (this.delete(folders)..where((f) => f.id.equals(folderId))).go();

  /// 更新照片计数
  Future<int> updatePhotoCount(int folderId, int count) =>
      (update(folders)..where((f) => f.id.equals(folderId)))
          .write(FoldersCompanion(photoCount: Value(count)));

  /// 更新最后扫描时间
  Future<int> updateLastScanned(int folderId) =>
      (update(folders)..where((f) => f.id.equals(folderId))).write(
        FoldersCompanion(lastScannedAt: Value(DateTime.now())),
      );

  /// 更新监听状态
  Future<int> setWatched(int folderId, bool watched) =>
      (update(folders)..where((f) => f.id.equals(folderId))).write(
        FoldersCompanion(isWatched: Value(watched ? 1 : 0)),
      );

  /// 修复所有文件夹的照片计数（启动时调用）
  ///
  /// 性能优化：单次 SQL GROUP BY 查询替代 N 次独立 COUNT 查询。
  /// 原实现对每个文件夹执行一条 SELECT COUNT(*)，N 个文件夹 = N 次 DB 往返。
  /// 现用 GROUP BY 一次性获取所有文件夹的真实照片数，再逐条回写差异。
  /// 注意：逐条回写不可避免，因为 drift 的 batch update 不支持按条件更新不同值。
  /// 若文件夹数量极大（>1000），可考虑用临时表 + 单条 UPDATE ... FROM 替代。
  Future<void> repairAllPhotoCounts() async {
    // 单次 GROUP BY 查询：folder_id → COUNT(*)
    // 一次性获取所有文件夹的真实照片数，避免 N 次独立 COUNT
    final countQuery = await (selectOnly(photos)
          ..addColumns([photos.folderId, photos.id.count()])
          ..where(photos.folderId.isNotNull())
          ..groupBy([photos.folderId]))
        .get();

    // 将查询结果转为 Map<folderId, actualCount>
    final actualCounts = <int, int>{};
    for (final row in countQuery) {
      final folderId = row.read(photos.folderId)!;
      final count = row.read(photos.id.count()) ?? 0;
      actualCounts[folderId] = count;
    }

    // 逐条回写差异 — 只更新计数不一致的文件夹
    final allFolders = await getAll();
    for (final folder in allFolders) {
      final actualCount = actualCounts[folder.id] ?? 0;
      if (folder.photoCount != actualCount) {
        await updatePhotoCount(folder.id, actualCount);
      }
    }
  }
}