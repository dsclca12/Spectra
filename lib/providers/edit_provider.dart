import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/models/edit_params.dart';
import '../data/services/auto_adjust_service.dart';
import 'providers.dart';
import 'settings_provider.dart';

/// 编辑参数 Provider — 从数据库加载指定照片的编辑参数
///
/// 返回 EditParams 对象（若无记录则返回默认值）
final editParamsProvider =
    FutureProvider.autoDispose.family<EditParams, int>((ref, photoId) async {
  final editDao = ref.watch(editDaoProvider);
  final edit = await editDao.getByPhotoId(photoId);
  if (edit == null) return EditParams.defaultParams;

  return EditParams(
    exposure: edit.exposure,
    contrast: edit.contrast,
    highlights: edit.highlights,
    shadows: edit.shadows,
    whites: edit.whites,
    blacks: edit.blacks,
    saturation: edit.saturation,
    vibrance: edit.vibrance,
    temperature: edit.temperature,
    tint: edit.tint,
    sharpness: edit.sharpness,
    vignette: edit.vignette,
    grain: edit.grain,
    fade: edit.fade,
    cropX: edit.cropX,
    cropY: edit.cropY,
    cropWidth: edit.cropWidth,
    cropHeight: edit.cropHeight,
    rotation: edit.rotation,
    flipH: edit.flipH == 1,
    flipV: edit.flipV == 1,
  );
});

/// 内存级历史条目 — 未持久化到数据库的编辑操作记录。
///
/// 在编辑时立即创建并加入 [EditSessionState.localHistory]，
/// 随后以 debounce 方式批量持久化到 [EditHistory] 表。
class EditLocalHistoryEntry {
  /// 操作后的完整 EditParams（JSON）
  final String paramsJson;

  /// 操作描述（如 "曝光 +0.5"）
  final String? actionLabel;

  /// 操作时间
  final DateTime createdAt;

  const EditLocalHistoryEntry({
    required this.paramsJson,
    this.actionLabel,
    required this.createdAt,
  });
}

/// 编辑会话状态 — 管理当前照片的实时编辑状态
///
/// 包含：
/// - 当前编辑参数（实时更新，驱动预览）
/// - 未保存标记（参数与数据库不同步时为 true）
/// - 撤销/重做历史栈（内存中，快速撤销）
/// - 持久化快照列表（数据库中，跨会话可用）
/// - 持久化操作历史列表（数据库中，可回退到任意节点）
/// - 内存级历史列表（编辑后立即创建，实时刷新 UI）
class EditSessionState {
  final EditParams params;
  final bool isDirty;
  final List<EditParams> undoStack;
  final List<EditParams> redoStack;
  final List<EditSnapshot> snapshots;
  final List<EditHistoryData> history;
  final bool isAutoAdjusting;

  /// 当前预览的历史节点 ID — 非 null 时图片预览使用该历史节点的参数
  final int? previewHistoryId;

  /// 内存级历史条目 — 编辑后立即创建，实时刷新历史面板。
  /// 持久化到 DB 后会从该列表移除。
  final List<EditLocalHistoryEntry> localHistory;

  const EditSessionState({
    this.params = EditParams.defaultParams,
    this.isDirty = false,
    this.undoStack = const [],
    this.redoStack = const [],
    this.snapshots = const [],
    this.history = const [],
    this.isAutoAdjusting = false,
    this.previewHistoryId,
    this.localHistory = const [],
  });

  /// 是否可以撤销
  bool get canUndo => undoStack.isNotEmpty;

  /// 是否可以重做
  bool get canRedo => redoStack.isNotEmpty;

  /// 获取当前预览参数 — 若 previewHistoryId 不为 null 则返回对应历史节点的参数
  /// previewHistoryId == 0 表示「初始」状态（默认参数）
  EditParams get previewParams {
    if (previewHistoryId == null) return params;
    if (previewHistoryId == 0) return EditParams.defaultParams;
    final target = history.where((h) => h.id == previewHistoryId).firstOrNull;
    if (target == null) return params;
    return EditParams.fromJson(
      jsonDecode(target.paramsJson) as Map<String, dynamic>,
    );
  }

