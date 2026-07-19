import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/models/photo_filter.dart';
import 'providers.dart';

// ─── 筛选状态 ───

/// 当前筛选条件
final filterProvider = StateProvider<PhotoFilter>((ref) {
  return const PhotoFilter();
});

/// 当前选中的文件夹 ID
final currentFolderProvider = StateProvider<int?>((ref) => null);

// ─── 照片列表 ───

/// 照片列表 Provider — 响应筛选条件变化
final catalogProvider =
    FutureProvider.autoDispose<List<Photo>>((ref) async {
  final filter = ref.watch(filterProvider);
  final folderId = ref.watch(currentFolderProvider);
  // watch EXIF 刷新计数器 — 后台 EXIF 写入后自动重新查询
  ref.watch(exifRefreshTickProvider);
  final catalogService = ref.read(catalogServiceProvider);

  // 首屏只加载 200 条，滚动时按需分页加载更多
  return catalogService.queryPhotos(
    folderId: folderId,
    filter: filter,
    limit: 200,
    offset: 0,
  );
});

/// 照片总数
final photoCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final filter = ref.watch(filterProvider);
  final folderId = ref.watch(currentFolderProvider);
  final catalogService = ref.read(catalogServiceProvider);
  return catalogService.countPhotos(folderId: folderId, filter: filter);
});

/// 单张照片 Provider
final photoByIdProvider =
    FutureProvider.autoDispose.family<Photo?, int>((ref, id) async {
  // watch EXIF 刷新计数器 — 后台 EXIF 写入后自动重新查询
  ref.watch(exifRefreshTickProvider);
  final photoDao = ref.read(photoDaoProvider);
  return photoDao.getById(id);
});

/// 相机型号列表
final cameraModelsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final catalogService = ref.read(catalogServiceProvider);
  return catalogService.getCameraModels();
});