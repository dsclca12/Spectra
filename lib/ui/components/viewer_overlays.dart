import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/models/photo_ext.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/providers.dart';
import 'star_rating.dart';

/// 顶部信息栏 — 显示文件名和相机参数
///
/// 内部使用 translucent GestureDetector 让背景区域手势穿透到 PageView，
/// 只有 IconButton 等可点击区域响应手势。
class ViewerTopBar extends StatelessWidget {
  final Photo photo;
  final VoidCallback? onClose;
  final VoidCallback? onToggleLeftPanel;
  final VoidCallback? onToggleRightPanel;
  final bool leftPanelVisible;
  final bool rightPanelVisible;

  const ViewerTopBar({
    super.key,
    required this.photo,
    this.onClose,
    this.onToggleLeftPanel,
    this.onToggleRightPanel,
    this.leftPanelVisible = true,
    this.rightPanelVisible = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {}, // 消费空白区域点击，不穿透（避免误触）
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            // 左面板切换
            if (onToggleLeftPanel != null)
              IconButton(
                icon: Icon(
                  leftPanelVisible
                      ? Icons.info_outline
                      : Icons.info,
                  color: Colors.white70,
                  size: 20,
                ),
                tooltip: leftPanelVisible ? '隐藏信息面板' : '显示信息面板',
                onPressed: onToggleLeftPanel,
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    photo.fileName,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  if (photo.cameraModel != null)
                    Text(
                      '${photo.cameraModel} · ${photo.formattedAperture} · ${photo.shutterSpeed ?? ''} · ISO ${photo.iso?.toStringAsFixed(0) ?? ''}',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                ],
              ),
            ),
            // 右面板切换
            if (onToggleRightPanel != null)
              IconButton(
                icon: Icon(
                  rightPanelVisible
                      ? Icons.tune
                      : Icons.tune_outlined,
                  color: Colors.white70,
                  size: 20,
                ),
                tooltip: rightPanelVisible ? '隐藏编辑面板' : '显示编辑面板',
                onPressed: onToggleRightPanel,
              ),
            if (onClose != null)
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: onClose,
              ),
          ],
        ),
      ),
    );
  }
}

/// 底部操作栏 — 评分 + 旗标
///
/// 内部使用 translucent GestureDetector 让背景区域手势穿透到 PageView。
class ViewerBottomBar extends ConsumerWidget {
  final Photo photo;

  const ViewerBottomBar({
    super.key,
    required this.photo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {},
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black54, Colors.transparent],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 评分
            StarRating(
              rating: photo.rating,
              starSize: 28,
              onChanged: (value) async {
                final catalogService = ref.read(catalogServiceProvider);
                await catalogService.setRating(photo.id, value);
                ref.invalidate(photoByIdProvider(photo.id));
                ref.invalidate(catalogProvider);
              },
            ),
            const SizedBox(width: 32),

            // 旗标
            FlagButton(
              isPick: photo.isPick,
              isReject: photo.isReject,
              onChanged: (label) async {
                final catalogService = ref.read(catalogServiceProvider);
                await catalogService.setPickLabel(photo.id, label);
                ref.invalidate(photoByIdProvider(photo.id));
                ref.invalidate(catalogProvider);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 旗标按钮
class FlagButton extends StatelessWidget {
  final bool isPick;
  final bool isReject;
  final ValueChanged<int> onChanged;

  const FlagButton({
    super.key,
    required this.isPick,
    required this.isReject,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            Icons.flag,
            color: isPick ? Colors.white : Colors.white54,
            size: 24,
          ),
          tooltip: 'Pick (P)',
          onPressed: () => onChanged(isPick ? 0 : 1),
        ),
        IconButton(
          icon: Icon(
            Icons.close,
            color: isReject ? const Color(0xFFE81123) : Colors.white54,
            size: 24,
          ),
          tooltip: 'Reject (X)',
          onPressed: () => onChanged(isReject ? 0 : 2),
        ),
      ],
    );
  }
}

/// 导航按钮 — 大圆形触摸目标，触摸屏友好
class NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const NavButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: Colors.black38,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white70, size: 32),
        ),
      ),
    );
  }
}