  EditSessionState copyWith({
    EditParams? params,
    bool? isDirty,
    List<EditParams>? undoStack,
    List<EditParams>? redoStack,
    List<EditSnapshot>? snapshots,
    List<EditHistoryData>? history,
    bool? isAutoAdjusting,
    int? previewHistoryId,
    bool clearPreview = false,
    List<EditLocalHistoryEntry>? localHistory,
  }) {
    return EditSessionState(
      params: params ?? this.params,
      isDirty: isDirty ?? this.isDirty,
      undoStack: undoStack ?? this.undoStack,
      redoStack: redoStack ?? this.redoStack,
      snapshots: snapshots ?? this.snapshots,
      history: history ?? this.history,
      isAutoAdjusting: isAutoAdjusting ?? this.isAutoAdjusting,
      previewHistoryId:
          clearPreview ? null : (previewHistoryId ?? this.previewHistoryId),
      localHistory: localHistory ?? this.localHistory,
    );
  }
}

/// 编辑会话 Notifier — 管理单张照片的编辑会话
///
/// 生命周期：
/// 1. [load] — 从数据库加载编辑参数，初始化状态
/// 2. [updateParam] — 修改单个参数，推入撤销栈
/// 3. [undo] / [redo] — 撤销/重做
/// 4. [reset] — 重置为默认参数
/// 5. [save] — 持久化到数据库
///
/// 实时特性：
/// - 自动保存防抖延迟由 [AppSettingsState.editAutoSaveDebounceMs] 控制（默认 500ms）
/// - 历史记录防抖延迟由 [AppSettingsState.editHistoryDebounceMs] 控制（默认 1000ms）
/// - 编辑后立即创建内存级历史条目 [EditLocalHistoryEntry]，历史面板实时刷新
/// - 离散操作（翻转、重置、自动调整等）立即记录历史，无防抖
class EditSessionNotifier extends StateNotifier<EditSessionState> {
  final Ref _ref;
  final int _photoId;

  /// 撤销栈最大深度
  static const int _maxHistory = 50;

  /// 自动保存防抖定时器
  Timer? _autoSaveTimer;

  /// 历史记录防抖定时器（持久化用）
  Timer? _historyTimer;

  /// 内存级历史防抖定时器 — 滑块拖动时 coalesce，减少条目数
  Timer? _localHistoryTimer;



  EditSessionNotifier(this._ref, this._photoId)
      : super(const EditSessionState());

  /// 从数据库加载编辑参数、快照和历史
  Future<void> load() async {
    final editDao = _ref.read(editDaoProvider);
    final edit = await editDao.getByPhotoId(_photoId);

    EditParams params = EditParams.defaultParams;
    if (edit != null) {
      params = EditParams(
        exposure: edit.exposure,
        contrast: edit.contrast,
        highlights: edit.highlights,
        shadows: edit.shadows,
        whites: edit.whites,
        blacks: edit.blacks,
        saturation: edit.saturation,
        vibrance: edit.vibrance,
        temperature: edit.temperature,
        tint: edit.tint,
        sharpness: edit.sharpness,
        vignette: edit.vignette,
        grain: edit.grain,
        fade: edit.fade,
        cropX: edit.cropX,
        cropY: edit.cropY,
        cropWidth: edit.cropWidth,
        cropHeight: edit.cropHeight,
        rotation: edit.rotation,
        flipH: edit.flipH == 1,
        flipV: edit.flipV == 1,
      );
    }

    // 加载快照和历史
    final snapshots = await _loadSnapshots();
    final history = await _loadHistory();

    state = EditSessionState(
      params: params,
      snapshots: snapshots,
      history: history,
    );
  }

  /// 加载快照列表
  Future<List<EditSnapshot>> _loadSnapshots() async {
    final snapshotDao = _ref.read(editSnapshotDaoProvider);
    return snapshotDao.getByPhotoId(_photoId);
  }

