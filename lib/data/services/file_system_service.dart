import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../../core/constants.dart';
import '../../core/errors.dart';

/// 文件系统服务 — 负责文件遍历、监听和增量扫描
///
/// ⚡ 性能策略：
/// - 单次遍历不预统计：避免整个文件夹遍历两遍（见 scanDirectory）
/// - 异步目录遍历：使用 dir.list() 替代 listSync()，避免阻塞事件循环
/// - 手动递归替代 recursive=true：单目录 FileSystemException 不影响其他目录
/// - stat 结果随事件传递（_FileEntry），避免调用方二次 stat
/// - 跳过已知 Windows 系统目录（回收站/系统卷信息等），避免权限异常
class FileSystemService {
  FileSystemService();

    /// 递归扫描文件夹中的所有图片文件
  ///
  /// ⚡ 性能说明：
  /// - 单次遍历，不预统计 total — 预统计会导致整个文件夹被遍历两遍，
  ///   对于包含数万文件的摄影文件夹耗时加倍。
  /// - stat 结果随事件传递（_FileEntry），避免调用方二次 stat。
  /// - 手动递归遍历替代 dir.list(recursive: true)：Windows 上 Dart 的
  ///   递归遍历遇到无权限目录（System Volume Information 等）会抛出
  ///   FileSystemException 并终止整个流。手动递归单目录失败不影响其他。
  /// - 异步 dir.list() 替代同步 dir.listSync()：大型目录树扫描时避免
  ///   阻塞事件循环数百毫秒，UI 保持响应。
  ///
  /// [onProgress] 回调用于报告扫描进度（total 在扫描完成后才确定）
  Stream<ScanEvent> scanDirectory(
    String dirPath, {
    bool recursive = true,
    void Function(int scanned, int? total)? onProgress,
  }) async* {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      throw FileSystemAppException('文件夹不存在', detail: dirPath);
    }

    // 单次遍历，不预统计 — 预统计会导致整个文件夹被遍历两遍
    int scanned = 0;
    await for (final entry in _listImageFilesWithStat(dir, recursive)) {
      scanned++;
      // total 未知时传 null，避免双重遍历
      onProgress?.call(scanned, null);
      yield ScanEvent(
        type: ScanEventType.fileFound,
        path: entry.file.path,
        fileStat: entry.stat,
      );
    }

