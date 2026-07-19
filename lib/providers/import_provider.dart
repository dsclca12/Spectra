import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/services/import_service.dart';
import 'catalog_provider.dart';
import 'providers.dart';

/// 导入状态
enum ImportStatus { idle, scanning, importing, completed, error }

/// 导入状态数据
class ImportState {
  final ImportStatus status;
  final int imported;
  final int skipped;
  final int failed;
  final String? currentFile;
  final String? error;

  const ImportState({
    this.status = ImportStatus.idle,
    this.imported = 0,
    this.skipped = 0,
    this.failed = 0,
    this.currentFile,
    this.error,
  });

  int get total => imported + skipped + failed;
  bool get isActive => status == ImportStatus.scanning || status == ImportStatus.importing;

  ImportState copyWith({
    ImportStatus? status,
    int? imported,
    int? skipped,
    int? failed,
    String? currentFile,
    String? error,
  }) {
    return ImportState(
      status: status ?? this.status,
      imported: imported ?? this.imported,
      skipped: skipped ?? this.skipped,
      failed: failed ?? this.failed,
      currentFile: currentFile ?? this.currentFile,
      error: error ?? this.error,
    );
  }
}

/// 导入 Provider
class ImportNotifier extends StateNotifier<ImportState> {
  final ImportService _importService;
  final Ref _ref;

  /// 进度通知节流定时器 — 避免逐文件 notifyListeners 导致 UI 狂刷
  Timer? _progressTimer;
  ImportProgress? _lastProgress;

  ImportNotifier(this._importService, this._ref) : super(const ImportState());

  /// 导入文件夹
  Future<void> importFolder(String dirPath) async {
    state = const ImportState(status: ImportStatus.scanning);

    try {
      await for (final progress
          in _importService.importFolder(dirPath, onProgress: _onProgress)) {
        // 只在完成时立即更新，中间进度由节流定时器处理
        if (progress.isCompleted) {
          _progressTimer?.cancel();
          _progressTimer = null;
          state = ImportState(
            status: ImportStatus.completed,
            imported: progress.imported,
            skipped: progress.skipped,
            failed: progress.failed,
          );
          // 刷新照片列表和文件夹列表（文件夹照片计数需更新）
          _ref.invalidate(catalogProvider);
          _ref.invalidate(folderListProvider);

          // 后台清理缩略图缓存 — 不阻塞 UI
          // 导入大量照片后缓存可能超过上限，LRU 清理最旧的缩略图
          Future.microtask(() async {
            try {
              final thumbnailService = _ref.read(thumbnailServiceProvider);
              await thumbnailService.pruneCache();
            } catch (_) {
              // 清理失败不影响功能
            }
          });
        }
      }
    } catch (e) {
      _progressTimer?.cancel();
      _progressTimer = null;
      state = ImportState(
        status: ImportStatus.error,
        error: e.toString(),
      );
    }
  }

  /// 进度回调 — 节流为每 200ms 最多更新一次 UI
  void _onProgress(ImportProgress p) {
    _lastProgress = p;
    _progressTimer ??= Timer.periodic(
      const Duration(milliseconds: 200),
      (_) {
        if (_lastProgress != null && !_lastProgress!.isCompleted) {
          state = state.copyWith(
            status: ImportStatus.importing,
            imported: _lastProgress!.imported,
            skipped: _lastProgress!.skipped,
            failed: _lastProgress!.failed,
            currentFile: _lastProgress!.currentFile,
          );
        }
      },
    );
  }

  /// 重置状态
  void reset() {
    _progressTimer?.cancel();
    _progressTimer = null;
    state = const ImportState();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }
}

final importProvider =
    StateNotifierProvider<ImportNotifier, ImportState>((ref) {
  return ImportNotifier(ref.read(importServiceProvider), ref);
});

/// 文件夹列表 Provider
final folderListProvider =
    FutureProvider.autoDispose<List<Folder>>((ref) async {
  final folderDao = ref.read(folderDaoProvider);
  return folderDao.getAll();
});