  /// 加载历史列表
  Future<List<EditHistoryData>> _loadHistory() async {
    final historyDao = _ref.read(editHistoryDaoProvider);
    return historyDao.getByPhotoId(_photoId);
  }

  /// 更新单个参数 — 推入撤销栈，触发实时内存级历史 + 防抖持久化
  void updateParam(EditParams Function(EditParams) updater) {
    final oldParams = state.params;
    final newParams = updater(oldParams);
    if (newParams == oldParams) return;

    final undoStack = [...state.undoStack, oldParams];
    if (undoStack.length > _maxHistory) {
      undoStack.removeAt(0);
    }

    // 生成操作描述标签
    final label = EditParams.describeDifference(oldParams, newParams);

    state = state.copyWith(
      params: newParams,
      isDirty: true,
      undoStack: undoStack,
      redoStack: [], // 新操作清空重做栈
      clearPreview: true,
    );

    _scheduleAutoSave();
    // 立即调度内存级历史（300ms coalesce，滑块拖动时不频繁创建）
    _scheduleLocalHistory(state.params, label);
    // 调度 DB 持久化
    _scheduleHistoryRecord();
  }

  /// 直接替换参数（用于裁剪等批量更新，仍推入撤销栈）
  void replaceParams(EditParams newParams, {String? actionLabel}) {
    if (newParams == state.params) return;

    final oldParams = state.params;
    final undoStack = [...state.undoStack, oldParams];
    if (undoStack.length > _maxHistory) {
      undoStack.removeAt(0);
    }

    final label = actionLabel ??
        EditParams.describeDifference(oldParams, newParams);

    state = state.copyWith(
      params: newParams,
      isDirty: true,
      undoStack: undoStack,
      redoStack: [],
      clearPreview: true,
    );

    _scheduleAutoSave();
    // 离散操作立即记录内存级历史（无防抖）
    _addLocalHistory(newParams, label);
    _scheduleHistoryRecord(label: label);
  }

  /// 撤销
  void undo() {
    if (!state.canUndo) return;
    final undoStack = [...state.undoStack];
    final previous = undoStack.removeLast();
    final redoStack = [...state.redoStack, state.params];

    state = state.copyWith(
      params: previous,
      isDirty: true,
      undoStack: undoStack,
      redoStack: redoStack,
      clearPreview: true,
    );

    // 撤销也记录历史，方便查看每一步变化
    final label = EditParams.describeDifference(state.params, previous);
    _addLocalHistory(previous, '撤销: $label');
    _scheduleAutoSave();
  }

  /// 重做
  void redo() {
    if (!state.canRedo) return;
    final redoStack = [...state.redoStack];
    final next = redoStack.removeLast();
    final undoStack = [...state.undoStack, state.params];

    state = state.copyWith(
      params: next,
      isDirty: true,
      undoStack: undoStack,
      redoStack: redoStack,
      clearPreview: true,
    );

    final label = EditParams.describeDifference(state.params, next);
    _addLocalHistory(next, '重做: $label');
    _scheduleAutoSave();
  }

  /// 重置为默认参数
  void reset() {
    if (state.params == EditParams.defaultParams) return;

    final oldParams = state.params;
    final undoStack = [...state.undoStack, oldParams];
    state = state.copyWith(
      params: EditParams.defaultParams,
      isDirty: true,
      undoStack: undoStack,
      redoStack: [],
      clearPreview: true,
    );

    _scheduleAutoSave();
    _addLocalHistory(EditParams.defaultParams, '重置');
    _scheduleHistoryRecord(label: '重置');
  }

