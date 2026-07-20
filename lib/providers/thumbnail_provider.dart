import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// 缩略图路径 Provider — 按 (photoId + 尺寸) 获取缩略图文件路径
///
/// ⚡ 性能设计：
/// - 使用 autoDispose.family — 滚动出屏幕的 provider 自动销毁，
///   避免网格滚动几轮后累积上千个 provider 造成内存泄漏。
/// - ThumbnailService._pathCache（LRU 500 条）缓存已生成的路径，
///   滚动回来时 provider 重建但 generate() 命中缓存立即返回。
/// - ThumbnailService 内部使用 Semaphore(4) 限制并发解码，
///   避免 200 项网格同时触发 200 个 WIC/PowerShell 进程。
///
/// 参见：ThumbnailService.generate() 的完整缓存策略说明。
final thumbnailPathProvider =
    FutureProvider.autoDispose.family<String?, ThumbnailRequest>((ref, request) async {
  final thumbnailService = ref.read(thumbnailServiceProvider);
  return thumbnailService.generate(
    request.photoId,
    request.filePath,
    size: request.size,
  );
});

/// 缩略图请求参数
class ThumbnailRequest {
  final int photoId;
  final String filePath;
  final int size;

  const ThumbnailRequest({
    required this.photoId,
    required this.filePath,
    this.size = 128,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ThumbnailRequest &&
          runtimeType == other.runtimeType &&
          photoId == other.photoId &&
          filePath == other.filePath &&
          size == other.size;

  @override
  int get hashCode => Object.hash(photoId, filePath, size);
}