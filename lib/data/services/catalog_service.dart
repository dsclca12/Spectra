import '../database/daos/photo_dao.dart';
import '../database/app_database.dart';
import '../../data/models/photo_filter.dart';

/// Catalog service — photo query/sort/group logic.
class CatalogService {
  final PhotoDao _photoDao;

  CatalogService({required PhotoDao photoDao}) : _photoDao = photoDao;

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

  /// Count photos.
  Future<int> countPhotos({int? folderId, required PhotoFilter filter}) {
    return _photoDao.countFiltered(
      folderId: filter.folderId ?? folderId,
      minRating: filter.minRating,
      pickLabel: filter.pickLabel,
      colorLabels: filter.colorLabels,
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
    await _photoDao.deletePhoto(photoId);
  }

  /// Batch delete photos (single transaction, avoids N DB round-trips).
  Future<void> removePhotos(List<int> photoIds) async {
    await _photoDao.deletePhotos(photoIds);
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