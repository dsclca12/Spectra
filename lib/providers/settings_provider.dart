import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/daos/settings_dao.dart';
import 'providers.dart';

// ─── 设置键名常量 ───

class SettingKeys {
  SettingKeys._();

  // 外观
  static const themeMode = 'appearance.themeMode'; // dark / light / system
  static const accentColor = 'appearance.accentColor';
  static const leftPanelWidth = 'appearance.leftPanelWidth';
  static const rightPanelWidth = 'appearance.rightPanelWidth';

  // 缩略图与画质
  static const thumbnailSmallSize = 'thumbnail.smallSize';
  static const thumbnailMediumSize = 'thumbnail.mediumSize';
  static const thumbnailCacheLimit = 'thumbnail.cacheLimitMB';
  static const thumbnailConcurrency = 'thumbnail.concurrency';
  static const previewMaxSize = 'thumbnail.previewMaxSize';
  static const gridCacheExtent = 'thumbnail.gridCacheExtent';

  // 导入
  static const importExifConcurrency = 'import.exifConcurrency';
  static const importThumbnailConcurrency = 'import.thumbnailConcurrency';
  static const importAutoGenerateThumbs = 'import.autoGenerateThumbs';
  static const importWatchFolders = 'import.watchFolders';
  static const maxFileSizeMB = 'import.maxFileSizeMB';

  // 搜索
  static const searchDebounceMs = 'search.debounceMs';
  static const searchScopeFileName = 'search.scopeFileName';
  static const searchScopeTitle = 'search.scopeTitle';
  static const searchScopeDescription = 'search.scopeDescription';
  static const searchScopeCamera = 'search.scopeCamera';
  static const searchScopeKeywords = 'search.scopeKeywords';

  // 浏览
  static const defaultViewMode = 'browse.defaultViewMode'; // grid / list
  static const defaultThumbSize = 'browse.defaultThumbSize'; // small / medium / large
  static const defaultSortBy = 'browse.defaultSortBy';
  static const defaultAscending = 'browse.defaultAscending';

  // 性能
  static const imageCacheMaxCount = 'performance.imageCacheMaxCount';
  static const imageCacheMaxSizeMB = 'performance.imageCacheMaxSizeMB';
  static const pageSize = 'performance.pageSize';

  // 快捷键（用户可自定义映射）
  static const shortcutRate0 = 'shortcut.rate0';
  static const shortcutRate1 = 'shortcut.rate1';
  static const shortcutRate2 = 'shortcut.rate2';
  static const shortcutRate3 = 'shortcut.rate3';
  static const shortcutRate4 = 'shortcut.rate4';
  static const shortcutRate5 = 'shortcut.rate5';
  static const shortcutPick = 'shortcut.pick';
  static const shortcutUnpick = 'shortcut.unpick';
  static const shortcutReject = 'shortcut.reject';
  static const shortcutColor1 = 'shortcut.color1';
  static const shortcutColor2 = 'shortcut.color2';
  static const shortcutColor3 = 'shortcut.color3';
  static const shortcutColor4 = 'shortcut.color4';
  static const shortcutColor5 = 'shortcut.color5';
  static const shortcutColor6 = 'shortcut.color6';
  static const shortcutClearColor = 'shortcut.clearColor';
  static const shortcutFullscreen = 'shortcut.fullscreen';
  static const shortcutImport = 'shortcut.import';
  static const shortcutSearch = 'shortcut.search';
  static const shortcutToggleView = 'shortcut.toggleView';
  static const shortcutSelectAll = 'shortcut.selectAll';
  static const shortcutDeselect = 'shortcut.deselect';
  static const shortcutToggleLeftPanel = 'shortcut.toggleLeftPanel';
  static const shortcutToggleRightPanel = 'shortcut.toggleRightPanel';
  static const shortcutToggleFilterBar = 'shortcut.toggleFilterBar';