  /// 保存到数据库
  Future<void> save() async {
    if (!state.isDirty) return;

    final editDao = _ref.read(editDaoProvider);
    final p = state.params;

    await editDao.upsert(PhotoEditsCompanion.insert(
      photoId: Value(_photoId),
      exposure: Value(p.exposure),
      contrast: Value(p.contrast),
      highlights: Value(p.highlights),
      shadows: Value(p.shadows),
      whites: Value(p.whites),
      blacks: Value(p.blacks),
      saturation: Value(p.saturation),
      vibrance: Value(p.vibrance),
      temperature: Value(p.temperature),
      tint: Value(p.tint),
      sharpness: Value(p.sharpness),
      vignette: Value(p.vignette),
      grain: Value(p.grain),
      fade: Value(p.fade),
      cropX: Value(p.cropX),
      cropY: Value(p.cropY),
      cropWidth: Value(p.cropWidth),
      cropHeight: Value(p.cropHeight),
      rotation: Value(p.rotation),
      flipH: Value(p.flipH ? 1 : 0),
      flipV: Value(p.flipV ? 1 : 0),
      updatedAt: Value(DateTime.now()),
    ));

    // 刷新 FutureProvider 缓存
    _ref.invalidate(editParamsProvider(_photoId));

    state = state.copyWith(isDirty: false);
  }

  /// 从数据库删除编辑参数（完全重置）
  Future<void> deleteEdits() async {
    final editDao = _ref.read(editDaoProvider);
    await editDao.deleteByPhotoId(_photoId);
    _ref.invalidate(editParamsProvider(_photoId));

    final undoStack = [...state.undoStack, state.params];
    state = state.copyWith(
      params: EditParams.defaultParams,
      isDirty: false,
      undoStack: undoStack,
      redoStack: [],
    );
  }

  // ─── 自动保存 ───

  /// 防抖自动保存 — 编辑后延迟 N 毫秒自动保存。
  /// 默认延迟 500ms（由 [AppSettingsState.editAutoSaveDebounceMs] 控制）。
  void _scheduleAutoSave() {
    try {
      final settings = _ref.read(settingsProvider);
      if (!settings.editAutoSave) return;

      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer(
        Duration(milliseconds: settings.editAutoSaveDebounceMs),
        () => _autoSave(),
      );
    } catch (_) {
      // settingsProvider 可能未初始化，忽略
    }
  }

  /// 执行自动保存
  Future<void> _autoSave() async {
    if (!state.isDirty) return;
    await save();
  }

  /// 切换照片时调用 — 立即保存
  Future<void> saveOnSwitch() async {
    try {
      final settings = _ref.read(settingsProvider);
      if (settings.editAutoSaveOnSwitch && state.isDirty) {
        _autoSaveTimer?.cancel();
        await save();
      }
    } catch (_) {
      // settingsProvider 可能未初始化，忽略
    }
  }

  /// 关闭查看器时调用 — 立即保存
  Future<void> saveOnClose() async {
    try {
      final settings = _ref.read(settingsProvider);
      if (settings.editAutoSaveOnClose && state.isDirty) {
        _autoSaveTimer?.cancel();
        await save();
      }
    } catch (_) {
      // settingsProvider 可能未初始化，忽略
    }
  }

  // ─── 编辑历史 ───

  /// 调度内存级历史条目 — 防抖 coalesce 滑块连续拖动。
  /// 用户连续拖动滑块时，只记录最后一次停止后的状态。
  /// 默认 300ms 防抖，适合滑块操作的实时反馈。
  void _scheduleLocalHistory(EditParams params, String label) {
    _localHistoryTimer?.cancel();
    _localHistoryTimer = Timer(
      const Duration(milliseconds: 300),
      () => _addLocalHistory(params, label),
    );
  }

  /// 立即添加内存级历史条目 — 更新 state 触发 UI 实时刷新。
  /// 同时调度持久化，确保条目最终写入数据库。
  void _addLocalHistory(EditParams params, String? label) {
    final entry = EditLocalHistoryEntry(
      paramsJson: jsonEncode(params.toJson()),
      actionLabel: label,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      localHistory: [...state.localHistory, entry],
    );
    // 立即调度持久化（防抖），确保本地条目最终写入 DB。
    // 这解决了 _scheduleHistoryRecord 的防抖周期可能短于
    // _scheduleLocalHistory 时，持久化在本地条目创建前
    // 就触发并提前退出的问题。
    _schedulePersistLocalHistory();
  }

