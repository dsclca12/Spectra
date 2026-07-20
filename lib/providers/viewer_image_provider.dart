import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../core/logging.dart';
import '../data/database/app_database.dart';
import '../data/models/photo_ext.dart';
import 'providers.dart';

/// 全屏预览图 Provider — 为非 Flutter 原生格式生成可显示的 PNG 预览
///
/// 标准格式（JPEG/PNG/WebP/BMP）直接用 `Image.file` 显示，无需此 provider。
/// RAW/HEIC/AVIF/TIFF 需要通过 WIC 解码为 PNG 后才能在 Flutter 中显示。
///
/// ⚡ 性能设计：
/// - previewMaxSize(1024px)：全屏查看足够清晰，但远小于原始 RAW 分辨率
///   （CR2/NEF 等通常 4000-8000px），解码速度快且内存占用低。
/// - 预览图缓存在应用支持目录 /previews/ 下，避免重复 WIC 解码。
/// - 每生成 50 张新预览触发一次过期清理（30 天未访问的旧预览）。
/// - 标准格式直接返回原路径（Image.file + FileImage），走 Flutter ImageCache。
///
/// ⚡ 预取策略（ViewerScreen）：
/// - 当前图片解码完成后，后台预加载前后各一张相邻图片。
/// - RAW/HEIC/AVIF/TIFF：调用本 provider 触发 WIC 解码写入磁盘缓存。
/// - 标准格式：precacheImage + FileImage 预解码到 Flutter ImageCache。
/// - 切换时直接命中缓存，零延迟。
final viewerImageProvider =
    FutureProvider.autoDispose.family<String?, Photo>((ref, photo) async {
  // 标准格式直接返回原文件路径 — Image.file 可以直接显示
  if (!photo.requiresExternalDecoder) {
    return photo.path;
  }

  // RAW/HEIC/AVIF/TIFF — 需要解码为 PNG
  final imageDecoder = ref.read(imageDecoderServiceProvider);
  final supportDir = await getApplicationSupportDirectory();
  final previewDir = p.join(supportDir.path, 'previews');
  final dir = Directory(previewDir);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }

  final previewPath = p.join(previewDir, '${photo.id}_${AppConstants.previewMaxSize}.png');

  // 缓存命中
  if (await File(previewPath).exists()) {
    return previewPath;
  }

  // 解码为 PNG 预览
  final result = await imageDecoder.decodeToPngFile(
    photo.path,
    outputPath: previewPath,
    targetWidth: AppConstants.previewMaxSize,
  );

  // 懒清理：每生成 50 张新预览后触发一次过期缓存清理
  // 避免预览目录无限膨胀（RAW 预览 PNG 每张约 2-5MB）
  _cleanStalePreviewsIfNeeded(previewDir, photo.id);

  return result;
});

/// 预览清理计数器 — 每生成一张预览递增，达到阈值时触发清理。
/// 注意：由于是全局静态变量，如果有多处同时调用（虽在当前架构中不适用），
/// 计数器可能被并发递增导致清理提前触发。当前架构中同一时间只有一个
/// viewerImageProvider 被 watch，因此是安全的。
/// 若后续支持多窗口/多标签同时打开查看器，应改为实例级计数器。
int _previewGenerateCount = 0;

/// 预览缓存最大存活天数。
/// RAW 预览 PNG 每张约 2-5MB，30 天后清理可腾出磁盘空间。
/// 若用户经常查看 RAW 照片，建议适当缩短此值。
const _previewMaxAgeDays = 30;

/// 每生成 N 张新预览后触发一次过期清理。
/// 50 张约 100-250MB 的产出后清理一次，频率适中。
/// 太频繁（<10）：每次清理扫描整个目录，I/O 开销大。
/// 太稀疏（>200）：预览目录可能膨胀到 1GB+。
const _previewCleanInterval = 50;

/// 懒清理：仅当生成新预览且达到阈值时才扫描目录
/// 比定时器方案更简单，对用户无感知。
/// 清理操作在 fire-and-forget Future 中执行，不阻塞 UI。
void _cleanStalePreviewsIfNeeded(String previewDir, int currentPhotoId) {
  _previewGenerateCount++;
  if (_previewGenerateCount < _previewCleanInterval) return;
  _previewGenerateCount = 0;

  // fire-and-forget：不阻塞预览加载
  Future(() async {
    try {
      final dir = Directory(previewDir);
      if (!await dir.exists()) return;
      final cutoff = DateTime.now().subtract(
        const Duration(days: _previewMaxAgeDays),
      );
      var deleted = 0;
      await for (final entity in dir.list()) {
        if (entity is File) {
          try {
            final stat = await entity.stat();
            if (stat.modified.isBefore(cutoff)) {
              await entity.delete();
              deleted++;
            }
          } catch (_) {}
        }
      }
      if (deleted > 0) {
        // 使用 AppLogger 而非 print，统一日志输出格式。
        // print 在 Flutter 中输出到 stdout，不能被 logcat/dump 过滤；
        // AppLogger 写入内存环形缓冲区（可在设置界面查看）+ debugPrint。
        AppLogger.info('PreviewCache', '预览缓存清理：删除了 $deleted 个过期文件');
      }
    } catch (_) {}
  });
}