  // 编辑
  static const editAutoSave = 'edit.autoSave'; // 自动保存总开关
  static const editAutoSaveDebounceMs = 'edit.autoSaveDebounce'; // 防抖延迟
  static const editAutoSaveOnSwitch = 'edit.autoSaveOnSwitch'; // 切换照片时保存
  static const editAutoSaveOnClose = 'edit.autoSaveOnClose'; // 关闭查看器时保存
  static const editHistoryEnabled = 'edit.historyEnabled'; // 操作历史开关
  static const editHistoryMaxCount = 'edit.historyMaxCount'; // 历史上限
  static const editAutoAdjustPreserve = 'edit.autoAdjustPreserve'; // 自动调整保留用户已调参数
  static const editAutoAdjustEngine = 'edit.autoAdjustEngine'; // 自动调整引擎
  static const editNeuralEnhanceStrength = 'edit.neuralEnhanceStrength'; // 神经增强强度
  static const editSuperResolutionEnabled = 'edit.superResolutionEnabled'; // 超分辨率开关
  static const editHistoryDebounceMs = 'edit.historyDebounceMs'; // 历史记录防抖延迟(毫秒)

  // 自动调整与模型
  static const aiModelPath = 'ai.modelPath';           // 模型文件路径
  static const aiAutoLoadModel = 'ai.autoLoadModel';   // 启动时自动加载模型
  static const aiAnalysisSize = 'ai.analysisSize';     // 自动调整分析尺寸
}

/// 应用设置状态 — 持久化到数据库 AppSettings 表。
///
/// 所有字段都有默认值，首次启动时自动初始化。
/// 用户通过设置界面修改后，自动保存到数据库。
///
/// ⚡ 性能设计：
/// - 设置值在内存中缓存，不每次读取数据库。
/// - 通过 StateNotifier 管理，修改后自动通知监听者。
/// - 默认值在 AppSettingsState 构造函数中定义，
///   数据库中没有对应键值时使用默认值。
class AppSettingsState {
  // 外观
  final String themeMode; // dark / light / system
  final String accentColor;
  final double leftPanelWidth;
  final double rightPanelWidth;

  // 缩略图与画质
  final int thumbnailSmallSize;
  final int thumbnailMediumSize;
  final int thumbnailCacheLimitMB;
  final int thumbnailConcurrency;
  final int previewMaxSize;
  final int gridCacheExtent;

  // 导入
  final int importExifConcurrency;
  final int importThumbnailConcurrency;
  final bool importAutoGenerateThumbs;
  final bool importWatchFolders;
  final int maxFileSizeMB;

  // 搜索
  final int searchDebounceMs;
  final bool searchScopeFileName;
  final bool searchScopeTitle;
  final bool searchScopeDescription;
  final bool searchScopeCamera;
  final bool searchScopeKeywords;

  // 浏览
  final String defaultViewMode;
  final String defaultThumbSize;
  final String defaultSortBy;
  final bool defaultAscending;

  // 性能
  final int imageCacheMaxCount;
  final int imageCacheMaxSizeMB;
  final int pageSize;

  // 快捷键
  final Map<String, String> shortcuts;

  // 编辑
  final bool editAutoSave;
  final int editAutoSaveDebounceMs;
  final bool editAutoSaveOnSwitch;
  final bool editAutoSaveOnClose;
  final bool editHistoryEnabled;
  final int editHistoryMaxCount;
  final bool editAutoAdjustPreserve;

  /// 自动调整引擎：neural / heuristic / auto
  final String editAutoAdjustEngine;

  /// 神经增强强度 (0.0-1.0)
  final double editNeuralEnhanceStrength;

  /// 超分辨率功能开关
  final bool editSuperResolutionEnabled;

  /// 历史记录防抖延迟（毫秒），默认 1000ms
  final int editHistoryDebounceMs;

  // AI 与模型
  /// ONNX 模型文件路径（空字符串 = 未设置）
  final String aiModelPath;

  /// 启动时自动加载模型
  final bool aiAutoLoadModel;

  /// 自动调整分析尺寸（长边像素），默认 256
  final int aiAnalysisSize;