  /// 防抖调度本地历史持久化 — 编辑后延迟 N 毫秒写入数据库。
  /// 默认延迟 1000ms（由 [AppSettingsState.editHistoryDebounceMs] 控制）。
  void _schedulePersistLocalHistory() {
    try {
      final settings = _ref.read(settingsProvider);
      if (!settings.editHistoryEnabled) return;

      _historyTimer?.cancel();
      _historyTimer = Timer(
        Duration(milliseconds: settings.editHistoryDebounceMs),
        () => _persistLocalHistory(),
      );
    } catch (_) {
      // settingsProvider 可能未初始化，忽略
    }
  }

  /// 防抖历史记录（保留旧接口，转发到本地历史持久化）
  void _scheduleHistoryRecord({String? label}) {
    _schedulePersistLocalHistory();
  }

  /// 持久化内存级历史到数据库
  Future<void> _persistLocalHistory() async {
    if (state.localHistory.isEmpty) return;

    try {
      final historyDao = _ref.read(editHistoryDaoProvider);
      final settings = _ref.read(settingsProvider);

      // 批量写入所有未持久化的本地历史条目
      for (final entry in state.localHistory) {
        await historyDao.add(EditHistoryCompanion.insert(
          photoId: _photoId,
          paramsJson: entry.paramsJson,
          actionLabel: Value(entry.actionLabel),
          createdAt: entry.createdAt,
        ));
      }

      // 清理超出上限的旧记录
      await historyDao.pruneHistory(_photoId, settings.editHistoryMaxCount);

      // 从数据库重新加载完整历史列表
      final history = await _loadHistory();
      if (mounted) {
        // 清空本地历史，刷新为 DB 数据
        state = state.copyWith(
          history: history,
          localHistory: const [],
        );
      }
    } catch (_) {
      // 忽略历史记录失败 — 保留本地条目，下次重试
    }
  }

  /// 预览历史节点 — 仅更新预览参数，不修改实际编辑状态
  /// [historyId] 为 0 时表示预览「初始」状态（默认参数）
  void previewHistory(int? historyId) {
    if (historyId == state.previewHistoryId) return;
    state = state.copyWith(previewHistoryId: historyId);
  }

  /// 清除历史预览 — 恢复显示当前编辑参数
  void clearPreview() {
    if (state.previewHistoryId == null) return;
    state = state.copyWith(clearPreview: true);
  }

  /// 跳转到历史节点 — 加载该节点的参数并提交
  /// [historyId] 为 0 时表示恢复到「初始」状态（默认参数）
  Future<void> restoreHistory(int historyId) async {
    EditParams params;
    if (historyId == 0) {
      params = EditParams.defaultParams;
    } else {
      final target = state.history.where((h) => h.id == historyId).firstOrNull;
      if (target == null) return;
      params = EditParams.fromJson(
        jsonDecode(target.paramsJson) as Map<String, dynamic>,
      );
    }

    final undoStack = [...state.undoStack, state.params];
    final oldParams = state.params;
    state = state.copyWith(
      params: params,
      isDirty: true,
      undoStack: undoStack,
      redoStack: [],
      clearPreview: true,
    );

    final label = EditParams.describeDifference(oldParams, params);
    _addLocalHistory(params, '恢复: $label');
    _scheduleAutoSave();
  }

  /// 清空历史（保留快照）
  Future<void> clearHistory() async {
    final historyDao = _ref.read(editHistoryDaoProvider);
    await historyDao.deleteByPhotoId(_photoId);
    state = state.copyWith(
      history: const [],
      localHistory: const [],
    );
  }

  // ─── 编辑快照 ───

  /// 创建快照
  Future<void> createSnapshot(String name) async {
    final snapshotDao = _ref.read(editSnapshotDaoProvider);
    await snapshotDao.create(EditSnapshotsCompanion.insert(
      photoId: _photoId,
      name: name,
      paramsJson: jsonEncode(state.params.toJson()),
      isAuto: const Value(false),
      createdAt: DateTime.now(),
    ));

    // 刷新快照列表
    final snapshots = await _loadSnapshots();
    state = state.copyWith(snapshots: snapshots);

    _addLocalHistory(state.params, '创建快照: $name');
  }

