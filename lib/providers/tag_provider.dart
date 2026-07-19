import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/models/tag_node.dart';
import 'providers.dart';

/// 标签树 Provider
final tagTreeProvider =
    FutureProvider.autoDispose<List<TagNode>>((ref) async {
  final tagService = ref.read(tagServiceProvider);
  return tagService.getTagTree();
});

/// 所有标签列表
final allTagsProvider = FutureProvider.autoDispose<List<Tag>>((ref) async {
  final tagService = ref.read(tagServiceProvider);
  return tagService.getAllTags();
});

/// 照片的标签列表
final photoTagsProvider =
    FutureProvider.autoDispose.family<List<Tag>, int>((ref, photoId) async {
  final tagService = ref.read(tagServiceProvider);
  return tagService.getTagsForPhoto(photoId);
});

/// 标签搜索
final tagSearchProvider =
    FutureProvider.autoDispose.family<List<Tag>, String>((ref, query) async {
  if (query.isEmpty) return [];
  final tagService = ref.read(tagServiceProvider);
  return tagService.searchTags(query);
});