import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 照片多选状态管理。
///
/// ⚡ 性能设计：
/// - UI 组件通过 `ref.watch(selectionProvider.select((s) => s.isSelected(id)))`
///   只监听单个照片的选中状态，避免整个网格重建。
/// - Set<int> 的 contains() 是 O(1) 操作，适合高频 build 调用。
/// - toList().indexOf() 在网格项中已被替换为直接遍历 Set 查找选中序号。
///
/// 选中序号计算：
/// ```dart
/// int orderIndex(Set<int> ids, int photoId) {
///   int idx = 0;
///   for (final id in ids) {
///     if (id == photoId) return idx;
///     idx++;
///   }
///   return -1;
/// }
/// ```
class SelectionState {
  final Set<int> selectedIds;
  final int? lastSelectedId;

  const SelectionState({
    this.selectedIds = const {},
    this.lastSelectedId,
  });

  bool get hasSelection => selectedIds.isNotEmpty;
  int get count => selectedIds.length;
  bool isSelected(int id) => selectedIds.contains(id);

  SelectionState copyWith({
    Set<int>? selectedIds,
    int? lastSelectedId,
    bool clearLastSelected = false,
  }) {
    return SelectionState(
      selectedIds: selectedIds ?? this.selectedIds,
      lastSelectedId:
          clearLastSelected ? null : lastSelectedId ?? this.lastSelectedId,
    );
  }
}

/// 多选 Provider
class SelectionNotifier extends StateNotifier<SelectionState> {
  SelectionNotifier() : super(const SelectionState());

  /// 单选
  void select(int id) {
    state = SelectionState(selectedIds: {id}, lastSelectedId: id);
  }

  /// 切换选中
  void toggle(int id) {
    final newIds = Set<int>.from(state.selectedIds);
    if (newIds.contains(id)) {
      newIds.remove(id);
    } else {
      newIds.add(id);
    }
    state = state.copyWith(
      selectedIds: newIds,
      lastSelectedId: id,
    );
  }

  /// 范围选择（Shift+点击）
  void selectRange(int id, List<int> allIds) {
    if (state.lastSelectedId == null) {
      select(id);
      return;
    }

    final startIdx = allIds.indexOf(state.lastSelectedId!);
    final endIdx = allIds.indexOf(id);

    if (startIdx == -1 || endIdx == -1) {
      select(id);
      return;
    }

    final from = startIdx < endIdx ? startIdx : endIdx;
    final to = startIdx < endIdx ? endIdx : startIdx;
    final newIds = Set<int>.from(state.selectedIds);
    for (var i = from; i <= to; i++) {
      newIds.add(allIds[i]);
    }
    state = state.copyWith(selectedIds: newIds, lastSelectedId: id);
  }

  /// 全选
  void selectAll(List<int> allIds) {
    state = SelectionState(
      selectedIds: Set<int>.from(allIds),
      lastSelectedId: allIds.isEmpty ? null : allIds.last,
    );
  }

  /// 清除选择
  void clear() {
    state = const SelectionState();
  }
}

final selectionProvider =
    StateNotifierProvider<SelectionNotifier, SelectionState>((ref) {
  return SelectionNotifier();
});