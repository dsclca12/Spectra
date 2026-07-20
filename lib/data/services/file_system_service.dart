import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import '../../core/constants.dart';
import '../../core/errors.dart';

/// 文件系统服务 — 负责文件遍历、监听和增量扫描
class FileSystemService {
  FileSystemService();

  /// 递归扫描文件夹中的所有图片文件
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
  Stream<_FileEntry> _walkDirectory(Directory dir) async* {
    // 先处理当前目录的文件
    yield* _listFilesInDirectory(dir);

    // 再递归处理子目录
    List<FileSystemEntity> subdirs;
    try {
      subdirs = dir.listSync(followLinks: false);
    } on FileSystemException {
      // 无法列出目录内容（权限不足等），跳过该目录，继续扫描其他目录
      return;
    }

    for (final entity in subdirs) {
      if (entity is! Directory) continue;

      // 跳过应忽略的目录
      if (_shouldSkipDirectory(entity)) continue;

      yield* _walkDirectory(entity);
    }
  }

  /// 列出单个目录中的图片文件
  Stream<_FileEntry> _listFilesInDirectory(Directory dir) async* {
    List<FileSystemEntity> entities;
    try {
      entities = dir.listSync(followLinks: false);
    } on FileSystemException {
      // 目录不可读，跳过
      return;
    }

    for (final entity in entities) {
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