  /// 删除快照
  Future<void> deleteSnapshot(int snapshotId) async {
    final snapshotDao = _ref.read(editSnapshotDaoProvider);
    await snapshotDao.deleteById(snapshotId);

    final snapshots = await _loadSnapshots();
    state = state.copyWith(snapshots: snapshots);
  }

  /// 重命名快照
  Future<void> renameSnapshot(int snapshotId, String newName) async {
    final snapshotDao = _ref.read(editSnapshotDaoProvider);
    await snapshotDao.rename(snapshotId, newName);

    final snapshots = await _loadSnapshots();
    state = state.copyWith(snapshots: snapshots);
  }

  /// 恢复到快照 — 加载快照参数到当前编辑会话
  Future<void> restoreSnapshot(int snapshotId) async {
    final target = state.snapshots.where((s) => s.id == snapshotId).firstOrNull;
    if (target == null) return;

    final params = EditParams.fromJson(
      jsonDecode(target.paramsJson) as Map<String, dynamic>,
    );

    final undoStack = [...state.undoStack, state.params];
    final oldParams = state.params;
    state = state.copyWith(
      params: params,
      isDirty: true,
      undoStack: undoStack,
      redoStack: [],
      clearPreview: true,
    );

    final label = EditParams.describeDifference(oldParams, params);
    _addLocalHistory(params, '恢复快照: $label');
    _scheduleAutoSave();
  }

  // ─── 自动调整 ───

  /// 执行自动调整
  ///
  /// 根据设置中的 `editAutoAdjustEngine` 选择引擎：
  /// - neural：神经网络驱动（IAT 模型）
  /// - heuristic：直方图启发式
  /// - auto：优先神经，回退启发式
  Future<void> autoAdjust(String imagePath) async {
    state = state.copyWith(isAutoAdjusting: true);

    try {
      final autoAdjustService = _ref.read(autoAdjustServiceProvider);
      final settings = _ref.read(settingsProvider);

      // 解析引擎设置
      final engine = switch (settings.editAutoAdjustEngine) {
        'neural' => AutoAdjustEngine.neural,
        'heuristic' => AutoAdjustEngine.heuristic,
        _ => AutoAdjustEngine.auto,
      };

      final autoParams = await autoAdjustService.analyze(
        imagePath,
        preserveUserEdits: settings.editAutoAdjustPreserve,
        currentParams: state.params,
        engine: engine,
        strength: settings.editNeuralEnhanceStrength,
      );

      if (!mounted) return;

      // 推入撤销栈
      final undoStack = [...state.undoStack, state.params];
      if (undoStack.length > _maxHistory) {
        undoStack.removeAt(0);
      }

      state = state.copyWith(
        params: autoParams,
        isDirty: true,
        undoStack: undoStack,
        redoStack: [],
        isAutoAdjusting: false,
        clearPreview: true,
      );

      _addLocalHistory(autoParams, '自动调整');
      _scheduleAutoSave();
      _scheduleHistoryRecord(label: '自动调整');
    } catch (_) {
      if (mounted) {
        state = state.copyWith(isAutoAdjusting: false);
      }
    }
  }

  // ─── 超分辨率 ───

  /// 对当前照片执行超分辨率放大
  ///
  /// [inputPath] 原始图片路径
  /// [outputPath] 输出路径
  /// 返回输出路径表示成功，null 表示失败。
  Future<String?> superResolve(
    String inputPath, {
    required String outputPath,
    int quality = 95,
  }) async {
    final srService = _ref.read(superResolutionServiceProvider);
    return srService.upscale(
      inputPath,
      outputPath: outputPath,
      quality: quality,
    );
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _historyTimer?.cancel();
    _localHistoryTimer?.cancel();
    super.dispose();
  }
}

/// 编辑会话 Provider — 按 photoId 创建
final editSessionProvider = StateNotifierProvider.autoDispose
    .family<EditSessionNotifier, EditSessionState, int>(
  (ref, photoId) => EditSessionNotifier(ref, photoId),
);