import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../providers/viewer_image_provider.dart';

/// 单页照片 — InteractiveViewer + 双击缩放
///
/// 每个 PageView 页面独立管理缩放，共享同一个 TransformationController。
/// 使用 ConsumerWidget 让每个页面独立 watch 自己的 viewerImageProvider，
/// 避免 itemBuilder 重建时所有页面重新 watch 导致的闪烁。
class PhotoPage extends ConsumerWidget {
  final Photo photo;
  final bool isCurrentPage;
  final String? previousImagePath;
  final TransformationController transformController;
  final VoidCallback? onDoubleTap;
  final void Function(ScaleStartDetails)? onTransformStart;
  final void Function(ScaleEndDetails)? onTransformEnd;

  const PhotoPage({
    super.key,
    required this.photo,
    required this.isCurrentPage,
    required this.previousImagePath,
    required this.transformController,
    this.onDoubleTap,
    this.onTransformStart,
    this.onTransformEnd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageAsync = ref.watch(viewerImageProvider(photo));
    final imagePath = imageAsync.valueOrNull ?? previousImagePath;

    Widget pageContent = GestureDetector(
      onDoubleTap: isCurrentPage ? onDoubleTap : null,
      child: InteractiveViewer(
        // 非当前页禁用所有手势 — 阻止相邻缓存页的 InteractiveViewer 参与手势竞技场。
        // 所有页面共享同一个 TransformationController，若相邻页也接收手势，
        // 双指缩放时相邻页会竞争手势，以当前 scale 为基线乘以新 scale → 跳变。
        panEnabled: isCurrentPage,
        scaleEnabled: isCurrentPage,
        maxScale: 5.0,
        // minScale 略低于 1.0 — 允许缩小到 0.8 后弹回，避免硬卡在 1.0。
        // minScale=1.0 时缩小到 1.0 后继续捏合 scale 不变，手势仍在进行，
        // 用户感觉"卡住"。minScale=0.8 让 InteractiveViewer 的弹回动画处理过渡。
        minScale: 0.8,
        transformationController: transformController,
        onInteractionStart: onTransformStart,
        onInteractionEnd: onTransformEnd,
        child: _buildImage(imageAsync, imagePath),
      ),
    );

    // 非当前页排除语义树 — 阻止相邻缓存页的 InteractiveViewer 共享
    // 同一个 TransformationController 时并发更新语义节点，导致 Windows
    // 辅助功能桥接器 AXTree 更新失败（"Nodes left pending" 错误）。
    if (!isCurrentPage) {
      pageContent = ExcludeSemantics(child: pageContent);
    }

    return pageContent;
  }

  Widget _buildImage(AsyncValue<String?> imageAsync, String? imagePath) {
    if (imageAsync is AsyncError) {
      return const Center(
        child: Icon(Icons.broken_image, size: 64, color: Colors.white54),
      );
    }
    if (imagePath == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }
    // RepaintBoundary 隔离图片重绘 — 缩放变换时只有此层重绘，
    // 不会波及 PageView 和其他页面，进一步消除闪烁
    return RepaintBoundary(
      child: Image.file(
        File(imagePath),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) => const Center(
          child: Icon(Icons.broken_image, size: 64, color: Colors.white54),
        ),
      ),
    );
  }
}