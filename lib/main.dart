// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/logging.dart';
import 'data/database/app_database.dart';
import 'data/services/pointer_type_service.dart';
import 'providers/providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Suppress Windows accessibility bridge AXTree update errors ──
  // Flutter on Windows desktop may encounter "Failed to update ui::AXTree"
  // errors when PopupMenu/Tooltip widgets are dynamically created/destroyed
  // due to inconsistent accessibility tree node IDs.
  // This is a known Flutter issue (flutter/issues#118401) with no functional impact.
  // Disabling semantics eliminates this error for professional photo apps
  // that don't require screen readers. Users can re-enable via system
  // accessibility settings if needed.
  SystemChannels.accessibility.send({'enabled': false});

    // ── Flutter 图片缓存调优 ──
  // 默认 1000 张 / 100MB 对照片管理应用太小。
  // 网格 200 项 + 预览图轻松超限。设为 2000 张 / 500MB。
  // 注意：PaintingBinding 初始化后才能设置 cache 参数。
  // 此设置对所有 Image.file / Image.network / precacheImage 等生效。
  PaintingBinding.instance.imageCache.maximumSize = 2000;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 500 * 1024 * 1024;

  // ── Windows stylus/touch differentiation service ──
  // Receives WM_POINTER events from the C++ layer via EventChannel,
  // allowing the viewer to distinguish stylus from touch input:
  // stylus controls cropping, touch maintains gestures.
  // No-op on non-Windows platforms.
  PointerTypeService().initialize();

  // Note: do NOT use --enable-impeller runtime flag.
  // Impeller backend on Flutter 3.29 Windows is still unstable and causes black screen.
  // Default Skia + OpenGL backend works correctly with good performance.

  // Initialize window manager — configure window but defer show to avoid white screen
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1400, 900),
      minimumSize: Size(900, 600),
      center: true,
      title: 'Spectra',
      titleBarStyle: TitleBarStyle.normal,
    ),
    () async {
      // Don't show here; wait until database is ready to avoid showing an empty window
    },
  );

  // Initialize database in parallel (created in isolate, doesn't block UI thread)
  final database = await createAppDatabase();

  // 启动时修复所有文件夹的照片计数 — 纠正旧代码中的错误计数
  AppLogger.info('Startup', '修复文件夹照片计数...');
  try {
    await database.folderDao.repairAllPhotoCounts();
    AppLogger.info('Startup', '文件夹照片计数修复完成');
  } catch (e) {
    AppLogger.warn('Startup', '文件夹照片计数修复失败', details: e.toString());
  }

  // ── Safe window close handling ──
  // Intercept close signal to close the database before Dart VM shutdown,
  // preventing Drift's FinalizableDatabase finalizer from calling
  // sqlite3_close_v2 after FFI system shutdown, which would cause
  // "GetFfiCallbackMetadata called after shutdown" crash.
  windowManager.addListener(_DatabaseCloseHandler(database));
  await windowManager.setPreventClose(true);

  // Show window only after database is ready
  await windowManager.show();
  await windowManager.focus();

  runApp(
    // ExcludeSemantics globally suppresses Windows accessibility bridge AXTree errors.
    // SystemChannels.accessibility.send is already called above, but the engine may still
    // trigger "Failed to update ui::AXTree" errors. ExcludeSemantics prevents semantic tree
    // construction at the framework level, providing double protection.
    ExcludeSemantics(
      child: ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
        ],
        child: const SpectraApp(),
      ),
    ),
  );
}

/// Window close handler.
///
/// When the user closes the window (clicking X / Alt+F4), proactively closes
/// the database connection first, ensuring all SQLite resources are released
/// before the window is destroyed.
/// This prevents Drift's FinalizableDatabase finalizer in the background isolate
/// from calling sqlite3_close_v2 after the Dart VM FFI system has shut down.
class _DatabaseCloseHandler extends WindowListener {
  final AppDatabase database;

  _DatabaseCloseHandler(this.database);

  @override
  void onWindowClose() {
    // setPreventClose(true) has intercepted the close signal.
    // Trigger async database close here; window closes only after completion.
    _closeDatabaseThenWindow();
  }

  Future<void> _closeDatabaseThenWindow() async {
    try {
      await database.close();
    } catch (e) {
      debugPrint('Database close error: $e');
    }
    try {
      await windowManager.setPreventClose(false);
      await windowManager.close();
    } catch (e) {
      debugPrint('Window close error: $e');
    }
  }
}