import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/database/daos/photo_dao.dart';
import '../data/database/daos/tag_dao.dart';
import '../data/database/daos/folder_dao.dart';
import '../data/database/daos/settings_dao.dart';
import '../data/database/daos/edit_dao.dart';
import '../data/database/daos/edit_snapshot_dao.dart';
import '../data/database/daos/edit_history_dao.dart';
import '../data/services/catalog_service.dart';
import '../data/services/export_service.dart';
import '../data/services/file_system_service.dart';
import '../data/services/image_decoder_service.dart';
import '../data/services/image_edit_service.dart';
import '../data/services/import_service.dart';
import '../data/services/metadata_service.dart';
import '../data/services/tag_service.dart';
import '../data/services/thumbnail_service.dart';
import '../data/services/auto_adjust_service.dart';
import '../data/services/image_analysis.dart';
import '../data/services/ml_service.dart';
import '../data/services/model_download_service.dart';
import '../data/services/neural_auto_adjust_service.dart';
import '../data/services/super_resolution_service.dart';

// ─── 数据库 ───

/// 数据库实例 Provider（同步初始化，使用内存+延迟加载）
/// 在 main() 中通过 ProviderScope override 替换为实际数据库
final databaseProvider = Provider<AppDatabase>((ref) {
  // 默认使用内存数据库（测试用），生产环境在 main.dart 中 override
  final db = AppDatabase(NativeDatabase.memory());
  // close 在窗口关闭处理器中已调用，此处作为 fallback
  // 使用 try-catch 防止重复关闭时抛出异常
  ref.onDispose(() {
    try {
      db.close();
    } catch (_) {
      // 数据库可能已在窗口关闭时被主动关闭，忽略
    }
  });
  return db;
});

/// 异步数据库初始化 Provider — 在 main 中使用
Future<AppDatabase> createAppDatabase() async {
  return AppDatabase.create();
}

// ─── DAO ───

final photoDaoProvider = Provider<PhotoDao>((ref) {
  return ref.watch(databaseProvider).photoDao;
});

final tagDaoProvider = Provider<TagDao>((ref) {
  return ref.watch(databaseProvider).tagDao;
});

final folderDaoProvider = Provider<FolderDao>((ref) {
  return ref.watch(databaseProvider).folderDao;
});

final settingsDaoProvider = Provider<SettingsDao>((ref) {
  return ref.watch(databaseProvider).settingsDao;
});

final editDaoProvider = Provider<EditDao>((ref) {
  return ref.watch(databaseProvider).editDao;
});

final editSnapshotDaoProvider = Provider<EditSnapshotDao>((ref) {
  return ref.watch(databaseProvider).editSnapshotDao;
});

final editHistoryDaoProvider = Provider<EditHistoryDao>((ref) {
  return ref.watch(databaseProvider).editHistoryDao;
});

// ─── Service ───

final fileSystemServiceProvider = Provider<FileSystemService>((ref) {
  final service = FileSystemService();
  ref.onDispose(() => service.dispose());
  return service;
});

final metadataServiceProvider = Provider<MetadataService>((ref) {
  return MetadataService();
});

final imageDecoderServiceProvider = Provider<ImageDecoderService>((ref) {
  return ImageDecoderService();
});

final thumbnailServiceProvider = Provider<ThumbnailService>((ref) {
  return ThumbnailService(
    photoDao: ref.read(photoDaoProvider),
    imageDecoder: ref.read(imageDecoderServiceProvider),
  );
});

final catalogServiceProvider = Provider<CatalogService>((ref) {
  return CatalogService(photoDao: ref.read(photoDaoProvider));
});

final imageEditServiceProvider = Provider<ImageEditService>((ref) {
  return ImageEditService();
});

/// 图像分析服务 — 用于自动调整的统计特征提取
final imageAnalysisServiceProvider = Provider<ImageAnalysisService>((ref) {
  return ImageAnalysisService(ref.read(imageDecoderServiceProvider));
});

final autoAdjustServiceProvider = Provider<AutoAdjustService>((ref) {
  final neuralService = ref.read(neuralAutoAdjustServiceProvider);
  final analysisService = ref.read(imageAnalysisServiceProvider);
  return AutoAdjustService(
    neuralService: neuralService,
    analysisService: analysisService,
  );
});

/// ML 推理服务（ONNX Runtime）— 单例，懒加载
final mlServiceProvider = Provider<MlService>((ref) {
  final service = MlService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// 模型下载服务
final modelDownloadServiceProvider = Provider<ModelDownloadService>((ref) {
  final service = ModelDownloadService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// 神经网络自动调整服务
final neuralAutoAdjustServiceProvider = Provider<NeuralAutoAdjustService>((ref) {
  final mlService = ref.read(mlServiceProvider);
  final analysisService = ref.read(imageAnalysisServiceProvider);
  return NeuralAutoAdjustService(mlService, analysisService);
});

/// ML 模型状态 — 用于设置界面显示模型加载状态
final mlModelStatusProvider = StateProvider<MlModelStatus>((ref) {
  // 初始从 NeuralAutoAdjustService 读取，之后由 UI 手动刷新
  final neural = ref.read(neuralAutoAdjustServiceProvider);
  return neural.modelStatus;
});

/// ONNX Runtime 是否可用
final mlServiceAvailableProvider = Provider<bool>((ref) {
  return ref.read(mlServiceProvider).isAvailable;
});

/// 超分辨率模型状态
final superResolutionStatusProvider = Provider<MlModelStatus>((ref) {
  final sr = ref.read(superResolutionServiceProvider);
  return sr.modelStatus;
});

/// 超分辨率服务
final superResolutionServiceProvider = Provider<SuperResolutionService>((ref) {
  final mlService = ref.read(mlServiceProvider);
  return SuperResolutionService(mlService);
});

final exportServiceProvider = Provider<ExportService>((ref) {
  return ExportService();
});

final tagServiceProvider = Provider<TagService>((ref) {
  return TagService(tagDao: ref.read(tagDaoProvider));
});

final importServiceProvider = Provider<ImportService>((ref) {
  final service = ImportService(
    photoDao: ref.read(photoDaoProvider),
    folderDao: ref.read(folderDaoProvider),
    fileSystemService: ref.read(fileSystemServiceProvider),
    metadataService: ref.read(metadataServiceProvider),
    thumbnailService: ref.read(thumbnailServiceProvider),
  );
  // EXIF 后台写入数据库后递增刷新计数器
  // catalogProvider watch 此值，变化时自动重新查询
  // 使用 debounce 避免批量导入时每次 EXIF 写入都触发 catalog 重新查询
  // 导入 1000 张照片 = 1000 次 onExifUpdated，不加 debounce = 1000 次 DB 查询
  Timer? exifDebounce;
  service.onExifUpdated = (_) {
    exifDebounce?.cancel();
    exifDebounce = Timer(const Duration(milliseconds: 500), () {
      ref.read(exifRefreshTickProvider.notifier).state++;
    });
  };
  ref.onDispose(() {
    exifDebounce?.cancel();
    service.onExifUpdated = null;
  });

  // 启动时重试读取缺少 EXIF 的照片（fire-and-forget）
  // 处理上一次导入时 EXIF 读取未完成或失败的情况
  Future.microtask(() => service.retryMissingExif());

  return service;
});

/// EXIF 刷新计数器 — 每次 EXIF 后台写入后递增
/// catalogProvider watch 此值，变化时重新查询数据库
final exifRefreshTickProvider = StateProvider<int>((ref) => 0);

