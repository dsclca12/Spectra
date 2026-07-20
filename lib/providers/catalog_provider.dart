import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
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

// ─── 照片列表（分页）───

/// 当前分页偏移量（每页 200 条）
/// 用户滚动到底部时由 UI 递增此值，catalogProvider 自动触发重新查询
/// offset 变化会丢弃之前加载的数据 — 但对于 <= 2000 张照片足够高效
final catalogPageOffsetProvider = StateProvider<int>((ref) => 0);

/// 照片列表 Provider — 响应筛选条件变化，支持滚动分页
///
/// ⚡ 性能说明：
/// - 首屏加载 200 条（pageSize=200），用户滚动到底部时递增 offset。
/// - 使用 autoDispose 防止 FutureProvider 持久占用内存。
/// - watch exifRefreshTickProvider — 后台 EXIF 写入后自动刷新列表。
/// - 对于 >= 10000 张照片的大目录，建议迁移到 StateNotifierProvider +
///   增量 append 模式，避免每次 offset 变化重新查询。
///
/// 筛选条件通过 [filterProvider] 和 [currentFolderProvider] 控制。
final catalogProvider =
    FutureProvider.autoDispose<List<Photo>>((ref) async {
  final filter = ref.watch(filterProvider);
  final folderId = ref.watch(currentFolderProvider);
  final offset = ref.watch(catalogPageOffsetProvider);
  // watch EXIF 刷新计数器 — 后台 EXIF 写入后自动重新查询
  ref.watch(exifRefreshTickProvider);
  final catalogService = ref.read(catalogServiceProvider);
  final pageSize = AppConstants.defaultPageSize;

  return catalogService.queryPhotos(
    folderId: folderId,
    filter: filter,
    limit: pageSize,
    offset: offset,
  );
});

/// 照片总数 — 用于 UI 计算总页数、显示"共 N 张"
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