  const AppSettingsState({
    this.themeMode = 'dark',
    this.accentColor = '#0078D4',
    this.leftPanelWidth = 200,
    this.rightPanelWidth = 280,
    this.thumbnailSmallSize = 128,
    this.thumbnailMediumSize = 512,
    this.thumbnailCacheLimitMB = 5120,
    this.thumbnailConcurrency = 4,
    this.previewMaxSize = 1024,
    this.gridCacheExtent = 500,
    this.importExifConcurrency = 2,
    this.importThumbnailConcurrency = 2,
    this.importAutoGenerateThumbs = false,
    this.importWatchFolders = true,
    this.maxFileSizeMB = 500,
    this.searchDebounceMs = 300,
    this.searchScopeFileName = true,
    this.searchScopeTitle = true,
    this.searchScopeDescription = true,
    this.searchScopeCamera = true,
    this.searchScopeKeywords = true,
    this.defaultViewMode = 'grid',
    this.defaultThumbSize = 'medium',
    this.defaultSortBy = 'dateTaken',
    this.defaultAscending = true,
    this.imageCacheMaxCount = 2000,
    this.imageCacheMaxSizeMB = 500,
    this.pageSize = 200,
    this.shortcuts = _defaultShortcuts,
    this.editAutoSave = true,
    this.editAutoSaveDebounceMs = 500,
    this.editAutoSaveOnSwitch = true,
    this.editAutoSaveOnClose = true,
    this.editHistoryEnabled = true,
    this.editHistoryMaxCount = 200,
    this.editAutoAdjustPreserve = true,
    this.editAutoAdjustEngine = 'auto',
    this.editNeuralEnhanceStrength = 1.0,
    this.editSuperResolutionEnabled = false,
    this.editHistoryDebounceMs = 1000,
    this.aiModelPath = '',
    this.aiAutoLoadModel = true,
    this.aiAnalysisSize = 256,
  });

  /// 默认快捷键映射
  static const Map<String, String> _defaultShortcuts = {
    SettingKeys.shortcutRate0: '0',
    SettingKeys.shortcutRate1: '1',
    SettingKeys.shortcutRate2: '2',
    SettingKeys.shortcutRate3: '3',
    SettingKeys.shortcutRate4: '4',
    SettingKeys.shortcutRate5: '5',
    SettingKeys.shortcutPick: 'P',
    SettingKeys.shortcutUnpick: 'U',
    SettingKeys.shortcutReject: 'X',
    SettingKeys.shortcutColor1: 'F1',
    SettingKeys.shortcutColor2: 'F2',
    SettingKeys.shortcutColor3: 'F3',
    SettingKeys.shortcutColor4: 'F4',
    SettingKeys.shortcutColor5: 'F5',
    SettingKeys.shortcutColor6: 'F6',
    SettingKeys.shortcutClearColor: 'F7',
    SettingKeys.shortcutFullscreen: 'F',
    SettingKeys.shortcutImport: 'Ctrl+I',
    SettingKeys.shortcutSearch: 'Ctrl+F',
    SettingKeys.shortcutToggleView: 'G',
    SettingKeys.shortcutSelectAll: 'Ctrl+A',
    SettingKeys.shortcutDeselect: 'Esc',
    SettingKeys.shortcutToggleLeftPanel: 'Ctrl+B',
    SettingKeys.shortcutToggleRightPanel: 'Ctrl+Shift+I',
    SettingKeys.shortcutToggleFilterBar: 'Ctrl+H',
  };