    yield ScanEvent(
      type: ScanEventType.completed,
      path: dirPath,
      fileStat: null,
      totalFiles: scanned,
    );
  }

  /// 列出文件夹中的所有图片文件（带 stat，避免重复调用）
  ///
  /// 使用手动递归遍历替代 `dir.list(recursive: true)`，原因：
  /// Windows 上 `Directory.list(recursive: true)` 底层用 FindFirstFile/
  /// FindNextFile 递归遍历，遇到无权限访问的子目录（如 System Volume
  /// Information、$Recycle.Bin 等系统目录）时，Dart 的 dart:io 会抛出
  /// FileSystemException 并终止整个流 — 导致该目录之后的所有文件被跳过。
  ///
  /// 手动递归逐目录遍历，单目录失败不影响其他目录。
  Stream<_FileEntry> _listImageFilesWithStat(Directory dir, bool recursive) async* {
    if (recursive) {
      yield* _walkDirectory(dir);
    } else {
      yield* _listFilesInDirectory(dir);
    }
  }

  /// 递归遍历目录树 — 逐目录处理，单目录失败不中断整体扫描
  /// 递归遍历目录树 — 逐目录异步遍历，单目录失败不中断整体扫描。
  ///
  /// ⚡ 性能说明：
  /// - 使用异步 `dir.list()` 替代同步 `dir.listSync()`，避免阻塞事件循环。
  /// - 带数万子目录的大型摄影库（如按年月日分层）扫描时，同步 listSync 会
  ///   数百毫秒阻塞 UI 线程。异步 list 让 UI 渲染和其他事件得以正常处理。
  /// - 每次 yield 后事件循环有机会处理其他微任务，扫描大目录时 UI 保持响应。
  Stream<_FileEntry> _walkDirectory(Directory dir) async* {
    // 先处理当前目录的文件
    yield* _listFilesInDirectory(dir);

    // 再递归处理子目录 — 使用异步 list 以避免阻塞事件循环
    // ⚡ 注意：dir.list() 是异步 Stream，每批返回一个 entity。
    // 相比 listSync() 的一次性返回所有 entity，异步版本在大目录下
    // 内存占用更低（无需一次性加载所有子目录名到 List）。
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! Directory) continue;

        // entity 经过 is! 检查后已收窄为 Directory 类型
        // ⚡ 注意：异步 list() 返回的 entity 类型与同步 listSync() 一致，
        // 都是 FileSystemEntity，但通过 await for 逐条消费而非一次性加载。
        if (_shouldSkipDirectory(entity)) continue;

        yield* _walkDirectory(entity);
      }
    } on FileSystemException {
      // 无法列出目录内容（权限不足等），跳过该目录，继续扫描其他目录
    }
  }

  /// 列出单个目录中的图片文件
  ///
  /// ⚡ 性能说明：
  /// - 使用异步 `dir.list()` 替代同步 `dir.listSync()`，避免阻塞事件循环。
  /// - `entity.stat()` 虽是异步调用但文件元数据读取通常很快（~1ms）。
  /// - 对于包含数千文件的单个目录，同步 listSync 可能阻塞数毫秒到数十毫秒。
  ///   虽然单次不大，但累积在深度递归中可能显著影响启动扫描延迟。
  Stream<_FileEntry> _listFilesInDirectory(Directory dir) async* {
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;

        final ext = p.extension(entity.path).toLowerCase().replaceAll('.', '');
        if (!AppConstants.supportedImageExtensions.contains(ext)) continue;

        // 忽略过大的文件
        try {
          final stat = await entity.stat();
          if (stat.size > AppConstants.maxFileSizeBytes) continue;
          yield _FileEntry(entity, stat);
        } on FileSystemException {
          // 单个文件 stat 失败（权限/锁定等），跳过该文件
          continue;
        }
      }
    } on FileSystemException {
      // 目录不可读，跳过
    }
  }

  /// 判断是否应跳过该目录（不递归进入）
  ///
  /// 同时覆盖 Unix 约定（`.` 前缀）和 Windows 系统目录。
  bool _shouldSkipDirectory(Directory dir) {
    final name = p.basename(dir.path);

    // ── Unix 隐藏目录：`.` 前缀 ──
    if (name.startsWith('.') && name != '.' && name != '..') return true;

    // ── Windows 已知系统目录 ──
    // 这些目录在 Windows 上即使不以 `.` 开头也通常无权限访问，
    // 提前跳过避免触发 FileSystemException。
    const windowsSystemDirs = {
      r'$Recycle.Bin',    // 回收站（NTFS）
      r'$RECYCLE.BIN',    // 回收站（FAT32/exFAT 大写变体）
      'System Volume Information', // 系统还原/卷影副本
      'Config.Msi',       // Windows Installer 缓存
      'MSOCache',         // Office 安装缓存
      'Recovery',         // 系统恢复分区挂载点
      // NTFS junction 指向（用户目录下）
      'Application Data',
      'Local Settings',
      'Templates',
      'SendTo',
      'Recent',
      'Cookies',
      'NetHood',
      'PrintHood',
      'Start Menu',
    };
    if (windowsSystemDirs.contains(name)) return true;

    // ── 兜底：stat 失败的目录直接跳过 ──
    // 无法获取 stat 的目录通常意味着权限不足（如其他用户的个人目录），
    // 这类目录几乎不可能包含用户需要导入的照片。
    try {
      dir.statSync();
    } on FileSystemException {
      return true;
    }

    return false;
  }

  /// 监听文件夹变更
  ///
  /// 返回一个 Stream，发出文件创建/修改/删除事件
  Stream<FileSystemChangeEvent> watchDirectory(String dirPath) {
    final controller = StreamController<FileSystemChangeEvent>.broadcast();
    StreamSubscription<WatchEvent>? sub;

    try {
      final watcher = DirectoryWatcher(dirPath);
      sub = watcher.events.listen(
        (event) {
          final ext =
              p.extension(event.path).toLowerCase().replaceAll('.', '');
          if (!AppConstants.supportedImageExtensions.contains(ext) &&
              event.type != ChangeType.REMOVE) {
            return;
          }

          controller.add(FileSystemChangeEvent(
            type: switch (event.type) {
              ChangeType.ADD => FileSystemChangeType.add,
              ChangeType.MODIFY => FileSystemChangeType.modify,
              ChangeType.REMOVE => FileSystemChangeType.remove,
              _ => FileSystemChangeType.modify,
            },
            path: event.path,
          ));
        },
        onError: (Object e) => controller.addError(e),
        onDone: () => controller.close(),
      );
    } catch (e) {
      controller.addError(FileSystemAppException('无法监听文件夹', detail: e.toString()));
    }

    controller.onCancel = () {
      sub?.cancel();
    };

    return controller.stream;
  }

  /// 计算文件 SHA256 哈希
  Future<String> computeFileHash(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemAppException('文件不存在', detail: filePath);
    }
    // 简化：使用文件路径+大小+修改时间作为快速哈希
    // 完整 SHA256 在 Isolate 中执行（见 import_service）
    final stat = await file.stat();
    return '${filePath}_${stat.size}_${stat.modified.millisecondsSinceEpoch}'
        .hashCode
        .toRadixString(16);
  }

  /// 检查文件是否存在
  Future<bool> fileExists(String path) async {
    return File(path).exists();
  }

  /// 获取文件信息
  Future<FileStat> getFileStat(String path) async {
    return File(path).stat();
  }

  /// 释放资源
  void dispose() {}
}

/// 扫描事件
class ScanEvent {
  final ScanEventType type;
  final String path;
  final FileStat? fileStat;
  final int? totalFiles;

  const ScanEvent({
    required this.type,
    required this.path,
    this.fileStat,
    this.totalFiles,
  });
}

enum ScanEventType { fileFound, completed }

/// 文件系统变更事件
class FileSystemChangeEvent {
  final FileSystemChangeType type;
  final String path;

  const FileSystemChangeEvent({required this.type, required this.path});
}

enum FileSystemChangeType { add, modify, remove }

/// 文件条目（带 stat 缓存，避免重复 stat 调用）
class _FileEntry {
  final File file;
  final FileStat stat;

  const _FileEntry(this.file, this.stat);
}