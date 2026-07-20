/// Centralized UI string constants for Spectra.
///
/// All user-facing strings should be defined here to facilitate
/// future internationalization (i18n) and to keep the UI layer
/// free of hardcoded text.
///
/// Default language: English.
///
/// Migration guide:
///   When adding a new string, add it here first, then reference
///   `AppStrings.xxx` from the UI code. When migrating to Flutter
///   `intl` / ARB later, these constants map directly to localized keys.
library;

/// All user-facing strings for the Spectra application.
class AppStrings {
  AppStrings._();

  // ─── App ───
  static const String appName = 'Spectra';
  // 与 pubspec.yaml / version.json / constants.dart 保持同步
  // 发布前使用 scripts/build.ps1 统一更新所有版本号
  static const String appVersion = '0.4.5';
  static const String appDescription =
      'Photo categorization & asset management for professional photographers on Windows';
  static const String appLicense = 'Apache 2.0';
  static const String appFramework = 'Flutter 3.29+ / Drift / Riverpod';

  // ─── Menu Bar ───
  static const String menuFile = 'File';
  static const String menuEdit = 'Edit';
  static const String menuView = 'View';
  static const String menuTags = 'Tags';
  static const String menuTools = 'Tools';
  static const String menuHelp = 'Help';

  static const String menuImportFolder = 'Import Folder...';
  static const String menuExport = 'Export Photos...';
  static const String menuExit = 'Exit';
  static const String menuUndo = 'Undo';
  static const String menuRedo = 'Redo';
  static const String menuSelectAll = 'Select All';
  static const String menuGridView = 'Grid View';
  static const String menuListView = 'List View';
  static const String menuPreview = 'Preview';
  static const String menuZoomIn = 'Zoom In';
  static const String menuZoomOut = 'Zoom Out';
  static const String menuToggleLeftPanel = 'Toggle Left Panel';
  static const String menuToggleRightPanel = 'Toggle Right Panel';
  static const String menuToggleFilmstrip = 'Toggle Filmstrip';
  static const String menuManageTags = 'Manage Tags...';
  static const String menuSettings = 'Settings...';
  static const String menuAbout = 'About Spectra';

  // ─── Settings Screen ───
  static const String settingsTitle = 'Settings';
  static const String settingsResetAll = 'Reset All';
  static const String settingsAppearance = 'Appearance';
  static const String settingsAppearanceSub = 'Theme, colors & panel layout';
  static const String settingsThumbnails = 'Thumbnails & Quality';
  static const String settingsThumbnailsSub = '';
  static const String settingsImport = 'Import';
  static const String settingsImportSub = 'Import behavior, file watching & concurrency';
  static const String settingsSearch = 'Search';
  static const String settingsSearchSub = 'Search scope & debounce delay';
  static const String settingsBrowse = 'Browse';
  static const String settingsBrowseSub = 'Default view & sort order';
  static const String settingsPerformance = 'Performance';
  static const String settingsPerformanceSub = 'Memory cache & page size';
  static const String settingsEditing = 'Editing';
  static const String settingsEditingSub = 'Auto-save, edit history & auto-adjust';
  static const String settingsShortcuts = 'Shortcuts';
  static const String settingsShortcutsSub = '';
  static const String settingsAbout = 'About';
  static const String settingsAboutSub = 'Application info';

  static const String settingsResetConfirmTitle = 'Reset All Settings';
  static const String settingsResetConfirmMsg =
      'Are you sure you want to reset all settings to their defaults? This action cannot be undone.';
  static const String settingsCancel = 'Cancel';
  static const String settingsReset = 'Reset';

  static const String settingsAppInfo = 'Application Info';
  static const String settingsLabelName = 'Name';
  static const String settingsLabelVersion = 'Version';
  static const String settingsLabelDescription = 'Description';
  static const String settingsLabelLicense = 'License';
  static const String settingsLabelFramework = 'Framework';

  // ─── Import ───
  static const String importScanning = 'Scanning...';
  static const String importImporting = 'Importing...';
  static const String importCompleted = 'Import completed';
  static const String importError = 'Import failed';

  // ─── Status Bar ───
  static const String statusSelected = 'selected';
  static const String statusTotal = 'Total';
  static const String statusReady = 'Ready';

  // ─── Dialog Buttons ───
  static const String ok = 'OK';
  static const String cancel = 'Cancel';
  static const String confirm = 'Confirm';

  // ─── Shortcut Editor ───
  static const String shortcutSetFor = 'Set shortcut:';
  static const String shortcutPressKeys = 'Press the key combination to bind';
  static const String shortcutWaiting = 'Waiting for keys...';


}
