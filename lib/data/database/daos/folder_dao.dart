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
}