  AppSettingsState copyWith({
    String? themeMode,
    String? accentColor,
    double? leftPanelWidth,
    double? rightPanelWidth,
    int? thumbnailSmallSize,
    int? thumbnailMediumSize,
    int? thumbnailCacheLimitMB,
    int? thumbnailConcurrency,
    int? previewMaxSize,
    int? gridCacheExtent,
    int? importExifConcurrency,
    int? importThumbnailConcurrency,
    bool? importAutoGenerateThumbs,
    bool? importWatchFolders,
    int? maxFileSizeMB,
    int? searchDebounceMs,
    bool? searchScopeFileName,
    bool? searchScopeTitle,
    bool? searchScopeDescription,
    bool? searchScopeCamera,
    bool? searchScopeKeywords,
    String? defaultViewMode,
    String? defaultThumbSize,
    String? defaultSortBy,
    bool? defaultAscending,
    int? imageCacheMaxCount,
    int? imageCacheMaxSizeMB,
    int? pageSize,
    Map<String, String>? shortcuts,
    bool? editAutoSave,
    int? editAutoSaveDebounceMs,
    bool? editAutoSaveOnSwitch,
    bool? editAutoSaveOnClose,
    bool? editHistoryEnabled,
    int? editHistoryMaxCount,
    bool? editAutoAdjustPreserve,
    String? editAutoAdjustEngine,
    double? editNeuralEnhanceStrength,
    bool? editSuperResolutionEnabled,
    int? editHistoryDebounceMs,
    String? aiModelPath,
    bool? aiAutoLoadModel,
    int? aiAnalysisSize,
  }) {
    return AppSettingsState(
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
      leftPanelWidth: leftPanelWidth ?? this.leftPanelWidth,
      rightPanelWidth: rightPanelWidth ?? this.rightPanelWidth,
      thumbnailSmallSize: thumbnailSmallSize ?? this.thumbnailSmallSize,
      thumbnailMediumSize: thumbnailMediumSize ?? this.thumbnailMediumSize,
      thumbnailCacheLimitMB:
          thumbnailCacheLimitMB ?? this.thumbnailCacheLimitMB,
      thumbnailConcurrency:
          thumbnailConcurrency ?? this.thumbnailConcurrency,
      previewMaxSize: previewMaxSize ?? this.previewMaxSize,
      gridCacheExtent: gridCacheExtent ?? this.gridCacheExtent,
      importExifConcurrency:
          importExifConcurrency ?? this.importExifConcurrency,
      importThumbnailConcurrency:
          importThumbnailConcurrency ?? this.importThumbnailConcurrency,
      importAutoGenerateThumbs:
          importAutoGenerateThumbs ?? this.importAutoGenerateThumbs,
      importWatchFolders: importWatchFolders ?? this.importWatchFolders,
      maxFileSizeMB: maxFileSizeMB ?? this.maxFileSizeMB,
      searchDebounceMs: searchDebounceMs ?? this.searchDebounceMs,
      searchScopeFileName: searchScopeFileName ?? this.searchScopeFileName,
      searchScopeTitle: searchScopeTitle ?? this.searchScopeTitle,
      searchScopeDescription:
          searchScopeDescription ?? this.searchScopeDescription,
      searchScopeCamera: searchScopeCamera ?? this.searchScopeCamera,
      searchScopeKeywords: searchScopeKeywords ?? this.searchScopeKeywords,
      defaultViewMode: defaultViewMode ?? this.defaultViewMode,
      defaultThumbSize: defaultThumbSize ?? this.defaultThumbSize,
      defaultSortBy: defaultSortBy ?? this.defaultSortBy,
      defaultAscending: defaultAscending ?? this.defaultAscending,
      imageCacheMaxCount: imageCacheMaxCount ?? this.imageCacheMaxCount,
      imageCacheMaxSizeMB: imageCacheMaxSizeMB ?? this.imageCacheMaxSizeMB,
      pageSize: pageSize ?? this.pageSize,
      shortcuts: shortcuts ?? this.shortcuts,
      editAutoSave: editAutoSave ?? this.editAutoSave,
      editAutoSaveDebounceMs:
          editAutoSaveDebounceMs ?? this.editAutoSaveDebounceMs,
      editAutoSaveOnSwitch: editAutoSaveOnSwitch ?? this.editAutoSaveOnSwitch,
      editAutoSaveOnClose: editAutoSaveOnClose ?? this.editAutoSaveOnClose,
      editHistoryEnabled: editHistoryEnabled ?? this.editHistoryEnabled,
      editHistoryMaxCount: editHistoryMaxCount ?? this.editHistoryMaxCount,
      editAutoAdjustPreserve:
          editAutoAdjustPreserve ?? this.editAutoAdjustPreserve,
      editAutoAdjustEngine:
          editAutoAdjustEngine ?? this.editAutoAdjustEngine,
      editNeuralEnhanceStrength:
          editNeuralEnhanceStrength ?? this.editNeuralEnhanceStrength,
      editSuperResolutionEnabled:
          editSuperResolutionEnabled ?? this.editSuperResolutionEnabled,
      editHistoryDebounceMs:
          editHistoryDebounceMs ?? this.editHistoryDebounceMs,
      aiModelPath: aiModelPath ?? this.aiModelPath,
      aiAutoLoadModel: aiAutoLoadModel ?? this.aiAutoLoadModel,
      aiAnalysisSize: aiAnalysisSize ?? this.aiAnalysisSize,
    );
  }
}

/// 设置 Notifier — 从数据库加载/保存设置
class SettingsNotifier extends StateNotifier<AppSettingsState> {
  final SettingsDao _dao;

  SettingsNotifier(this._dao) : super(const AppSettingsState()) {
    _load();
  }

