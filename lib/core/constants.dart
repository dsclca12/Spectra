// SPDX-License-Identifier: Apache-2.0

/// Feature flags — compile-time constants to disable certain features.
///
/// Unlike runtime flags, these are `const` so the Dart compiler
/// can tree-shake dead code for unused features.
class FeatureFlags {
  FeatureFlags._();

  /// Auto-adjust features (neural enhancement engine).
  static const bool aiMlEnabled = false;

  /// Super-resolution feature
  static const bool superResolutionEnabled = false;
}

/// Application core constants.
class AppConstants {
  AppConstants._();

  /// Application name.
  static const String appName = 'Spectra';

  /// Application version.
  static const String appVersion = '0.1.0';

  /// Supported image file extensions (lowercase, no dot).
  ///
  /// Standard formats are handled by Flutter's native decoder (dart:ui / Skia);
  /// RAW/HEIC/AVIF/TIFF are decoded via Windows WIC (requires corresponding codec pack).
  static const Set<String> supportedImageExtensions = {
    // ─── Standard formats (native dart:ui support) ───
    'jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif', 'wbmp',

    // ─── HEIC / HEIF / AVIF (requires WIC + HEIF codec pack) ───
    'heic', 'heif', 'hif', 'avif',

    // ─── TIFF (requires WIC) ───
    'tif', 'tiff',

    // ─── Canon RAW ───
    'cr2', 'cr3', 'crw',
    // ─── Nikon RAW ───
    'nef', 'nrw',
    // ─── Sony RAW ───
    'arw', 'sr2', 'srf',
    // ─── Adobe DNG ───
    'dng',
    // ─── Fujifilm RAW ───
    'raf',
    // ─── Panasonic RAW ───
    'rw2', 'raw',
    // ─── Olympus RAW ───
    'orf',
    // ─── Pentax RAW ───
    'pef',
    // ─── Samsung RAW ───
    'srw',
    // ─── Minolta RAW ───
    'mrw',
    // ─── Sigma RAW ───
    'x3f',
    // ─── Hasselblad RAW ───
    '3fr', 'fff',
    // ─── Phase One / Leaf RAW ───
    'iiq', 'mos',
    // ─── Leica RAW ───
    'rwl',
    // ─── Kodak RAW ───
    'kdc', 'dcr',
    // ─── Red RAW ───
    'r3d',
  };

  /// Thumbnail size tiers.
  static const int thumbnailSmall = 128;
  static const int thumbnailMedium = 512;
  static const int previewMaxSize = 1024;

  /// Thumbnail cache directory name.
  static const String thumbnailCacheDir = 'thumbnails';

  /// Database file name.
  static const String databaseFileName = 'spectra.db';

  /// Default page size for paginated queries.
  static const int defaultPageSize = 200;

  /// Maximum file size (500MB). Files larger than this are ignored.
  static const int maxFileSizeBytes = 500 * 1024 * 1024;

  /// Maximum thumbnail cache size (5GB).
  static const int maxCacheSizeBytes = 5 * 1024 * 1024 * 1024;

  /// Search debounce duration.
  static const Duration searchDebounce = Duration(milliseconds: 300);

  /// Panel dimensions.
  static const double leftPanelDefaultWidth = 200;
  static const double leftPanelMinWidth = 150;
  static const double leftPanelMaxWidth = 400;

  static const double rightPanelDefaultWidth = 280;
  static const double rightPanelMinWidth = 220;
  static const double rightPanelMaxWidth = 500;

  /// Edit panel size (viewer right panel).
  static const double editPanelDefaultWidth = 320;
  static const double editPanelMinWidth = 260;
  static const double editPanelMaxWidth = 480;

  /// Info panel size (viewer left panel).
  static const double infoPanelDefaultWidth = 280;
  static const double infoPanelMinWidth = 200;
  static const double infoPanelMaxWidth = 450;

  /// Filmstrip size.
  static const double filmstripDefaultHeight = 180;
  static const double filmstripMinHeight = 100;
  static const double filmstripMaxHeight = 400;

  /// Preset thumbnail sizes.
  static const double thumbSizeSmall = 120;
  static const double thumbSizeMedium = 180;
  static const double thumbSizeLarge = 260;
}