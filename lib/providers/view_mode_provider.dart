import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';

/// 视图模式
enum ViewMode { grid, list, preview }

/// 缩略图尺寸预设
enum ThumbSize { small, medium, large }

/// 排序方式
enum SortBy { dateTaken, importedAt, rating, fileName }

/// 视图状态
class ViewModeState {
  final ViewMode mode;
  final ThumbSize thumbSize;
  final SortBy sortBy;
  final bool ascending;
  final bool leftPanelVisible;
  final bool rightPanelVisible;
  final bool filterBarVisible;

  /// 左栏宽度（可拖拽调节）
  final double leftPanelWidth;

  /// 底部胶片条高度（可拖拽调节，仅预览模式）
  final double filmstripHeight;

  /// 底部胶片条可见性（仅预览模式）
  final bool filmstripVisible;

  const ViewModeState({
    this.mode = ViewMode.grid,
    this.thumbSize = ThumbSize.medium,
    this.sortBy = SortBy.dateTaken,
    this.ascending = true,
    this.leftPanelVisible = true,
    this.rightPanelVisible = true,
    this.filterBarVisible = true,
    this.leftPanelWidth = AppConstants.leftPanelDefaultWidth,
    this.filmstripHeight = AppConstants.filmstripDefaultHeight,
    this.filmstripVisible = true,
  });

  /// 获取缩略图像素尺寸
  double get thumbPixelSize => switch (thumbSize) {
        ThumbSize.small => 120,
        ThumbSize.medium => 180,
        ThumbSize.large => 260,
      };

  ViewModeState copyWith({
    ViewMode? mode,
    ThumbSize? thumbSize,
    SortBy? sortBy,
    bool? ascending,
    bool? leftPanelVisible,
    bool? rightPanelVisible,
    bool? filterBarVisible,
    double? leftPanelWidth,
    double? filmstripHeight,
    bool? filmstripVisible,
  }) {
    return ViewModeState(
      mode: mode ?? this.mode,
      thumbSize: thumbSize ?? this.thumbSize,
      sortBy: sortBy ?? this.sortBy,
      ascending: ascending ?? this.ascending,
      leftPanelVisible: leftPanelVisible ?? this.leftPanelVisible,
      rightPanelVisible: rightPanelVisible ?? this.rightPanelVisible,
      filterBarVisible: filterBarVisible ?? this.filterBarVisible,
      leftPanelWidth: leftPanelWidth ?? this.leftPanelWidth,
      filmstripHeight: filmstripHeight ?? this.filmstripHeight,
      filmstripVisible: filmstripVisible ?? this.filmstripVisible,
    );
  }
}

/// 视图模式 Provider
class ViewModeNotifier extends StateNotifier<ViewModeState> {
  ViewModeNotifier() : super(const ViewModeState());

  void toggleViewMode() {
    final next = switch (state.mode) {
      ViewMode.grid => ViewMode.list,
      ViewMode.list => ViewMode.preview,
      ViewMode.preview => ViewMode.grid,
    };
    state = state.copyWith(mode: next);
  }

  void setViewMode(ViewMode mode) {
    state = state.copyWith(mode: mode);
  }

  void setThumbSize(ThumbSize size) {
    state = state.copyWith(thumbSize: size);
  }

  void increaseThumbSize() {
    final next = switch (state.thumbSize) {
      ThumbSize.small => ThumbSize.medium,
      ThumbSize.medium => ThumbSize.large,
      ThumbSize.large => ThumbSize.large,
    };
    state = state.copyWith(thumbSize: next);
  }

  void decreaseThumbSize() {
    final next = switch (state.thumbSize) {
      ThumbSize.small => ThumbSize.small,
      ThumbSize.medium => ThumbSize.small,
      ThumbSize.large => ThumbSize.medium,
    };
    state = state.copyWith(thumbSize: next);
  }

  void setSortBy(SortBy sortBy) {
    state = state.copyWith(sortBy: sortBy);
  }

  void toggleAscending() {
    state = state.copyWith(ascending: !state.ascending);
  }

  void toggleLeftPanel() {
    state = state.copyWith(leftPanelVisible: !state.leftPanelVisible);
  }

  void toggleRightPanel() {
    state = state.copyWith(rightPanelVisible: !state.rightPanelVisible);
  }

  void toggleFilterBar() {
    state = state.copyWith(filterBarVisible: !state.filterBarVisible);
  }

  /// 设置左栏宽度 — 限制在 min/max 范围内
  void setLeftPanelWidth(double width) {
    final clamped = width.clamp(
      AppConstants.leftPanelMinWidth,
      AppConstants.leftPanelMaxWidth,
    );
    state = state.copyWith(leftPanelWidth: clamped);
  }

  /// 设置底部胶片条高度 — 限制在 min/max 范围内
  void setFilmstripHeight(double height) {
    final clamped = height.clamp(
      AppConstants.filmstripMinHeight,
      AppConstants.filmstripMaxHeight,
    );
    state = state.copyWith(filmstripHeight: clamped);
  }

  /// 切换底部胶片条可见性
  void toggleFilmstrip() {
    state = state.copyWith(filmstripVisible: !state.filmstripVisible);
  }
}

final viewModeProvider =
    StateNotifierProvider<ViewModeNotifier, ViewModeState>((ref) {
  return ViewModeNotifier();
});