  /// 从数据库加载所有设置
  Future<void> _load() async {
    final all = await _dao.getAll();
    state = _fromMap(all);
  }

  /// 从键值映射构建设置状态
  AppSettingsState _fromMap(Map<String, String> map) {
    int? getInt(String k) => map[k] != null ? int.tryParse(map[k]!) : null;
    double? getDouble(String k) =>
        map[k] != null ? double.tryParse(map[k]!) : null;
    bool? getBool(String k) =>
        map[k] != null ? map[k] == 'true' : null;

    // 快捷键
    final shortcuts = Map<String, String>.from(AppSettingsState._defaultShortcuts);
    for (final key in AppSettingsState._defaultShortcuts.keys) {
      if (map.containsKey(key)) shortcuts[key] = map[key]!;
    }

    return AppSettingsState(
      themeMode: map[SettingKeys.themeMode] ?? 'dark',
      accentColor: map[SettingKeys.accentColor] ?? '#0078D4',
      leftPanelWidth: getDouble(SettingKeys.leftPanelWidth) ?? 200,
      rightPanelWidth: getDouble(SettingKeys.rightPanelWidth) ?? 280,
      thumbnailSmallSize: getInt(SettingKeys.thumbnailSmallSize) ?? 128,
      thumbnailMediumSize: getInt(SettingKeys.thumbnailMediumSize) ?? 512,
      thumbnailCacheLimitMB:
          getInt(SettingKeys.thumbnailCacheLimit) ?? 5120,
      thumbnailConcurrency: getInt(SettingKeys.thumbnailConcurrency) ?? 4,
      previewMaxSize: getInt(SettingKeys.previewMaxSize) ?? 1024,
      gridCacheExtent: getInt(SettingKeys.gridCacheExtent) ?? 500,
      importExifConcurrency: getInt(SettingKeys.importExifConcurrency) ?? 2,
      importThumbnailConcurrency:
          getInt(SettingKeys.importThumbnailConcurrency) ?? 2,
      importAutoGenerateThumbs:
          getBool(SettingKeys.importAutoGenerateThumbs) ?? false,
      importWatchFolders: getBool(SettingKeys.importWatchFolders) ?? true,
      maxFileSizeMB: getInt(SettingKeys.maxFileSizeMB) ?? 500,
      searchDebounceMs: getInt(SettingKeys.searchDebounceMs) ?? 300,
      searchScopeFileName: getBool(SettingKeys.searchScopeFileName) ?? true,
      searchScopeTitle: getBool(SettingKeys.searchScopeTitle) ?? true,
      searchScopeDescription:
          getBool(SettingKeys.searchScopeDescription) ?? true,
      searchScopeCamera: getBool(SettingKeys.searchScopeCamera) ?? true,
      searchScopeKeywords: getBool(SettingKeys.searchScopeKeywords) ?? true,
      defaultViewMode: map[SettingKeys.defaultViewMode] ?? 'grid',
      defaultThumbSize: map[SettingKeys.defaultThumbSize] ?? 'medium',
      defaultSortBy: map[SettingKeys.defaultSortBy] ?? 'dateTaken',
      defaultAscending: getBool(SettingKeys.defaultAscending) ?? true,
      imageCacheMaxCount: getInt(SettingKeys.imageCacheMaxCount) ?? 2000,
      imageCacheMaxSizeMB: getInt(SettingKeys.imageCacheMaxSizeMB) ?? 500,
      pageSize: getInt(SettingKeys.pageSize) ?? 200,
      shortcuts: shortcuts,
      editAutoSave: getBool(SettingKeys.editAutoSave) ?? true,
      editAutoSaveDebounceMs:
          getInt(SettingKeys.editAutoSaveDebounceMs) ?? 500,
      editAutoSaveOnSwitch: getBool(SettingKeys.editAutoSaveOnSwitch) ?? true,
      editAutoSaveOnClose: getBool(SettingKeys.editAutoSaveOnClose) ?? true,
      editHistoryEnabled: getBool(SettingKeys.editHistoryEnabled) ?? true,
      editHistoryMaxCount: getInt(SettingKeys.editHistoryMaxCount) ?? 200,
      editAutoAdjustPreserve:
          getBool(SettingKeys.editAutoAdjustPreserve) ?? true,
      editAutoAdjustEngine:
          map[SettingKeys.editAutoAdjustEngine] ?? 'auto',
      editNeuralEnhanceStrength:
          getDouble(SettingKeys.editNeuralEnhanceStrength) ?? 1.0,
      editSuperResolutionEnabled:
          getBool(SettingKeys.editSuperResolutionEnabled) ?? false,
      editHistoryDebounceMs:
          getInt(SettingKeys.editHistoryDebounceMs) ?? 1000,
      aiModelPath: map[SettingKeys.aiModelPath] ?? '',
      aiAutoLoadModel: getBool(SettingKeys.aiAutoLoadModel) ?? true,
      aiAnalysisSize: getInt(SettingKeys.aiAnalysisSize) ?? 256,
    );
  }

