import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../database/app_database.dart';
import '../database/daos/photo_dao.dart';
import '../database/daos/folder_dao.dart';
import '../../core/concurrency.dart';
import '../../core/enums.dart';
import 'file_system_service.dart';
import 'metadata_service.dart';
import 'thumbnail_service.dart';

/// 导入服务 — 编排文件夹扫描、EXIF 读取、缩略图生成
///
/// 性能策略：
/// - 批量查重：一次性查询已存在的路径集合，避免逐条 SELECT
/// - 批量插入：使用 drift batch 减少事务往返
/// - 后台任务限流：EXIF/缩略图通过信号量限制并发，避免内存爆炸
/// - 导入完成不等缩略图：缩略图由 UI 滚动时按需生成，导入只负责入库
class ImportService {
  final PhotoDao _photoDao;
  final FolderDao _folderDao;
  final FileSystemService _fileSystemService;
  final MetadataService _metadataService;
  final ThumbnailService _thumbnailService;

  /// 后台 EXIF 读取并发数
  final Semaphore _exifSemaphore = Semaphore(2);

  /// 后台缩略图生成并发数（导入时低并发，避免与 UI 滚动叠加）
  final Semaphore _thumbSemaphore = Semaphore(2);

  /// EXIF 更新回调 — 每次后台 EXIF 写入数据库后触发
  /// Provider 层可监听此回调来刷新 UI
  void Function(String filePath)? onExifUpdated;

  ImportService({
    required PhotoDao photoDao,
    required FolderDao folderDao,
    required FileSystemService fileSystemService,
    required MetadataService metadataService,
    required ThumbnailService thumbnailService,
    this.onExifUpdated,
  })  : _photoDao = photoDao,
        _folderDao = folderDao,
        _fileSystemService = fileSystemService,
        _metadataService = metadataService,
        _thumbnailService = thumbnailService;

  /// 导入文件夹
  ///
  /// [onProgress] 报告导入进度
  Stream<ImportProgress> importFolder(
    String dirPath, {
    void Function(ImportProgress)? onProgress,
  }) async* {
    final dirName = p.basename(dirPath);
    final now = DateTime.now();

    // 创建或更新文件夹记录
    final folderId = await _folderDao.insertOnConflictUpdate(
      FoldersCompanion(
        path: Value(dirPath),
        name: Value(dirName),
        lastScannedAt: Value(now),
        isWatched: const Value(1),
      ),
    );

    // ── 第一遍：收集所有候选文件路径 ──
    final candidates = <_CandidateFile>[];
    await for (final event in _fileSystemService.scanDirectory(dirPath)) {
      if (event.type == ScanEventType.completed) break;
      if (event.type != ScanEventType.fileFound) continue;
      if (event.fileStat == null) continue;
      candidates.add(_CandidateFile(event.path, event.fileStat!));
    }

    if (candidates.isEmpty) {
      yield const ImportProgress(
        imported: 0,
        skipped: 0,
        failed: 0,
        isCompleted: true,
      );
      return;
    }

    // ── 批量查重：一次性获取已存在的路径 ──
    final allPaths = candidates.map((c) => c.path).toList();
    final existingPaths = await _photoDao.getExistingPaths(allPaths);
    final existingSet = existingPaths.toSet();

    // ── 批量插入新文件 ──
    final newCandidates =
        candidates.where((c) => !existingSet.contains(c.path)).toList();
    final companions = <PhotosCompanion>[];
    for (final c in newCandidates) {
      companions.add(PhotosCompanion(
        folderId: Value(folderId),
        path: Value(c.path),
        fileName: Value(p.basename(c.path)),
        fileHash: const Value(''),
        fileSize: Value(c.stat.size),
        modifiedAt: Value(c.stat.modified),
        importedAt: Value(now),
        thumbnailStatus: const Value(ThumbnailStatus.notGenerated),
      ));
    }

    // 批量插入（单事务，无逐条往返）
    // 不使用 batchInsertReturning — 它通过 ORDER BY importedAt DESC LIMIT N 取回行，
    // 当多次导入的 importedAt 相同或数据库已有同时间戳行时结果不可靠。
    // 改为纯批量插入，EXIF 更新通过路径匹配。
    await _photoDao.batchInsert(companions);

    final imported = newCandidates.length;
    final skipped = candidates.length - newCandidates.length;
    const failed = 0;

    // 报告进度
    final progress = ImportProgress(
      imported: imported,
      skipped: skipped,
      failed: failed,
      currentFile: null,
    );
    onProgress?.call(progress);
    yield progress;

    // ── 后台触发 EXIF（fire-and-forget，不阻塞导入完成）──
    // EXIF 读取在后台进行，导入立即返回。UI 滚动时 EXIF 可能还在读取，
    // 但这不影响浏览 — EXIF 数据在 info panel 打开时才展示。
    // 用路径而非 photoId 入队，避免需要取回 ID 的额外查询。
    for (final c in newCandidates) {
      _enqueueExifByPath(c.path);
    }

    // 更新文件夹照片计数
    await _folderDao.updatePhotoCount(folderId, imported);

    // 不等待 EXIF — 导入立即完成，用户可以马上浏览
    // EXIF 在后台慢慢写入，UI 刷新时自然拿到最新数据

    yield ImportProgress(
      imported: imported,
      skipped: skipped,
      failed: failed,
      isCompleted: true,
    );
  }

