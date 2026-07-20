import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/daos/photo_dao.dart';
import '../../core/constants.dart';
import '../../core/concurrency.dart';
import 'image_decoder_service.dart';

/// 缩略图服务 — 分级缓存生成
///
/// 性能策略：
/// - 标准格式（JPEG/PNG/WebP/BMP）用 `dart:ui` 原生解码器（Skia/Impeller）
///   - 在 native 线程异步执行，不阻塞 UI 线程
///   - `targetWidth` 参数直接解码到目标尺寸，无需解码全分辨率
///   - 比 `package:image` 快 10-50 倍，内存占用降低 90%+
/// - RAW/HEIC/AVIF/TIFF 用 Windows WIC（通过 PowerShell + WPF）
///   - WIC 是 Windows 内置组件，支持各种 RAW 和 HEIC 格式
///   - 需要安装对应的 codec pack（Microsoft Store 免费）
/// - 内存缓存已生成的缩略图路径，避免重复 DB 查询和文件存在检查
/// - 信号量限制并发解码数量，避免资源爆炸
class ThumbnailService {
  ThumbnailService({required PhotoDao photoDao, required ImageDecoderService imageDecoder})
      : _imageDecoder = imageDecoder;

  final ImageDecoderService _imageDecoder;

  String? _cacheDirPath;

  /// 内存缓存：photoId_size → 缩略图路径（或 null 表示生成失败）
  /// 避免每次 build 都触发 DB 状态查询 + 文件存在检查
  /// 使用 LRU 策略限制大小 — 长时间滚动后避免缓存无限增长
  final _pathCache = <String, String?>{};
  static const int _maxPathCacheSize = 500;

  /// 信号量限制并发缩略图生成 — 避免 UI 滚动时同时创建大量解码任务
  /// 导入时使用更低的并发数（由调用方控制）
  final Semaphore _generateSemaphore = Semaphore(4);

  /// 写入路径缓存并执行 LRU 淘汰
  void _setCache(String key, String? value) {
    _pathCache[key] = value;
    // LRU 淘汰 — 超过上限时删除最早插入的条目
    // Dart Map 保持插入顺序，remove 最旧的 key 即可
    if (_pathCache.length > _maxPathCacheSize) {
      _pathCache.remove(_pathCache.keys.first);
    }
  }

  /// 初始化缓存目录
  Future<String> _getCacheDir() async {
    if (_cacheDirPath != null) return _cacheDirPath!;
    final supportDir = await getApplicationSupportDirectory();
    final cacheDir = Directory(p.join(supportDir.path, AppConstants.thumbnailCacheDir));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    _cacheDirPath = cacheDir.path;
    return _cacheDirPath!;
  }

  /// 获取缩略图路径
  ///
  /// [size] 为目标尺寸（128 或 512）
  Future<String> getThumbnailPath(int photoId, int size) async {
    final cacheDir = await _getCacheDir();
    return p.join(cacheDir, '${photoId}_$size.png');
  }

  /// 同步生成缩略图
  Future<String?> generate(int photoId, String filePath, {int size = AppConstants.thumbnailSmall}) async {
    // 内存缓存命中 — 已生成过的直接返回，避免重复 DB 查询
    final cacheKey = '${photoId}_$size';
    if (_pathCache.containsKey(cacheKey)) {
      return _pathCache[cacheKey];
    }

    // 先检查缓存文件是否已存在 — 如果已有缩略图文件，直接返回，完全跳过信号量和 DB 写入
    // 这是滚动时最常见的情况：缩略图已生成过，只需读文件路径
    final cacheDir = await _getCacheDir();
    final thumbPath = p.join(cacheDir, '${photoId}_$size.png');
    if (await File(thumbPath).exists()) {
      _setCache(cacheKey, thumbPath);
      return thumbPath;
    }

    // 信号量限流 — 避免滚动时大量并发解码
    final release = await _generateSemaphore.acquire();
    try {
      // 再次检查缓存文件（可能在等待信号量期间其他任务已生成）
      final thumbFile = File(thumbPath);
      if (await thumbFile.exists()) {
        _setCache(cacheKey, thumbPath);
        return thumbPath;
      }

      final file = File(filePath);
      if (!await file.exists()) {
        _setCache(cacheKey, null);
        return null;
      }

      // 使用 ImageDecoderService 解码 — 自动选择 dart:ui 或 WIC
      // targetWidth 让解码器直接解码到目标尺寸，无需解码全分辨率
      final result = await _imageDecoder.decodeToPngFile(
        filePath,
        outputPath: thumbPath,
        targetWidth: size,
      );

      if (result == null) {
        _setCache(cacheKey, null);
        return null;
      }

      _setCache(cacheKey, thumbPath);
      return thumbPath;
    } catch (e) {
      _setCache(cacheKey, null);
      return null;
    } finally {
      release();
    }
  }

