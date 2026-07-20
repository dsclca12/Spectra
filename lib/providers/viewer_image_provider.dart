import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../data/database/app_database.dart';
import '../data/models/photo_ext.dart';
import 'providers.dart';

/// 全屏预览图 Provider — 为非 Flutter 原生格式生成可显示的 PNG 预览
///
/// 标准格式（JPEG/PNG/WebP/BMP）直接用 `Image.file` 显示，无需此 provider。
/// RAW/HEIC/AVIF/TIFF 需要通过 WIC 解码为 PNG 后才能在 Flutter 中显示。
///
/// 预览图缓存在应用支持目录下，避免重复解码。
/// 使用 `previewMaxSize`（1024px）作为目标宽度 — 全屏查看足够清晰，
/// 但远小于原始 RAW 分辨率，解码速度快且内存占用低。
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

/// 预览清理计数器 — 每生成一张预览递增，达到阈值时触发清理
int _previewGenerateCount = 0;

/// 预览缓存最大存活天数
const _previewMaxAgeDays = 30;

/// 每生成 N 张新预览后触发一次过期清理
const _previewCleanInterval = 50;

/// 懒清理：仅当生成新预览且达到阈值时才扫描目录
/// 比定时器方案更简单，对用户无感知
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
        // ignore: avoid_print
        print('预览缓存清理：删除了 $deleted 个过期文件');
      }
    } catch (_) {}
  });
}