  /// 更新单个设置项并持久化
  Future<void> update(String key, dynamic value, {String? group}) async {
    final strValue = value is bool
        ? (value ? 'true' : 'false')
        : value.toString();

    await _dao.set(key, strValue, group: group);

    // 更新内存状态
    state = _applyUpdate(state, key, value);
  }

  /// 更新快捷键映射
  Future<void> updateShortcut(String key, String value) async {
    await _dao.set(key, value, group: 'shortcut');
    final shortcuts = Map<String, String>.from(state.shortcuts);
    shortcuts[key] = value;
    state = state.copyWith(shortcuts: shortcuts);
  }

  /// 重置所有设置到默认值
  Future<void> resetAll() async {
    for (final key in AppSettingsState._defaultShortcuts.keys) {
      await _dao.deleteSetting(key);
    }
    // 删除其他设置键
    for (final key in [
      SettingKeys.themeMode, SettingKeys.accentColor,
      SettingKeys.leftPanelWidth, SettingKeys.rightPanelWidth,
      SettingKeys.thumbnailSmallSize, SettingKeys.thumbnailMediumSize,
      SettingKeys.thumbnailCacheLimit, SettingKeys.thumbnailConcurrency,
      SettingKeys.previewMaxSize, SettingKeys.gridCacheExtent,
      SettingKeys.importExifConcurrency, SettingKeys.importThumbnailConcurrency,
      SettingKeys.importAutoGenerateThumbs, SettingKeys.importWatchFolders,
      SettingKeys.maxFileSizeMB, SettingKeys.searchDebounceMs,
      SettingKeys.searchScopeFileName, SettingKeys.searchScopeTitle,
      SettingKeys.searchScopeDescription, SettingKeys.searchScopeCamera,
      SettingKeys.searchScopeKeywords, SettingKeys.defaultViewMode,
      SettingKeys.defaultThumbSize, SettingKeys.defaultSortBy,
      SettingKeys.defaultAscending, SettingKeys.imageCacheMaxCount,
      SettingKeys.imageCacheMaxSizeMB, SettingKeys.pageSize,
      SettingKeys.editAutoSave, SettingKeys.editAutoSaveDebounceMs,
      SettingKeys.editAutoSaveOnSwitch, SettingKeys.editAutoSaveOnClose,
      SettingKeys.editHistoryEnabled, SettingKeys.editHistoryMaxCount,
      SettingKeys.editAutoAdjustPreserve,
      SettingKeys.editAutoAdjustEngine,
      SettingKeys.editNeuralEnhanceStrength,
      SettingKeys.editSuperResolutionEnabled,
      SettingKeys.editHistoryDebounceMs,
      SettingKeys.aiModelPath,
      SettingKeys.aiAutoLoadModel,
      SettingKeys.aiAnalysisSize,
    ]) {
      await _dao.deleteSetting(key);
    }
    state = const AppSettingsState();
  }

