/// 照片筛选条件值对象
class PhotoFilter {
  final int? folderId;
  final int? minRating;
  final int? maxRating;
  final int? pickLabel;
  final List<int>? colorLabels;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String? cameraModel;
  final String? searchQuery;
  final String sortBy;
  final bool ascending;

  const PhotoFilter({
    this.folderId,
    this.minRating,
    this.maxRating,
    this.pickLabel,
    this.colorLabels,
    this.dateFrom,
    this.dateTo,
    this.cameraModel,
    this.searchQuery,
    this.sortBy = 'dateTaken',
    this.ascending = true,
  });

  /// 空筛选器（无任何条件）
  static const empty = PhotoFilter();

  /// 是否有活跃的筛选条件
  bool get hasActiveFilters =>
      folderId != null ||
      minRating != null ||
      pickLabel != null ||
      (colorLabels != null && colorLabels!.isNotEmpty) ||
      dateFrom != null ||
      dateTo != null ||
      (cameraModel != null && cameraModel!.isNotEmpty) ||
      (searchQuery != null && searchQuery!.isNotEmpty);

  /// 创建副本
  PhotoFilter copyWith({
    int? folderId,
    int? minRating,
    int? maxRating,
    int? pickLabel,
    List<int>? colorLabels,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? cameraModel,
    String? searchQuery,
    String? sortBy,
    bool? ascending,
    bool clearFolderId = false,
    bool clearMinRating = false,
    bool clearPickLabel = false,
    bool clearColorLabels = false,
    bool clearDateRange = false,
    bool clearCameraModel = false,
    bool clearSearchQuery = false,
  }) {
    return PhotoFilter(
      folderId: clearFolderId ? null : folderId ?? this.folderId,
      minRating: clearMinRating ? null : minRating ?? this.minRating,
      maxRating: maxRating ?? this.maxRating,
      pickLabel: clearPickLabel ? null : pickLabel ?? this.pickLabel,
      colorLabels:
          clearColorLabels ? null : colorLabels ?? this.colorLabels,
      dateFrom: clearDateRange ? null : dateFrom ?? this.dateFrom,
      dateTo: clearDateRange ? null : dateTo ?? this.dateTo,
      cameraModel:
          clearCameraModel ? null : cameraModel ?? this.cameraModel,
      searchQuery:
          clearSearchQuery ? null : searchQuery ?? this.searchQuery,
      sortBy: sortBy ?? this.sortBy,
      ascending: ascending ?? this.ascending,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoFilter &&
          runtimeType == other.runtimeType &&
          folderId == other.folderId &&
          minRating == other.minRating &&
          maxRating == other.maxRating &&
          pickLabel == other.pickLabel &&
          _listEquals(colorLabels, other.colorLabels) &&
          dateFrom == other.dateFrom &&
          dateTo == other.dateTo &&
          cameraModel == other.cameraModel &&
          searchQuery == other.searchQuery &&
          sortBy == other.sortBy &&
          ascending == other.ascending;

  @override
  int get hashCode => Object.hash(
        folderId,
        minRating,
        maxRating,
        pickLabel,
        Object.hashAll(colorLabels ?? []),
        dateFrom,
        dateTo,
        cameraModel,
        searchQuery,
        sortBy,
        ascending,
      );

  bool _listEquals(List<int>? a, List<int>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}