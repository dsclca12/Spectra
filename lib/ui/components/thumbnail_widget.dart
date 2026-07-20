import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/thumbnail_provider.dart';

/// 缩略图组件 — 带加载状态和缓存
///
/// 关键：缩略图尺寸变化（放大/缩小缩略图）时，新的 `thumbnailPathProvider`
/// family 成员返回 `AsyncLoading`。若直接显示 loading 占位，所有缩略图
/// 会同时闪烁为转圈再切回图片。这里缓存上一次成功加载的缩略图路径，
/// 在新尺寸缩略图生成期间继续显示旧图（由 BoxFit.cover 自动缩放填充
/// 新单元格），配合 gaplessPlayback 实现无缝切换，消除闪烁。
class ThumbnailWidget extends ConsumerStatefulWidget {
  final int photoId;
  final String filePath;
  final int size;
  final BoxFit fit;

  const ThumbnailWidget({
    super.key,
    required this.photoId,
    required this.filePath,
    this.size = 128,
    this.fit = BoxFit.cover,
  });

  @override
  ConsumerState<ThumbnailWidget> createState() => _ThumbnailWidgetState();
}

class _ThumbnailWidgetState extends ConsumerState<ThumbnailWidget> {
  /// 上一次成功加载的缩略图路径 — 尺寸变化时用于在新缩略图生成期间
  /// 继续显示旧图，避免闪烁。
  String? _lastThumbPath;

  /// 缓存路径对应的 photoId — 用于检测 widget 复用后 photoId 变化，
  /// 此时旧路径属于另一张照片，必须清除避免显示错误图片。
  int? _lastThumbPathPhotoId;

  @override
  void didUpdateWidget(covariant ThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // widget 被复用（如 GridView/ListView 滚动时）但 photoId 变化 —
    // 旧缩略图属于另一张照片，必须清除，否则会显示错误图片。
    if (widget.photoId != oldWidget.photoId) {
      _lastThumbPath = null;
      _lastThumbPathPhotoId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 高 DPI 屏幕（如 2x 缩放）上，逻辑像素 180 实际渲染为 360 物理像素。
    // 需要以 devicePixelRatio 倍率请求和缓存缩略图，否则 180px 源图在
    // 360px 渲染区域会被拉伸导致模糊。
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final physicalSize = (widget.size * devicePixelRatio).round();

    final thumbAsync = ref.watch(thumbnailPathProvider(ThumbnailRequest(
      photoId: widget.photoId,
      filePath: widget.filePath,
      size: physicalSize,
    )));

    // 同步缓存最新成功路径 — 用于 loading/error 时回退显示。
    // 仅当路径属于当前 photoId 时才缓存，避免跨照片污染。
    thumbAsync.whenData((thumbPath) {
      if (thumbPath != null) {
        _lastThumbPath = thumbPath;
        _lastThumbPathPhotoId = widget.photoId;
      }
    });

    // 安全获取回退路径 — 仅当缓存路径确实属于当前照片时才使用。
    // didUpdateWidget 已清除跨照片的旧路径，这里做二次保护。
    final fallbackPath =
        (_lastThumbPathPhotoId == widget.photoId) ? _lastThumbPath : null;

    // RepaintBoundary 隔离每个缩略图的重绘范围
    // 滚动时只有可见项重绘，不会波及其他项
    return RepaintBoundary(
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        child: thumbAsync.when(
          data: (thumbPath) {
            if (thumbPath == null) {
              // 缩略图生成失败或尚未生成 — 显示占位图，不回退到原图
              // 原图可能几十 MB，网格中同时加载多张会导致内存爆炸
              // 但若有上一尺寸的旧图，优先显示旧图而非错误占位
              if (fallbackPath != null) {
                return _buildImage(fallbackPath, physicalSize);
              }
              return _ErrorWidget(size: widget.size);
            }
            return _buildImage(thumbPath, physicalSize);
          },
          // 尺寸变化时新 provider 处于 loading — 继续显示旧图，
          // 由 BoxFit.cover 自动缩放填充新单元格，无闪烁。
          // 仅在首次加载（无旧图）时显示转圈占位。
          loading: () {
            if (fallbackPath != null) {
              return _buildImage(fallbackPath, physicalSize);
            }
            return _LoadingWidget(size: widget.size);
          },
          error: (e, _) {
            if (fallbackPath != null) {
              return _buildImage(fallbackPath, physicalSize);
            }
            return _ErrorWidget(size: widget.size);
          },
        ),
      ),
    );
  }

  /// 构建 Image.file — 统一参数，确保旧图与新图行为一致。
  Widget _buildImage(String thumbPath, int cacheWidth) {
    return Image.file(
      File(thumbPath),
      fit: widget.fit,
      filterQuality: FilterQuality.medium,
      // 只设 cacheWidth 不设 cacheHeight —
      // 同时设两个会将图片强制拉伸为正方形，破坏宽高比
      // 只设 cacheWidth 则按宽度等比缩放，BoxFit.cover 负责裁剪填充
      cacheWidth: cacheWidth,
      // gaplessPlayback 避免加载完成时闪烁
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) =>
          _ErrorWidget(size: widget.size),
    );
  }
}

/// 加载中占位
class _LoadingWidget extends StatelessWidget {
  final int size;

  const _LoadingWidget({required this.size});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
    );
  }
}

/// 错误占位
class _ErrorWidget extends StatelessWidget {
  final int size;

  const _ErrorWidget({required this.size});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.broken_image_outlined,
        size: size * 0.3,
        color: Theme.of(context).colorScheme.secondary,
      ),
    );
  }
}