  /// 将单个键值应用到状态
  AppSettingsState _applyUpdate(
    AppSettingsState current,
    String key,
    dynamic value,
  ) {
    return switch (key) {
      SettingKeys.themeMode => current.copyWith(themeMode: value as String),
      SettingKeys.accentColor =>
        current.copyWith(accentColor: value as String),
      SettingKeys.leftPanelWidth =>
        current.copyWith(leftPanelWidth: (value as num).toDouble()),
      SettingKeys.rightPanelWidth =>
        current.copyWith(rightPanelWidth: (value as num).toDouble()),
      SettingKeys.thumbnailSmallSize =>
        current.copyWith(thumbnailSmallSize: value as int),
      SettingKeys.thumbnailMediumSize =>
        current.copyWith(thumbnailMediumSize: value as int),
      SettingKeys.thumbnailCacheLimit =>
        current.copyWith(thumbnailCacheLimitMB: value as int),
      SettingKeys.thumbnailConcurrency =>
        current.copyWith(thumbnailConcurrency: value as int),
      SettingKeys.previewMaxSize =>
        current.copyWith(previewMaxSize: value as int),
      SettingKeys.gridCacheExtent =>
        current.copyWith(gridCacheExtent: value as int),
      SettingKeys.importExifConcurrency =>
        current.copyWith(importExifConcurrency: value as int),
      SettingKeys.importThumbnailConcurrency =>
        current.copyWith(importThumbnailConcurrency: value as int),
      SettingKeys.importAutoGenerateThumbs =>
        current.copyWith(importAutoGenerateThumbs: value as bool),
      SettingKeys.importWatchFolders =>
        current.copyWith(importWatchFolders: value as bool),
      SettingKeys.maxFileSizeMB =>
        current.copyWith(maxFileSizeMB: value as int),
      SettingKeys.searchDebounceMs =>
        current.copyWith(searchDebounceMs: value as int),
      SettingKeys.searchScopeFileName =>
        current.copyWith(searchScopeFileName: value as bool),
      SettingKeys.searchScopeTitle =>
        current.copyWith(searchScopeTitle: value as bool),
      SettingKeys.searchScopeDescription =>
        current.copyWith(searchScopeDescription: value as bool),
      SettingKeys.searchScopeCamera =>
        current.copyWith(searchScopeCamera: value as bool),
      SettingKeys.searchScopeKeywords =>
        current.copyWith(searchScopeKeywords: value as bool),
      SettingKeys.defaultViewMode =>
        current.copyWith(defaultViewMode: value as String),
      SettingKeys.defaultThumbSize =>
        current.copyWith(defaultThumbSize: value as String),
      SettingKeys.defaultSortBy =>
        current.copyWith(defaultSortBy: value as String),
      SettingKeys.defaultAscending =>
        current.copyWith(defaultAscending: value as bool),
      SettingKeys.imageCacheMaxCount =>
        current.copyWith(imageCacheMaxCount: value as int),
      SettingKeys.imageCacheMaxSizeMB =>
        current.copyWith(imageCacheMaxSizeMB: value as int),
      SettingKeys.pageSize => current.copyWith(pageSize: value as int),
      SettingKeys.editAutoSave =>
        current.copyWith(editAutoSave: value as bool),
      SettingKeys.editAutoSaveDebounceMs =>
        current.copyWith(editAutoSaveDebounceMs: value as int),
      SettingKeys.editAutoSaveOnSwitch =>
        current.copyWith(editAutoSaveOnSwitch: value as bool),
      SettingKeys.editAutoSaveOnClose =>
        current.copyWith(editAutoSaveOnClose: value as bool),
      SettingKeys.editHistoryEnabled =>
        current.copyWith(editHistoryEnabled: value as bool),
      SettingKeys.editHistoryMaxCount =>
        current.copyWith(editHistoryMaxCount: value as int),
      SettingKeys.editAutoAdjustPreserve =>
        current.copyWith(editAutoAdjustPreserve: value as bool),
      SettingKeys.editAutoAdjustEngine =>
        current.copyWith(editAutoAdjustEngine: value as String),
      SettingKeys.editNeuralEnhanceStrength =>
        current.copyWith(
            editNeuralEnhanceStrength: (value as num).toDouble()),
      SettingKeys.editSuperResolutionEnabled =>
        current.copyWith(editSuperResolutionEnabled: value as bool),
      SettingKeys.editHistoryDebounceMs =>
        current.copyWith(editHistoryDebounceMs: value as int),
      SettingKeys.aiModelPath =>
        current.copyWith(aiModelPath: value as String),
      SettingKeys.aiAutoLoadModel =>
        current.copyWith(aiAutoLoadModel: value as bool),
      SettingKeys.aiAnalysisSize =>
        current.copyWith(aiAnalysisSize: value as int),
      _ => current,
    };
  }
}

/// 设置 Provider
final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettingsState>((ref) {
  return SettingsNotifier(ref.read(settingsDaoProvider));
});