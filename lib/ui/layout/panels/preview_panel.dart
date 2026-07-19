import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/enums.dart';
import '../../../data/database/app_database.dart';
import '../../../providers/catalog_provider.dart';
import '../../../providers/providers.dart';
import '../../../providers/selection_provider.dart';
import '../../../providers/viewer_image_provider.dart';
import '../../components/empty_state.dart';
import '../../components/photo_page.dart';
import '../../components/viewer_overlays.dart';
import '../../components/zoom_aware_scroll_physics.dart';

/// 中栏：单图预览面板
///
/// 在三栏布局的中栏显示当前选中照片的大图预览，支持：
/// - 水平滑动切换照片（PageView + 磁吸物理）
/// - 双击缩放 / 手势缩放 / 平移（InteractiveViewer）
/// - 与网格选择状态双向联动（滑动→选中，选中→滑动）
/// - 键盘快捷键（方向键、评分、旗标、色标）
/// - 相邻图片预取（消除切换延迟）
class PreviewPanel extends ConsumerStatefulWidget {
  const PreviewPanel({super.key});

  @override
  ConsumerState<PreviewPanel> createState() => _PreviewPanelState();
}

class _PreviewPanelState extends ConsumerState<PreviewPanel>
    with TickerProviderStateMixin {
  /// PageView 控制器 — 原生滑动切换照片
  late PageController _pageController;

  /// InteractiveViewer 的控制器 — 切换照片时重置缩放
  final TransformationController _transformController =
      TransformationController();

  /// 当前缩放状态 — 用于禁用 PageView 滑动
  bool _isZoomed = false;

  /// 查看区域 GlobalKey — 获取视口尺寸用于计算缩放锚点
  final GlobalKey _viewerKey = GlobalKey();

  /// 双击缩放动画控制器 — 平滑过渡避免画面跳动
  late AnimationController _zoomAnimController;

  /// 当前显示的照片 ID — 从 selectionProvider 同步
  int? _currentPhotoId;

  /// 前一张照片 — catalog 刷新时 fallback 消除闪烁
  Photo? _previousPhoto;
  String? _previousImagePath;
  int? _lastPrefetchedPhotoId;

  /// 标记是否正在程序化切换（animateToPage），避免 onPageChanged 中的
  /// setState 与动画冲突导致跳变。
  bool _programmaticNavigation = false;

  /// 标记需要在下一帧 jumpToPage（首次构建或外部选择变化时）。
  bool _needsPageJump = false;

  /// 判断变换矩阵是否接近 identity — 用容差比较避免浮点误差。
  bool _isNearIdentity() {
    final m = _transformController.value.storage;
    const tol = 0.01;
    return (m[0] - 1).abs() < tol &&
        (m[5] - 1).abs() < tol &&
        m[1].abs() < tol &&
        m[4].abs() < tol &&
        m[12].abs() < tol &&
        m[13].abs() < tol;
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _transformController.addListener(_onTransformControllerChanged);
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformControllerChanged);
    _zoomAnimController.dispose();
    _pageController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  /// TransformationController 变化监听器 — 持续同步 _isZoomed。
  void _onTransformControllerChanged() {
    _isZoomed = !_isNearIdentity();
  }

  /// 双击切换缩放 — 在 1x 和 2x 之间平滑动画过渡
  void _toggleZoom() {
    _zoomAnimController.stop();

    final wasZoomed = !_isNearIdentity();
    final renderBox =
        _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? MediaQuery.sizeOf(context);
    final center = Offset(size.width / 2, size.height / 2);

    final Matrix4 target;
    if (!wasZoomed) {
      target = Matrix4.identity()
        ..translateByDouble(-center.dx, -center.dy, 0, 1)
        ..scaleByDouble(2.0, 2.0, 1.0, 1.0)
        ..translateByDouble(center.dx, center.dy, 0, 1);
    } else {
      target = Matrix4.identity();
    }

    _animateTransformTo(target);
  }

  /// 平滑动画过渡到目标变换矩阵
  void _animateTransformTo(Matrix4 target) {
    final start = _transformController.value.clone();
    final tween = Matrix4Tween(begin: start, end: target);

    _zoomAnimController.value = 0.0;

    void listener() {
      final t = Curves.easeOutCubic.transform(_zoomAnimController.value);
      _transformController.value = tween.transform(t);
    }

    _zoomAnimController.addListener(listener);
    _zoomAnimController.forward().whenComplete(() {
      _zoomAnimController.removeListener(listener);
    });
  }

  /// InteractiveViewer 手势开始 — 停止动画
  void _onTransformStart(ScaleStartDetails details) {
    _zoomAnimController.stop();
  }

  /// InteractiveViewer 手势结束
  void _onTransformEnd(ScaleEndDetails details) {}

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(catalogProvider);
    final selection = ref.watch(selectionProvider);

    // 从选中状态获取当前照片 ID
    final selectedId = selection.hasSelection ? selection.selectedIds.first : null;

    // 外部选择变化时标记需要跳转
    if (selectedId != null && selectedId != _currentPhotoId) {
      _currentPhotoId = selectedId;
      _needsPageJump = true;
    }

    return Container(
      color: Colors.black,
      child: _buildBody(catalogAsync),
    );
  }

  Widget _buildBody(AsyncValue<List<Photo>> catalogAsync) {
    if (catalogAsync is AsyncError) {
      return Center(
        child: Text('加载失败: ${catalogAsync.error}',
            style: const TextStyle(color: Colors.white)),
      );
    }

    final photos = catalogAsync.valueOrNull;

    // catalog 加载中或为空时用前一张照片保持显示
    if (photos == null || photos.isEmpty) {
      if (_previousPhoto != null) {
        return _buildContent(_previousPhoto!, const [], 0);
      }
      return const EmptyState(
        icon: Icons.photo_library_outlined,
        title: '没有照片',
        message: '导入照片后可在此预览',
      );
    }

    // 无选中照片时显示第一张
    if (_currentPhotoId == null) {
      _currentPhotoId = photos.first.id;
      _needsPageJump = true;
    }

    // 从列表中查找当前照片
    final index = photos.indexWhere((p) => p.id == _currentPhotoId);
    if (index < 0) {
      // 当前照片不在列表中（可能被筛选掉），显示第一张
      if (photos.isNotEmpty) {
        _currentPhotoId = photos.first.id;
        _needsPageJump = true;
        return _buildContent(photos.first, photos, 0);
      }
      if (_previousPhoto != null) {
        return _buildContent(_previousPhoto!, const [], 0);
      }
      return const Center(child: CircularProgressIndicator());
    }

    final photo = photos[index];
    _previousPhoto = photo;
    return _buildContent(photo, photos, index);
  }

  Widget _buildContent(Photo photo, List<Photo> photos, int currentIndex) {
    final imageAsync = ref.watch(viewerImageProvider(photo));

    // 缓存最新加载完成的图片路径
    if (imageAsync is AsyncData && imageAsync.value != null) {
      _previousImagePath = imageAsync.value;
      _maybePrefetchAdjacent(photo.id);
    }

    // 确保 PageView 显示当前照片页
    if (_needsPageJump) {
      _needsPageJump = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        if (_pageController.page?.round() != currentIndex) {
          _pageController.jumpToPage(currentIndex);
        }
      });
    }

    return Focus(
      autofocus: true,
      onKeyEvent: (focusNode, event) => _handleKeyEvent(event),
      child: Stack(
        children: [
          // PageView — 原生水平滑动切换照片
          PageView.builder(
            key: _viewerKey,
            controller: _pageController,
            physics: ZoomAwarePageScrollPhysics(
              isZoomed: () => _isZoomed,
            ),
            itemCount: photos.length,
            onPageChanged: (page) {
              if (_programmaticNavigation) return;
              _zoomAnimController.stop();
              final newPhotoId = photos[page].id;
              setState(() {
                _currentPhotoId = newPhotoId;
                _transformController.value = Matrix4.identity();
                _isZoomed = false;
              });
              // 联动：更新选中状态 → 网格和 InfoPanel 同步
              ref.read(selectionProvider.notifier).select(newPhotoId);
            },
            itemBuilder: (context, page) {
              final pagePhoto = photos[page];
              return PhotoPage(
                photo: pagePhoto,
                isCurrentPage: page == currentIndex,
                previousImagePath:
                    page == currentIndex ? _previousImagePath : null,
                transformController: _transformController,
                onDoubleTap: _toggleZoom,
                onTransformStart: _onTransformStart,
                onTransformEnd: _onTransformEnd,
              );
            },
          ),

          // 顶部信息栏
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ViewerTopBar(photo: photo),
          ),

          // 底部操作栏
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ViewerBottomBar(photo: photo),
          ),

          // 左右切换按钮
          if (photos.length > 1) ...[
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: NavButton(
                  icon: Icons.chevron_left,
                  onTap: () => _navigate(-1),
                ),
              ),
            ),
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: NavButton(
                  icon: Icons.chevron_right,
                  onTap: () => _navigate(1),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 键盘事件处理 — 预览模式快捷键
  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final catalogService = ref.read(catalogServiceProvider);

    // 方向键左 — 上一张
    if (key == LogicalKeyboardKey.arrowLeft) {
      _navigate(-1);
      return KeyEventResult.handled;
    }

    // 方向键右 — 下一张
    if (key == LogicalKeyboardKey.arrowRight) {
      _navigate(1);
      return KeyEventResult.handled;
    }

    // 数字键 0-5 — 评分
    if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.digit1 ||
        key == LogicalKeyboardKey.digit2 ||
        key == LogicalKeyboardKey.digit3 ||
        key == LogicalKeyboardKey.digit4 ||
        key == LogicalKeyboardKey.digit5) {
      final rating = key.keyId - LogicalKeyboardKey.digit0.keyId;
      if (_currentPhotoId != null) {
        catalogService.setRating(_currentPhotoId!, rating);
        ref.invalidate(photoByIdProvider(_currentPhotoId!));
        ref.invalidate(catalogProvider);
      }
      return KeyEventResult.handled;
    }

    // P — Pick
    if (key == LogicalKeyboardKey.keyP) {
      if (_currentPhotoId != null) {
        catalogService.setPickLabel(_currentPhotoId!, PickLabel.pick);
        ref.invalidate(photoByIdProvider(_currentPhotoId!));
        ref.invalidate(catalogProvider);
      }
      return KeyEventResult.handled;
    }

    // U — Unpick
    if (key == LogicalKeyboardKey.keyU) {
      if (_currentPhotoId != null) {
        catalogService.setPickLabel(_currentPhotoId!, PickLabel.none);
        ref.invalidate(photoByIdProvider(_currentPhotoId!));
        ref.invalidate(catalogProvider);
      }
      return KeyEventResult.handled;
    }

    // X — Reject
    if (key == LogicalKeyboardKey.keyX) {
      if (_currentPhotoId != null) {
        catalogService.setPickLabel(_currentPhotoId!, PickLabel.reject);
        ref.invalidate(photoByIdProvider(_currentPhotoId!));
        ref.invalidate(catalogProvider);
      }
      return KeyEventResult.handled;
    }

    // F1-F6 — 色标
    if (key == LogicalKeyboardKey.f1 ||
        key == LogicalKeyboardKey.f2 ||
        key == LogicalKeyboardKey.f3 ||
        key == LogicalKeyboardKey.f4 ||
        key == LogicalKeyboardKey.f5 ||
        key == LogicalKeyboardKey.f6) {
      final label = key.keyId - LogicalKeyboardKey.f1.keyId + 1;
      if (_currentPhotoId != null) {
        catalogService.setColorLabel(_currentPhotoId!, label);
        ref.invalidate(photoByIdProvider(_currentPhotoId!));
        ref.invalidate(catalogProvider);
      }
      return KeyEventResult.handled;
    }

    // F7 — 清除色标
    if (key == LogicalKeyboardKey.f7) {
      if (_currentPhotoId != null) {
        catalogService.setColorLabel(_currentPhotoId!, 0);
        ref.invalidate(photoByIdProvider(_currentPhotoId!));
        ref.invalidate(catalogProvider);
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _navigate(int direction) {
    final catalog = ref.read(catalogProvider);
    catalog.maybeWhen(
      data: (photos) {
        if (photos.isEmpty) return;
        final currentIndex =
            photos.indexWhere((p) => p.id == _currentPhotoId);
        if (currentIndex == -1) return;
        final newIndex =
            (currentIndex + direction).clamp(0, photos.length - 1);
        if (newIndex != currentIndex) {
          _programmaticNavigation = true;
          _pageController
              .animateToPage(
            newIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          )
              .then((_) {
            _programmaticNavigation = false;
            if (!mounted) return;
            _zoomAnimController.stop();
            setState(() {
              _currentPhotoId = photos[newIndex].id;
              _transformController.value = Matrix4.identity();
              _isZoomed = false;
            });
            // 联动：更新选中状态
            ref.read(selectionProvider.notifier).select(photos[newIndex].id);
          });
        }
      },
      orElse: () {},
    );
  }

  /// 预取相邻图片 — 避免重复预取同一张
  void _maybePrefetchAdjacent(int currentPhotoId) {
    if (_lastPrefetchedPhotoId == currentPhotoId) return;
    _lastPrefetchedPhotoId = currentPhotoId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _prefetchAdjacent();
    });
  }

  /// 预取相邻图片的解码结果和 ImageCache
  void _prefetchAdjacent() {
    final catalog = ref.read(catalogProvider);
    catalog.maybeWhen(
      data: (photos) {
        final currentIndex =
            photos.indexWhere((p) => p.id == _currentPhotoId);
        if (currentIndex == -1) return;

        for (final delta in [1, -1]) {
          final adjacentIndex = currentIndex + delta;
          if (adjacentIndex < 0 || adjacentIndex >= photos.length) continue;
          final adjacentPhoto = photos[adjacentIndex];

          ref
              .read(viewerImageProvider(adjacentPhoto).future)
              .then((imagePath) {
            if (imagePath == null || !mounted) return;
            precacheImage(
              FileImage(File(imagePath)),
              context,
            ).catchError((_) {});
          });
        }
      },
      orElse: () {},
    );
  }
}