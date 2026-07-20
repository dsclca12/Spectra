import '../database/daos/photo_dao.dart';
import '../database/daos/folder_dao.dart';
import '../database/app_database.dart';
import '../../data/models/photo_filter.dart';

/// Catalog service — photo query/sort/group logic.
class CatalogService {
  final PhotoDao _photoDao;
  final FolderDao _folderDao;

  CatalogService({required PhotoDao photoDao, required FolderDao folderDao})
      : _photoDao = photoDao,
        _folderDao = folderDao;

  /// Query photo list.
  Future<List<Photo>> queryPhotos({
    int? folderId,
    required PhotoFilter filter,
    int limit = 200,
    int offset = 0,
  }) {
    return _photoDao.queryFiltered(
      folderId: filter.folderId ?? folderId,
      minRating: filter.minRating,
      pickLabel: filter.pickLabel,
      colorLabels: filter.colorLabels,
      dateFrom: filter.dateFrom,
      dateTo: filter.dateTo,
      cameraModel: filter.cameraModel,
      searchQuery: filter.searchQuery,
      limit: limit,
      offset: offset,
      sortBy: filter.sortBy,
      ascending: filter.ascending,
    );
  }

  /// 统计照片数量 — 与 queryPhotos 的筛选逻辑保持一致。
  ///
  /// 传递全部筛选参数给 DAO，确保计数与列表查询结果一致。
  /// 扩展了 dateFrom/dateTo/cameraModel/searchQuery 参数，
  /// 以便在搜索或筛选时状态栏显示精确的计数。
  Future<int> countPhotos({int? folderId, required PhotoFilter filter}) {
    return _photoDao.countFiltered(
      folderId: filter.folderId ?? folderId,
      minRating: filter.minRating,
      pickLabel: filter.pickLabel,
      colorLabels: filter.colorLabels,
      dateFrom: filter.dateFrom,
      dateTo: filter.dateTo,
      cameraModel: filter.cameraModel,
      searchQuery: filter.searchQuery,
    );
  }

  /// Batch set rating.
  Future<void> batchRate(List<int> photoIds, int rating) async {
    await _photoDao.batchSetRating(photoIds, rating);
  }

  /// Batch set pick label.
  Future<void> batchSetPick(List<int> photoIds, int pickLabel) async {
    await _photoDao.batchSetPickLabel(photoIds, pickLabel);
  }

  /// Batch set color label.
  Future<void> batchSetColor(List<int> photoIds, int colorLabel) async {
    await _photoDao.batchSetColorLabel(photoIds, colorLabel);
  }

  /// Set single photo rating.
  Future<void> setRating(int photoId, int rating) async {
    await _photoDao.setRating(photoId, rating);
  }

  /// Set single photo pick label.
  Future<void> setPickLabel(int photoId, int pickLabel) async {
    await _photoDao.setPickLabel(photoId, pickLabel);
  }

  /// Set single photo color label.
  Future<void> setColorLabel(int photoId, int colorLabel) async {
    await _photoDao.setColorLabel(photoId, colorLabel);
  }

  /// Get camera model list.
  Future<Map<String, int>> getCameraModels() {
    return _photoDao.getCameraModelCounts();
  }

  /// Get rating distribution.
  Future<Map<int, int>> getRatingDistribution() {
    return _photoDao.getRatingDistribution();
  }

  /// Delete photo (remove from catalog, does not delete file).
  Future<void> removePhoto(int photoId) async {
    final photo = await _photoDao.getById(photoId);
    if (photo == null) return;
    await _photoDao.deletePhoto(photoId);
    // 更新文件夹照片计数
    if (photo.folderId != null) {
      final count = await _photoDao.countByFolder(photo.folderId!);
      await _folderDao.updatePhotoCount(photo.folderId!, count);
    }
  }

  /// Batch delete photos (single transaction, avoids N DB round-trips).
  Future<void> removePhotos(List<int> photoIds) async {
    if (photoIds.isEmpty) return;
    // 先查询要删除的照片以获取所属文件夹
    final photos = await _photoDao.getByIds(photoIds);
    final folderIds = photos
        .map((p) => p.folderId)
        .where((id) => id != null)
        .cast<int>()
        .toSet();
    await _photoDao.deletePhotos(photoIds);
    // 更新受影响的文件夹照片计数
    for (final folderId in folderIds) {
      final count = await _photoDao.countByFolder(folderId);
      await _folderDao.updatePhotoCount(folderId, count);
    }
  }

  /// Batch get photos by ID list.
  Future<List<Photo>> getPhotosByIds(List<int> photoIds) async {
    return _photoDao.getByIds(photoIds);
  }

  /// Query all matching photos (no pagination, for export).
  Future<List<Photo>> queryAllPhotos({
    int? folderId,
    required PhotoFilter filter,
  }) async {
    return _photoDao.queryFiltered(
      folderId: filter.folderId ?? folderId,
      minRating: filter.minRating,
      maxRating: filter.maxRating,
      pickLabel: filter.pickLabel,
      colorLabels: filter.colorLabels,
      dateFrom: filter.dateFrom,
      dateTo: filter.dateTo,
      cameraModel: filter.cameraModel,
      searchQuery: filter.searchQuery,
      limit: 100000,
      offset: 0,
      sortBy: filter.sortBy,
      ascending: filter.ascending,
    );
  }
}