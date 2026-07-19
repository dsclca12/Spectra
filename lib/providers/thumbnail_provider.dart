import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// 缩略图路径 Provider — 按照片 ID 获取缩略图
///
/// 使用 autoDispose — 滚动出屏幕的缩略图 provider 被自动销毁。
/// ThumbnailService 内部的 _pathCache 会缓存已生成的路径，
/// 滚动回来时 provider 重新创建但 generate() 会命中缓存立即返回。
///
/// 不使用 autoDispose 会导致所有曾经可见的缩略图 provider 永远存活，
/// 200 项网格滚动几轮后累积上千个 provider，内存持续增长。
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