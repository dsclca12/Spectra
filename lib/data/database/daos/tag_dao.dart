import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'tag_dao.g.dart';

/// 标签数据访问对象
@DriftAccessor(tables: [Tags, PhotoTags])
class TagDao extends DatabaseAccessor<AppDatabase> with _$TagDaoMixin {
  TagDao(super.db);

  /// 获取所有标签
  Future<List<Tag>> getAll() =>
      (select(tags)..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
          .get();

  /// 获取顶级标签
  Future<List<Tag>> getRootTags() =>
      (select(tags)
            ..where((t) => t.parentId.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
          .get();

  /// 获取子标签
  Future<List<Tag>> getChildTags(int parentId) =>
      (select(tags)
            ..where((t) => t.parentId.equals(parentId))
            ..orderBy([(t) => OrderingTerm(expression: t.sortOrder)]))
          .get();

  /// 按 ID 获取
  Future<Tag?> getById(int id) async {
    final result = await (select(tags)..where((t) => t.id.equals(id))).get();
    return result.isEmpty ? null : result.first;
  }

  /// 按名称搜索
  Future<List<Tag>> search(String query) =>
      (select(tags)..where((t) => t.name.like('%$query%'))).get();

  /// 插入标签
  Future<int> insertTag(TagsCompanion tag) => into(tags).insert(tag);

  /// 更新标签
  Future<bool> updateTag(Tag tag) =>
      (update(tags)..where((t) => t.id.equals(tag.id))).write(tag).then(
            (rows) => rows > 0,
          );

  /// 删除标签（级联删除子标签和关联）
  Future<int> deleteTag(int tagId) =>
      (this.delete(tags)..where((t) => t.id.equals(tagId))).go();

  /// 获取标签下照片数（含子标签）
  Future<int> getPhotoCount(int tagId) async {
    // 获取所有子标签 ID
    final allTagIds = await _getAllSubTagIds(tagId);
    final count = await (selectOnly(photoTags)
          ..addColumns([photoTags.photoId.count()])
          ..where(photoTags.tagId.isIn(allTagIds)))
        .get();
    return count.first.read(photoTags.photoId.count()) ?? 0;
  }

  /// 递归获取所有子标签 ID（含自身）
  Future<List<int>> _getAllSubTagIds(int tagId) async {
    final result = <int>[tagId];
    final children = await getChildTags(tagId);
    for (final child in children) {
      result.addAll(await _getAllSubTagIds(child.id));
    }
    return result;
  }

  /// 合并标签 — 将源标签的照片关联转移到目标标签
  ///
  /// 优化：使用 batch insert 替代逐条 insert，减少事务内的 SQL 往返。
  /// 原实现 for 循环逐条 insert，N 张照片 = N 次 INSERT。
  /// 现用 batch.insertAll 单次写入所有关联。
  Future<void> mergeTags(int sourceTagId, int targetTagId) async {
    await transaction(() async {
      // 获取源标签的所有照片关联
      final sourceLinks = await (select(photoTags)
            ..where((t) => t.tagId.equals(sourceTagId)))
          .get();

      // 批量插入目标标签关联（忽略已存在的冲突）
      final companions = sourceLinks.map((link) => PhotoTagsCompanion(
        photoId: Value(link.photoId),
        tagId: Value(targetTagId),
        createdAt: Value(DateTime.now()),
      )).toList();

      if (companions.isNotEmpty) {
        await batch((b) => b.insertAll(photoTags, companions,
            mode: InsertMode.insertOrIgnore));
      }

      // 删除源标签
      await deleteTag(sourceTagId);
    });
  }

  /// 获取标签的层级路径（如 "人像/婚礼/新娘"）
  Future<String> getTagPath(int tagId) async {
    final parts = <String>[];
    int? currentId = tagId;
    while (currentId != null) {
      final tag = await getById(currentId);
      if (tag == null) break;
      parts.insert(0, tag.name);
      currentId = tag.parentId;
    }
    return parts.join(' / ');
  }
}