  /// 排队 EXIF 读取（受信号量限流），返回 Future 在任务完成时完成
  Future<void> _enqueueExif(int photoId, String filePath) async {
    final release = await _exifSemaphore.acquire();
    try {
      final exifData = await _metadataService.readExif(filePath);
      if (exifData != null) {
        await _photoDao.updateExif(photoId, exifData);
      }
      // 无论是否读取到 EXIF，都通知 UI 刷新（显示数据或无 EXIF 提示）
      onExifUpdated?.call(filePath);
    } catch (_) {
      // EXIF 失败不影响导入 — 但仍通知 UI，避免一直处于加载中状态
      onExifUpdated?.call(filePath);
    } finally {
      release();
    }
  }

  /// 排队 EXIF 读取（按路径，fire-and-forget）— 不阻塞导入流程
  /// 通过路径更新 EXIF，避免需要先取回 photoId
  void _enqueueExifByPath(String filePath) {
    // fire-and-forget — 不 await，导入立即继续
    _exifSemaphore.acquire().then((release) async {
      try {
        final exifData = await _metadataService.readExif(filePath);
        if (exifData != null) {
          await _photoDao.updateExifByPath(filePath, exifData);
        }
        // 无论是否读取到 EXIF，都通知 UI 刷新
        onExifUpdated?.call(filePath);
      } catch (_) {
        // EXIF 失败不影响导入 — 但仍通知 UI
        onExifUpdated?.call(filePath);
      } finally {
        release();
      }
    });
  }

  /// 重试读取缺少 EXIF 的照片（启动时调用，fire-and-forget）
  /// 处理上一次导入时 EXIF 读取未完成或失败的情况。
  Future<void> retryMissingExif({int limit = 100}) async {
    try {
      final photos = await _photoDao.getPhotosWithoutExif(limit: limit);
      for (final photo in photos) {
        _enqueueExifByPath(photo.path);
      }
    } catch (_) {
      // 重试失败不影响功能
    }
  }

  /// 排队缩略图生成（受信号量限流），返回 Future 在任务完成时完成
  Future<void> _enqueueThumbnail(int photoId, String filePath) async {
    final release = await _thumbSemaphore.acquire();
    try {
      await _thumbnailService.generate(photoId, filePath);
    } catch (_) {
      // 缩略图失败不影响导入
    } finally {
      release();
    }
  }

  /// 处理文件系统变更（增量扫描）
  Future<void> handleFileChange(FileSystemChangeEvent event) async {
    switch (event.type) {
      case FileSystemChangeType.add:
        await _onFileAdded(event.path);
      case FileSystemChangeType.modify:
        await _onFileModified(event.path);
      case FileSystemChangeType.remove:
        await _onFileRemoved(event.path);
    }
  }

  Future<void> _onFileAdded(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    final existing = await _photoDao.getByPath(filePath);
    if (existing != null) return;

    final stat = await file.stat();
    final photoId = await _photoDao.insertPhoto(
      PhotosCompanion(
        path: Value(filePath),
        fileName: Value(p.basename(filePath)),
        fileHash: const Value(''),
        fileSize: Value(stat.size),
        modifiedAt: Value(stat.modified),
        importedAt: Value(DateTime.now()),
        thumbnailStatus: const Value(ThumbnailStatus.notGenerated),
      ),
    );

    _enqueueExif(photoId, filePath);
    _enqueueThumbnail(photoId, filePath);
  }

  Future<void> _onFileModified(String filePath) async {
    final photo = await _photoDao.getByPath(filePath);
    if (photo == null) return;

    final file = File(filePath);
    if (!await file.exists()) return;

    final stat = await file.stat();
    await _photoDao.updatePhoto(photo.copyWith(
      fileSize: stat.size,
      modifiedAt: stat.modified,
    ));

    // 重新生成缩略图
    _enqueueThumbnail(photo.id, filePath);
  }

  Future<void> _onFileRemoved(String filePath) async {
    await _photoDao.deleteByPath(filePath);
  }
}

/// 导入进度
class ImportProgress {
  final int imported;
  final int skipped;
  final int failed;
  final String? currentFile;
  final bool isCompleted;

  const ImportProgress({
    required this.imported,
    required this.skipped,
    required this.failed,
    this.currentFile,
    this.isCompleted = false,
  });

  int get total => imported + skipped + failed;
}

/// 候选文件（路径 + stat 缓存）
class _CandidateFile {
  final String path;
  final FileStat stat;

  const _CandidateFile(this.path, this.stat);
}