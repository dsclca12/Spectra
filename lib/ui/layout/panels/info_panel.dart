import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/models/photo_ext.dart';
import '../../../providers/catalog_provider.dart';
import '../../../providers/selection_provider.dart';
import '../../../providers/providers.dart';
import '../../components/star_rating.dart';
import '../../components/color_label.dart';
import '../../components/metadata_view.dart';
import '../../components/thumbnail_widget.dart';

/// 右栏：信息面板
///
/// 通常显示当前选中的照片信息；
/// 如果传入了 [photoId]，则直接显示该照片信息（用于查看器场景）。
///
/// [showPreview] 控制是否显示缩略图预览，在查看器场景中默认为 false
/// 以避免与主图区域重复。
class InfoPanel extends ConsumerWidget {
  final int? photoId;
  final bool showPreview;

  const InfoPanel({super.key, this.photoId, this.showPreview = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 如果传入了 photoId，则直接使用它；否则从选中状态获取
    final int targetId;
    if (photoId != null) {
      targetId = photoId!;
    } else {
      final selection = ref.watch(selectionProvider);
      if (!selection.hasSelection) {
        return _EmptyInfoPanel(context);
      }
      targetId = selection.selectedIds.first;
    }

    final photoAsync = ref.watch(photoByIdProvider(targetId));

    return Container(
      color: Theme.of(context).canvasColor,
      child: photoAsync.when(
        data: (photo) {
          if (photo == null) return _EmptyInfoPanel(context);
          return _PhotoInfoContent(photo: photo, showPreview: showPreview);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
      ),
    );
  }

  Widget _EmptyInfoPanel(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.canvasColor,
      child: Column(
        children: [
          _PanelHeader(title: '信息'),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.info_outline, size: 30,
                          color: theme.colorScheme.secondary),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '选择一张照片查看详情',
                      style: TextStyle(
                        color: theme.colorScheme.secondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 面板标题栏
class _PanelHeader extends StatelessWidget {
  final String title;

  const _PanelHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.canvasColor,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// 照片信息内容
class _PhotoInfoContent extends ConsumerWidget {
  final Photo photo;
  final bool showPreview;

  const _PhotoInfoContent({required this.photo, this.showPreview = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        const _PanelHeader(title: '信息'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              // 预览图（单图模式下隐藏，避免与主图区域重复）
              if (showPreview) ...[
                _PreviewImage(photo: photo),
                const SizedBox(height: 16),
              ],

              // 基本信息
              _SectionTitle(title: '基本信息'),
              _InfoRow('文件名', photo.fileName),
              _InfoRow('尺寸', photo.formattedResolution),
              _InfoRow('大小', photo.formattedFileSize),
              _InfoRow('修改日期', _formatDateTime(photo.modifiedAt)),
              const SizedBox(height: 12),

              // EXIF
              _SectionTitle(title: 'EXIF'),
              MetadataView(photo: photo),
              const SizedBox(height: 12),

              // GPS
              if (photo.latitude != null && photo.longitude != null) ...[
                _SectionTitle(title: 'GPS'),
                _InfoRow('纬度', '${photo.latitude!.toStringAsFixed(4)}°'),
                _InfoRow('经度', '${photo.longitude!.toStringAsFixed(4)}°'),
                if (photo.altitude != null)
                  _InfoRow('海拔', '${photo.altitude!.toStringAsFixed(1)} m'),
                const SizedBox(height: 12),
              ],

              // 分类信息
              _SectionTitle(title: '分类'),
              _InfoRow('评分', ''),
              StarRating(
                rating: photo.rating,
                starSize: 20,
                onChanged: (value) async {
                  final catalogService = ref.read(catalogServiceProvider);
                  await catalogService.setRating(photo.id, value);
                  ref.invalidate(photoByIdProvider(photo.id));
                  ref.invalidate(catalogProvider);
                },
              ),
              const SizedBox(height: 8),
              _InfoRow('旗标', _pickLabelName(photo.pickLabel)),
              const SizedBox(height: 8),
              _InfoRow('色标', ''),
              ColorLabelSelector(
                colorLabel: photo.colorLabel,
                onChanged: (value) async {
                  final catalogService = ref.read(catalogServiceProvider);
                  await catalogService.setColorLabel(photo.id, value);
                  ref.invalidate(photoByIdProvider(photo.id));
                  ref.invalidate(catalogProvider);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _pickLabelName(int label) {
    return switch (label) {
      1 => 'Pick',
      2 => 'Reject',
      _ => '无',
    };
  }
}

/// 预览图 — 使用 512px 缩略图而非原图，避免加载几十 MB 的全分辨率图片
class _PreviewImage extends ConsumerWidget {
  final Photo photo;

  const _PreviewImage({required this.photo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: ThumbnailWidget(
          photoId: photo.id,
          filePath: photo.path,
          size: 512,
        ),
      ),
    );
  }
}

/// 分区标题
class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 12,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// 信息行
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}