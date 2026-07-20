import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/models/photo_ext.dart';
import '../../providers/selection_provider.dart';
import '../screens/viewer_screen.dart';
import 'star_rating.dart';
import 'thumbnail_widget.dart';

/// 照片列表视图
class PhotoList extends ConsumerWidget {
  final List<Photo> photos;

  const PhotoList({super.key, required this.photos});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Material 为 ListTile 提供 ink splash 容器
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: ListView.builder(
        // 增加 scrollCacheExtent 预渲染屏幕外项目，滚动时更流畅
        scrollCacheExtent: const ScrollCacheExtent.pixels(500),
        // 固定 itemExtent — 让 Flutter 知道每个项的精确高度，
        // 避免计算每个项的尺寸，大幅提升滚动性能
        itemExtent: 72,
        itemCount: photos.length,
        itemBuilder: (context, index) {
          final photo = photos[index];
          return _PhotoListTile(photo: photo);
        },
      ),
    );
  }
}

class _PhotoListTile extends ConsumerStatefulWidget {
  final Photo photo;

  const _PhotoListTile({required this.photo});

  @override
  ConsumerState<_PhotoListTile> createState() => _PhotoListTileState();
}

class _PhotoListTileState extends ConsumerState<_PhotoListTile> {
  DateTime? _lastTapTime;

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    // 用 Selector 隔离选中状态，避免选中变化时重建所有列表项
    final isSelected = ref.watch(
      selectionProvider.select((s) => s.isSelected(photo.id)),
    );

    return ListTile(
      dense: true,
      leading: SizedBox(
        width: 64,
        height: 64,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          // 使用缩略图而非原图 — 原图可能几十 MB，列表 200 条会耗尽内存
          child: ThumbnailWidget(
            photoId: photo.id,
            filePath: photo.path,
            size: 128,
          ),
        ),
      ),
      title: Text(
        photo.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Row(
        children: [
          if (photo.dateTaken != null)
            Text(
              '${photo.dateTaken!.year}-${photo.dateTaken!.month.toString().padLeft(2, '0')}-${photo.dateTaken!.day.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          const SizedBox(width: 12),
          Text(
            photo.formattedFileSize,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.secondary,
            ),
          ),
          const SizedBox(width: 12),
          if (photo.cameraModel != null)
            Text(
              photo.cameraModel!,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (photo.rating > 0)
            StarRating(
              rating: photo.rating,
              starSize: 12,
              onChanged: (_) {},
              interactive: false,
            ),
          if (photo.pickLabel == 1)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.flag, size: 16, color: Colors.white),
            ),
          if (photo.pickLabel == 2)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.close, size: 16, color: Color(0xFFE81123)),
            ),
        ],
      ),
      selected: isSelected,
      onTap: () {
        // 双击检测 — 300ms 内连续两次点击 = 打开查看器
        final now = DateTime.now();
        if (_lastTapTime != null &&
            now.difference(_lastTapTime!) < const Duration(milliseconds: 300)) {
          _lastTapTime = null;
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ViewerScreen(photoId: photo.id),
            ),
          );
          return;
        }
        _lastTapTime = now;

        final selection = ref.read(selectionProvider);
        if (selection.hasSelection) {
          ref.read(selectionProvider.notifier).toggle(photo.id);
        } else {
          ref.read(selectionProvider.notifier).select(photo.id);
        }
      },
      onLongPress: () {
        // 触摸屏长按 = 上下文菜单（与网格一致）
        showMenu<void>(
          context: context,
          position: const RelativeRect.fromLTRB(100, 100, 0, 0),
          items: [
            PopupMenuItem<void>(
              child: const Text('在查看器中打开'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ViewerScreen(photoId: photo.id),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}