  /// 生成大尺寸预览图（512px）
  Future<String?> generatePreview(int photoId, String filePath) async {
    return generate(photoId, filePath, size: AppConstants.thumbnailMedium);
  }

  /// 删除缩略图缓存
  Future<void> deleteCache(int photoId) async {
    final cacheDir = await _getCacheDir();
    for (final size in [AppConstants.thumbnailSmall, AppConstants.thumbnailMedium]) {
      final file = File(p.join(cacheDir, '${photoId}_$size.png'));
      if (await file.exists()) {
        await file.delete();
      }
      _pathCache.remove('${photoId}_$size');
    }
  }

  /// 清理所有缩略图缓存
  Future<void> clearAllCache() async {
    final cacheDir = await _getCacheDir();
    final dir = Directory(cacheDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
    _pathCache.clear();
  }

  /// 获取缓存大小
  ///
  /// 使用 Future.wait 并行 stat 所有文件，避免逐个 await 造成 I/O 串行化。
  /// 对于包含数万个缩略图的大缓存，串行 stat 可能耗时数秒。
  Future<int> getCacheSize() async {
    final cacheDir = await _getCacheDir();
    final dir = Directory(cacheDir);
    if (!await dir.exists()) return 0;

    final entities = await dir.list(recursive: true).toList();
    final stats = await Future.wait(
      entities.whereType<File>().map((f) => f.stat()),
    );
    return stats.fold<int>(0, (sum, s) => sum + s.size);
  }

  /// LRU 清理 — 当缓存超过上限时删除最旧的缩略图文件
  ///
  /// 按文件最后修改时间排序，删除最旧的文件直到总大小低于上限。
  /// 建议在应用空闲时或导入完成后调用。
  ///
  /// 优化：先用 Future.wait 并行 stat 收集文件信息，再用批量删除减少 I/O 次数。
  Future<void> pruneCache() async {
    final cacheDir = await _getCacheDir();
    final dir = Directory(cacheDir);
    if (!await dir.exists()) return;

    // 并行 stat 所有文件 — list + stat 串行对数千文件很慢
    final entities = await dir.list().toList();
    final fileEntries = <_CacheEntry>[];
    int totalSize = 0;

    final stats = await Future.wait(
      entities.whereType<File>().map((f) => f.stat()),
    );
    for (var i = 0; i < stats.length; i++) {
      final file = entities.whereType<File>().elementAt(i);
      final stat = stats[i];
      fileEntries.add(_CacheEntry(file, stat.size, stat.modified));
      totalSize += stat.size;
    }

    if (totalSize <= AppConstants.maxCacheSizeBytes) return;

    // 按修改时间升序排序（最旧在前）
    fileEntries.sort((a, b) => a.modified.compareTo(b.modified));

    // 批量删除 — 收集要删的文件路径后并行删除
    final toDelete = <File>[];
    for (final entry in fileEntries) {
      if (totalSize <= AppConstants.maxCacheSizeBytes) break;
      toDelete.add(entry.file);
      totalSize -= entry.size;
    }
    await Future.wait(toDelete.map((f) => f.delete().catchError((_) {})));

    // 清理变动的项对应的内存缓存
    for (final entry in toDelete) {
      final fileName = p.basename(entry.path);
      final parts = fileName.replaceAll('.png', '').split('_');
      if (parts.length == 2) {
        _pathCache.remove('${parts[0]}_${parts[1]}');
      }
    }
  }
}

/// 缓存文件条目
class _CacheEntry {
  final File file;
  final int size;
  final DateTime modified;

  const _CacheEntry(this.file, this.size, this.modified);
}