import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/enums.dart';
import '../../data/database/app_database.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/edit_provider.dart';
import '../../providers/providers.dart';
import '../../providers/viewer_image_provider.dart';
import '../components/photo_page.dart';
import '../components/draggable_divider.dart';
import '../components/editable_image_view.dart';
// ⚠️ Stylus crop temporarily disabled for debugging. Keeping import for recovery.
// import '../components/stylus_crop_overlay.dart';
import '../components/thumbnail_widget.dart';
import '../components/viewer_overlays.dart';
import '../components/zoom_aware_scroll_physics.dart';
import '../layout/panels/info_panel.dart';
import '../layout/panels/edit_panel.dart';

/// Full-screen photo viewer — ConsumerStatefulWidget manages internal photoId state.
/// Switches photos by updating state only (no Navigator), eliminating flicker and transitions.
class ViewerScreen extends ConsumerStatefulWidget {
  final int photoId;

  const ViewerScreen({super.key, required this.photoId});

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen>
    with TickerProviderStateMixin {
  late int _currentPhotoId;
  Photo? _previousPhoto;
  String? _previousImagePath;
  int? _lastPrefetchedPhotoId;

  /// Filmstrip height (draggable to resize).
  double _filmstripHeight = AppConstants.filmstripDefaultHeight;

  /// Left panel (info panel) width.
  double _leftPanelWidth = AppConstants.infoPanelDefaultWidth;

  /// Right panel (edit panel) width.
  double _rightPanelWidth = AppConstants.editPanelDefaultWidth;

  /// Whether left panel is visible.
  bool _leftPanelVisible = true;

  /// Whether right panel (edit panel) is visible.
  bool _rightPanelVisible = true;

  /// PageView controller — native swipe to switch photos.
  late PageController _pageController;

  /// InteractiveViewer controller — reset zoom on photo switch.
  final TransformationController _transformController =
      TransformationController();

  /// Current zoom state — used to disable PageView swipe.
  bool _isZoomed = false;

  /// Viewer area GlobalKey — get viewport size for zoom anchor calculation.
  final GlobalKey _viewerKey = GlobalKey();

  /// Double-tap zoom animation controller — smooth transition to avoid visual jumping.
  late AnimationController _zoomAnimController;

  /// Whether programmatic navigation (animateToPage) is in progress.
  /// Prevents setState in onPageChanged from conflicting with the animation.
  bool _programmaticNavigation = false;

  /// Whether jumpToPage is needed on next frame (first build or external photoId change).
  bool _needsPageJump = true;

  /// Check if the transform matrix is near identity — uses tolerance to avoid floating-point errors.
  ///
  /// When pinch-zoom returns to 1.0 on touch screens, the matrix almost never
  /// returns to exact identity (typically has 1.0000001 or tiny translation).
  /// Using `Matrix4.isIdentity()` for exact comparison would prevent `_isZoomed`
  /// from resetting, causing PageView swipe gestures to be captured by InteractiveViewer.
  bool _isNearIdentity() {
    final m = _transformController.value.storage;
    const tol = 0.01;
    // 2D transform (no rotation): scaleX, scaleY, skewX, skewY, translateX, translateY
    return (m[0] - 1).abs() < tol && // scaleX
        (m[5] - 1).abs() < tol && // scaleY
        m[1].abs() < tol && // skewY
        m[4].abs() < tol && // skewX
        m[12].abs() < tol && // translateX
        m[13].abs() < tol; // translateY
  }

  @override
  void initState() {
    super.initState();
    _currentPhotoId = widget.photoId;
    _pageController = PageController();
    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    // Listen to TransformationController changes — continuously sync _isZoomed.
    // InteractiveViewer's snap-back animation happens asynchronously after onInteractionEnd.
    // During snap-back, scale goes from 0.8→1.0, but onInteractionEnd fires only once
    // before the animation starts. Without continuous listening, _isZoomed stays true
    // after snap-back completes, locking the PageView.
    _transformController.addListener(_onTransformControllerChanged);
  }

  @override
  void didUpdateWidget(covariant ViewerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When external photoId changes, mark jumpToPage as needed.
    if (widget.photoId != oldWidget.photoId &&
        widget.photoId != _currentPhotoId) {
      _currentPhotoId = widget.photoId;
      _needsPageJump = true;
    }
  }

  @override
  void dispose() {
    // Auto-save current photo edits when viewer closes.
    // Fire-and-forget — saveOnClose internally checks isDirty and settings.
    ref.read(editSessionProvider(_currentPhotoId).notifier).saveOnClose();

    _transformController.removeListener(_onTransformControllerChanged);
    _zoomAnimController.dispose();
    _pageController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  /// Double-tap to toggle zoom — smooth animation between 1x and 2x.
  ///
  /// Zoom anchor is the viewport center to avoid jumping to top-left corner.
  /// Uses AnimationController driving Matrix4Tween for smooth transition.
  void _toggleZoom() {
    _zoomAnimController.stop();

    final wasZoomed = !_isNearIdentity();
    final renderBox =
        _viewerKey.currentContext?.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? MediaQuery.sizeOf(context);
    final center = Offset(size.width / 2, size.height / 2);

    final Matrix4 target;
    if (!wasZoomed) {
      // Zoom to 2x anchored at viewport center
      // T(c) · S(2) · T(-c): translate center to origin → scale → translate back
      target = Matrix4.identity()
        ..translateByDouble(-center.dx, -center.dy, 0, 1)
        ..scaleByDouble(2.0, 2.0, 1.0, 1.0)
        ..translateByDouble(center.dx, center.dy, 0, 1);
    } else {
      target = Matrix4.identity();
    }

    _animateTransformTo(target);
  }

  /// Smoothly animate to a target transform matrix.
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

  /// TransformationController change listener — continuously syncs _isZoomed.
  ///
  /// InteractiveViewer's snap-back animation runs asynchronously after onInteractionEnd.
  /// During snap-back, scale goes from 0.8→1.0. If _isZoomed is only updated in
  /// onInteractionEnd, it stays true after snap-back, locking the PageView.
  /// This listener syncs _isZoomed on every matrix change (including snap-back frames).
  void _onTransformControllerChanged() {
    _isZoomed = !_isNearIdentity();
  }

  /// InteractiveViewer gesture start — stops animation.
  ///
  /// `_isZoomed` is automatically synced by `_onTransformControllerChanged`.
  void _onTransformStart(ScaleStartDetails details) {
    _zoomAnimController.stop();
  }

  /// InteractiveViewer gesture end.
  ///
  /// `_isZoomed` is automatically synced by `_onTransformControllerChanged`.
  void _onTransformEnd(ScaleEndDetails details) {}

  @override
  Widget build(BuildContext context) {
    // Use catalogProvider's photo list directly — avoids photoByIdProvider DB queries.
    // Catalog data is already loaded and cached in the main screen, providing
    // zero-latency synchronous Photo object access on switch.
    final catalogAsync = ref.watch(catalogProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildBody(catalogAsync),
    );
  }

  /// Build body — finds current photo from catalog list, uses previous photo as fallback to prevent flicker.
  Widget _buildBody(AsyncValue<List<Photo>> catalogAsync) {
    // Error state
    if (catalogAsync is AsyncError) {
      return Center(
        child: Text('加载失败: ${catalogAsync.error}',
            style: const TextStyle(color: Colors.white)),
      );
    }

    final photos = catalogAsync.valueOrNull;

    // Use previous photo while catalog is loading or empty.
    if (photos == null || photos.isEmpty) {
      if (_previousPhoto != null) {
        return _buildContent(_previousPhoto!, const [], 0);
      }
      return const Center(child: CircularProgressIndicator());
    }

    // Find current photo from list — synchronous, no DB query latency.
    final index = photos.indexWhere((p) => p.id == _currentPhotoId);
    if (index < 0) {
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
    // Use viewerImageProvider to get the displayable image path.
    final imageAsync = ref.watch(viewerImageProvider(photo));

    // Cache the latest loaded image path (only in AsyncData to avoid build-side-effect issues).
    if (imageAsync is AsyncData && imageAsync.value != null) {
      _previousImagePath = imageAsync.value;
      // Prefetch adjacent images after current one loads — eliminates switch latency.
      _maybePrefetchAdjacent(photo.id);
    }

    // Ensure PageView shows the current photo page — jumps only on first build
    // or external photoId change, not during swipe/animation to avoid interruptions.
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
      child: Column(
        children: [
          // Top: three-column layout — left info | center image | right edit
          Expanded(
            child: Row(
              children: [
                // Left column: photo info panel
                if (_leftPanelVisible) ...[
                  SizedBox(
                    width: _leftPanelWidth,
                    child: InfoPanel(
                      photoId: _currentPhotoId,
                      showPreview: false,
                    ),
                  ),
                  _verticalDivider(context),
                ],
                // Center column: image viewer area
                Expanded(
                  child: Container(
                    key: _viewerKey,
                    color: Colors.black,
                    child: Stack(
                      children: [
                        // PageView — native horizontal swipe to switch photos.
                        // Uses ZoomAwarePageScrollPhysics closure to dynamically
                  // reject page turns when zoomed, avoiding rebuild flicker from physics swaps.
                  PageView.builder(
                    controller: _pageController,
                    physics: ZoomAwarePageScrollPhysics(
                      isZoomed: () => _isZoomed,
                    ),
                    itemCount: photos.length,
                    onPageChanged: (page) {
                      // _navigate handles state update during programmatic navigation.
                      if (_programmaticNavigation) return;
                      // Auto-save current photo edits before switching.
                      ref.read(editSessionProvider(_currentPhotoId).notifier)
                          .saveOnSwitch();
                      _zoomAnimController.stop();
                      setState(() {
                        _currentPhotoId = photos[page].id;
                        // Reset zoom on photo switch.
                        _transformController.value = Matrix4.identity();
                        _isZoomed = false;
                      });
                    },
                    itemBuilder: (context, page) {
                      final pagePhoto = photos[page];
                      return _EditablePhotoPage(
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

                  // Stylus crop overlay — only shown on current page when image size is known.
                  // Draw diagonal line with stylus to create crop box, then drag 8 handles to adjust.
                  // Touch input passes through to underlying PageView/InteractiveViewer.
                  //
                  // ⚠️ Temporarily disabled: stylus trigger unavailable, debugging needed.
                  // Positioned.fill(
                  //   child: _buildStylusCropLayer(photo),
                  // ),

                  // Top info bar — translucent to allow swipe gestures through to PageView.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: ViewerTopBar(
                      photo: photo,
                      onClose: () => Navigator.of(context).pop(),
                      onToggleLeftPanel: () => setState(() =>
                          _leftPanelVisible = !_leftPanelVisible),
                      onToggleRightPanel: () => setState(() =>
                          _rightPanelVisible = !_rightPanelVisible),
                      leftPanelVisible: _leftPanelVisible,
                      rightPanelVisible: _rightPanelVisible,
                    ),
                  ),

                  // Bottom action bar — translucent to allow swipe gestures through to PageView.
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: ViewerBottomBar(photo: photo),
                  ),

                  // Left/right navigation buttons — large touch targets, touch-friendly.
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
              ),
            ),
          ),
                // Right column: edit panel
                if (_rightPanelVisible) ...[
                  _verticalDivider(context),
                  SizedBox(
                    width: _rightPanelWidth,
                    child: EditPanel(photoId: _currentPhotoId),
                  ),
                ],
              ],
            ),
          ),
          // Bottom: filmstrip (height is draggable)
          DraggableDivider(
            isHorizontal: true,
            onDrag: (delta) {
              setState(() {
                _filmstripHeight =
                    (_filmstripHeight - delta).clamp(
                      AppConstants.filmstripMinHeight,
                      AppConstants.filmstripMaxHeight,
                    );
              });
            },
          ),
          SizedBox(
            height: _filmstripHeight,
            child: _ViewerFilmstrip(
              photos: photos,
              currentPhotoId: _currentPhotoId,
              onTap: (photoId) {
                final index = photos.indexWhere((p) => p.id == photoId);
                if (index < 0) return;
                _programmaticNavigation = true;
                _pageController
                    .animateToPage(
                  index,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                )
                    .then((_) {
                  _programmaticNavigation = false;
                  if (!mounted) return;
                  _zoomAnimController.stop();
                  setState(() {
                    _currentPhotoId = photoId;
                    _transformController.value = Matrix4.identity();
                    _isZoomed = false;
                  });
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider(BuildContext context) {
    return VerticalDivider(
      width: 1,
      thickness: 0.5,
      color: Theme.of(context).dividerColor,
    );
  }

  /// Build stylus crop overlay.
  ///
  /// Only shown when ALL conditions are met:
  /// - Current photo has valid original dimensions (width/height non-null and > 0)
  /// - Not zoomed (_isZoomed is false) — zoomed state distorts crop coordinate
  ///   calculations and conflicts with InteractiveViewer gestures
  /// - Current photo has an edit session
  ///
  /// Touch input passes through StylusCropOverlay to the underlying PageView,
  /// stylus input draws diagonal lines to create crop boxes + drag 8 handles to adjust.
  //
  // ⚠️ Temporarily disabled: stylus trigger unavailable, debugging needed. Code preserved for recovery.
  // Widget _buildStylusCropLayer(Photo photo) {
  //   final imageW = photo.width;
  //   final imageH = photo.height;
  //   if (imageW == null || imageH == null || imageW <= 0 || imageH <= 0) {
  //     return const SizedBox.shrink();
  //   }
  //   if (_isZoomed) return const SizedBox.shrink();
  //
  //   return _StylusCropLayer(photo: photo);
  // }

  /// Keyboard event handler — shortcuts within the full-screen viewer.
  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final catalogService = ref.read(catalogServiceProvider);

    // Esc — exit viewer
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }

    // Arrow left — previous photo
    if (key == LogicalKeyboardKey.arrowLeft) {
      _navigate(-1);
      return KeyEventResult.handled;
    }

    // Arrow right — next photo
    if (key == LogicalKeyboardKey.arrowRight) {
      _navigate(1);
      return KeyEventResult.handled;
    }

    // Digit keys 0-5 — rating
    if (key == LogicalKeyboardKey.digit0 ||
        key == LogicalKeyboardKey.digit1 ||
        key == LogicalKeyboardKey.digit2 ||
        key == LogicalKeyboardKey.digit3 ||
        key == LogicalKeyboardKey.digit4 ||
        key == LogicalKeyboardKey.digit5) {
      final rating = key.keyId - LogicalKeyboardKey.digit0.keyId;
      catalogService.setRating(_currentPhotoId, rating);
      ref.invalidate(photoByIdProvider(_currentPhotoId));
      ref.invalidate(catalogProvider);
      return KeyEventResult.handled;
    }

    // P — Pick
    if (key == LogicalKeyboardKey.keyP) {
      catalogService.setPickLabel(_currentPhotoId, PickLabel.pick);
      ref.invalidate(photoByIdProvider(_currentPhotoId));
      ref.invalidate(catalogProvider);
      return KeyEventResult.handled;
    }

    // U — Unpick
    if (key == LogicalKeyboardKey.keyU) {
      catalogService.setPickLabel(_currentPhotoId, PickLabel.none);
      ref.invalidate(photoByIdProvider(_currentPhotoId));
      ref.invalidate(catalogProvider);
      return KeyEventResult.handled;
    }

    // X — Reject
    if (key == LogicalKeyboardKey.keyX) {
      catalogService.setPickLabel(_currentPhotoId, PickLabel.reject);
      ref.invalidate(photoByIdProvider(_currentPhotoId));
      ref.invalidate(catalogProvider);
      return KeyEventResult.handled;
    }

    // F1-F6 — color label
    if (key == LogicalKeyboardKey.f1 ||
        key == LogicalKeyboardKey.f2 ||
        key == LogicalKeyboardKey.f3 ||
        key == LogicalKeyboardKey.f4 ||
        key == LogicalKeyboardKey.f5 ||
        key == LogicalKeyboardKey.f6) {
      final label = key.keyId - LogicalKeyboardKey.f1.keyId + 1;
      catalogService.setColorLabel(_currentPhotoId, label);
      ref.invalidate(photoByIdProvider(_currentPhotoId));
      ref.invalidate(catalogProvider);
      return KeyEventResult.handled;
    }

    // F7 — clear color label
    if (key == LogicalKeyboardKey.f7) {
      catalogService.setColorLabel(_currentPhotoId, 0);
      ref.invalidate(photoByIdProvider(_currentPhotoId));
      ref.invalidate(catalogProvider);
      return KeyEventResult.handled;
    }

    // Tab — toggle right panel (edit panel) visibility
    if (key == LogicalKeyboardKey.tab) {
      setState(() => _rightPanelVisible = !_rightPanelVisible);
      return KeyEventResult.handled;
    }

    // Ctrl+Z — undo edit
    if (HardwareKeyboard.instance.isControlPressed &&
        key == LogicalKeyboardKey.keyZ) {
      ref.read(editSessionProvider(_currentPhotoId).notifier).undo();
      return KeyEventResult.handled;
    }

    // Ctrl+Y or Ctrl+Shift+Z — redo edit
    if (HardwareKeyboard.instance.isControlPressed &&
        (key == LogicalKeyboardKey.keyY ||
            (HardwareKeyboard.instance.isShiftPressed &&
                key == LogicalKeyboardKey.keyZ))) {
      ref.read(editSessionProvider(_currentPhotoId).notifier).redo();
      return KeyEventResult.handled;
    }

    // Ctrl+S — save edit
    if (HardwareKeyboard.instance.isControlPressed &&
        key == LogicalKeyboardKey.keyS) {
      ref.read(editSessionProvider(_currentPhotoId).notifier).save();
      return KeyEventResult.handled;
    }

    // R — reset edit (without Ctrl)
    if (!HardwareKeyboard.instance.isControlPressed &&
        key == LogicalKeyboardKey.keyR) {
      ref.read(editSessionProvider(_currentPhotoId).notifier).reset();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _navigate(int direction) {
    // Auto-save current photo edits before switching
    ref.read(editSessionProvider(_currentPhotoId).notifier).saveOnSwitch();

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
          // Mark programmatic navigation to suppress setState in onPageChanged
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
          });
        }
      },
      orElse: () {},
    );
  }

  /// Prefetch adjacent images — avoids redundant prefetches.
  void _maybePrefetchAdjacent(int currentPhotoId) {
    if (_lastPrefetchedPhotoId == currentPhotoId) return;
    _lastPrefetchedPhotoId = currentPhotoId;

    // Defer to next frame — don't block current image rendering
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _prefetchAdjacent();
    });
  }

  /// Prefetch decoded results and ImageCache for adjacent images.
  ///
  /// After the current image is displayed, preload the next and previous images:
  /// - RAW/HEIC/AVIF/TIFF: triggers WIC decoding, writes PNG preview to disk cache
  /// - Standard formats: precacheImage pre-decodes FileImage into Flutter ImageCache
  ///
  /// Zero-latency cache hit on photo switch.
  void _prefetchAdjacent() {
    final catalog = ref.read(catalogProvider);
    catalog.maybeWhen(
      data: (photos) {
        final currentIndex =
            photos.indexWhere((p) => p.id == _currentPhotoId);
        if (currentIndex == -1) return;

        // Prefetch one in each direction
        for (final delta in [1, -1]) {
          final adjacentIndex = currentIndex + delta;
          if (adjacentIndex < 0 || adjacentIndex >= photos.length) continue;
          final adjacentPhoto = photos[adjacentIndex];

          // Prefetch viewerImageProvider — triggers RAW/HEIC WIC decoding
          ref
              .read(viewerImageProvider(adjacentPhoto).future)
              .then((imagePath) {
            if (imagePath == null || !mounted) return;
            // Pre-cache into Flutter ImageCache — direct hit on switch
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

/// Full-screen viewer bottom filmstrip — horizontal thumbnail list linked with PageView.
///
/// Click thumbnail → animateToPage jump; PageView swipe → highlight current item and auto-scroll.
class _ViewerFilmstrip extends StatefulWidget {
  final List<Photo> photos;
  final int currentPhotoId;
  final ValueChanged<int> onTap;

  const _ViewerFilmstrip({
    required this.photos,
    required this.currentPhotoId,
    required this.onTap,
  });

  @override
  State<_ViewerFilmstrip> createState() => _ViewerFilmstripState();
}

class _ViewerFilmstripState extends State<_ViewerFilmstrip> {
  final ScrollController _scrollController = ScrollController();
  static const double _itemWidth = 128 + 8;
  int? _lastHighlightedId;

  @override
  void didUpdateWidget(covariant _ViewerFilmstrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll to current item when currentPhotoId changes
    if (widget.currentPhotoId != _lastHighlightedId) {
      _lastHighlightedId = widget.currentPhotoId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final index =
            widget.photos.indexWhere((p) => p.id == widget.currentPhotoId);
        if (index < 0) return;
        _scrollToIndex(index, _scrollController.position.viewportDimension);
      });
    }
  }

  void _scrollToIndex(int index, double viewportWidth) {
    final offset = index * _itemWidth;
    final currentOffset = _scrollController.offset;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final visibleEnd = currentOffset + viewportWidth;

    if (offset >= currentOffset && offset + _itemWidth <= visibleEnd) return;

    double targetOffset = offset - (viewportWidth - _itemWidth) / 2;
    targetOffset = targetOffset.clamp(0.0, maxScroll);

    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.canvasColor,
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Title bar
          Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            child: Text(
              '胶片条 · ${widget.photos.length} 张',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Divider(height: 1, color: theme.dividerColor),
          // 水平缩略图列表
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: widget.photos.length,
              itemExtent: _itemWidth,
              itemBuilder: (context, index) {
                final photo = widget.photos[index];
                final isSelected = photo.id == widget.currentPhotoId;

                return GestureDetector(
                  onTap: () => widget.onTap(photo.id),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: theme.dividerColor.withValues(alpha: 0.4),
                          width: 1,
                        ),
                      ),
                      color: isSelected
                          ? theme.colorScheme.primary.withValues(alpha: 0.08)
                          : Colors.transparent,
                    ),
                    child: Stack(
                      children: [
                        // 选中高亮边框
                        if (isSelected)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: theme.colorScheme.primary,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          ),
                        // 缩略图
                        Padding(
                          padding: const EdgeInsets.all(2),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: ThumbnailWidget(
                              photoId: photo.id,
                              filePath: photo.path,
                              size: AppConstants.thumbnailSmall,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        // 星级 — 数字徽章
                        if (photo.rating > 0)
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFB900),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                '${photo.rating}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 可编辑照片页 — 包装 EditableImageView，集成编辑参数实时预览
///
/// 替代原 PhotoPage，在 PageView 的每个页面中显示带编辑效果的图片。
/// 当前页通过 editSessionProvider 获取编辑参数，非当前页使用默认参数。
class _EditablePhotoPage extends ConsumerWidget {
  final Photo photo;
  final bool isCurrentPage;
  final String? previousImagePath;
  final TransformationController transformController;
  final VoidCallback? onDoubleTap;
  final void Function(ScaleStartDetails)? onTransformStart;
  final void Function(ScaleEndDetails)? onTransformEnd;

  const _EditablePhotoPage({
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

    // 当前页从 editSessionProvider 获取编辑参数
    // 非当前页使用默认参数（无编辑效果）
    // 若正在预览历史节点，使用 previewParams 显示该历史状态
    final editParams = isCurrentPage
        ? ref.watch(editSessionProvider(photo.id)).previewParams
        : null;

    Widget pageContent = RepaintBoundary(
      child: editParams != null
          ? EditableImageView(
              imagePath: imagePath,
              params: editParams,
              isCurrentPage: isCurrentPage,
              transformController: transformController,
              onDoubleTap: onDoubleTap,
              onTransformStart: onTransformStart,
              onTransformEnd: onTransformEnd,
            )
          : PhotoPage(
              photo: photo,
              isCurrentPage: isCurrentPage,
              previousImagePath: previousImagePath,
              transformController: transformController,
              onDoubleTap: onDoubleTap,
              onTransformStart: onTransformStart,
              onTransformEnd: onTransformEnd,
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
}

/// 手写笔裁剪叠加层 — 独立 ConsumerWidget，watch 当前照片的编辑会话，
/// 让裁剪参数变化时仅本层 rebuild，不影响 PageView/InteractiveViewer。
//
// ⚠️ 暂时禁用：手写笔触发不可用，待调试。保留代码以便后续恢复。
// class _StylusCropLayer extends ConsumerWidget {
//   final Photo photo;
//
//   const _StylusCropLayer({required this.photo});
//
//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final session = ref.watch(editSessionProvider(photo.id));
//     final imageW = photo.width;
//     final imageH = photo.height;
//     if (imageW == null || imageH == null || imageW <= 0 || imageH <= 0) {
//       return const SizedBox.shrink();
//     }
//
//     return StylusCropOverlay(
//       imageWidth: imageW,
//       imageHeight: imageH,
//       params: session.params,
//       onChanged: (newParams) {
//         ref
//             .read(editSessionProvider(photo.id).notifier)
//             .replaceParams(newParams, actionLabel: '手写笔裁剪');
//       },
//     );
//   }
// }

