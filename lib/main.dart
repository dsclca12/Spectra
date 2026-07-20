// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

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
  if (Platform.isWindows) {
    SystemChannels.accessibility.send({'enabled': false});
  }

  // ── Flutter 图片缓存调优 ──
  PaintingBinding.instance.imageCache.maximumSize = 2000;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 500 * 1024 * 1024;

  // ── 手写笔/触摸输入区分服务 ──
  // Windows: 从 C++ 层通过 EventChannel spnext/pointer_type 接收 WM_POINTER。
  // Linux: 无操作。
  // No-op on non-Windows platforms.
  PointerTypeService().initialize();

  // Note: do NOT use --enable-impeller runtime flag.

  // ── 窗口管理器 ──
  // window_manager 支持 Windows/Linux/macOS。
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1400, 900),
      minimumSize: Size(900, 600),
      center: true,
      title: 'Spectra',
      titleBarStyle: TitleBarStyle.normal,
    ),
    () async {},
  );

  // 初始化数据库
  final database = await createAppDatabase();

  // 启动时修复所有文件夹的照片计数
  AppLogger.info('Startup', '修复文件夹照片计数...');
  try {
    await database.folderDao.repairAllPhotoCounts();
    AppLogger.info('Startup', '文件夹照片计数修复完成');
  } catch (e) {
    AppLogger.warn('Startup', '文件夹照片计数修复失败', details: e.toString());
  }

  // ── Safe window close handling ──
  windowManager.addListener(_DatabaseCloseHandler(database));
  await windowManager.setPreventClose(true);

  // Show window only after database is ready
  await windowManager.show();
  await windowManager.focus();

  runApp(
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
class _DatabaseCloseHandler extends WindowListener {
  final AppDatabase database;

  _DatabaseCloseHandler(this.database);

  @override
  void onWindowClose() {
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