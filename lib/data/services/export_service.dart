import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/concurrency.dart';

/// 导出服务 — 将照片复制到目标目录。
///
/// 支持按筛选条件导出，可选保持原始目录结构或扁平化。
///
/// ⚡ 性能策略：
/// - Semaphore(4) 限制并行复制数：Windows 上过多并行文件 I/O 会
///   导致磁盘控制器队列过深，反而降低吞吐量。4 路并行在 HDD/SSD 上都表现良好。
/// - 目标文件夹只在开始时创建一次，避免逐文件重复检查 exists()。
/// - Future.wait 批量提交复制任务 + 信号量内部排队 = 4 路并行 + 自动排队。
/// - 文件名冲突：追加计数器后缀（"文件名 (1).ext"），而非覆盖。
///
/// ⚠️ 已知限制：
/// - 当前只做文件复制，不做格式转换或编辑烘焙。
/// - 如果用户需要导出编辑后的照片（带 EditParams），需先通过
///   ImageEditService.bakeAndExport 烘焙后再导出。
/// - RAW/HEIC 格式直接复制原始文件，不支持导出为 JPEG/PNG。
class ExportService {
  /// 并行复制信号量 — 限制同时进行的文件复制操作。
  /// Windows 上过多并行文件 I/O 可能导致磁盘控制器队列过深，
  /// 反而降低吞吐量。4 路并行在机械硬盘和 SSD 上都有良好表现。
  final _copySemaphore = Semaphore(4);

  /// Export photos to a target directory.
  ///
  /// [photoPaths] List of photo file paths to export.
  /// [targetDir] Target directory path.
  /// [preserveStructure] Whether to preserve original directory structure (true=keep subdirectories, false=flatten).
  /// [onProgress] Progress callback (exported count, total count, current filename).
  ///
  /// Returns the number of successfully exported files.
  Future<int> exportPhotos({
    required List<String> photoPaths,
    required String targetDir,
    bool preserveStructure = false,
    String? commonRootPath,
    void Function(int exported, int total, String currentFile)? onProgress,
  }) async {
    if (photoPaths.isEmpty) return 0;

    final targetDirectory = Directory(targetDir);
    if (!await targetDirectory.exists()) {
      await targetDirectory.create(recursive: true);
    }

    final total = photoPaths.length;
    var exported = 0;

    // 并行复制 — 用 Future.wait 批量执行，而非逐张 await。
    // Semaphore 控制并发数，避免 I/O 饱和。
    // 对于大量小文件（<10MB），并行复制可显著提升吞吐量。
    final results = await Future.wait(
      photoPaths.map((sourcePath) => _copyOneFile(
        sourcePath: sourcePath,
        targetDir: targetDir,
        preserveStructure: preserveStructure,
        commonRootPath: commonRootPath,
      )),
    );
    exported = results.where((r) => r).length;

    onProgress?.call(exported, total, '');
    return exported;
  }

  /// 复制单张照片（受信号量限流），返回 true 表示成功
  Future<bool> _copyOneFile({
    required String sourcePath,
    required String targetDir,
    required bool preserveStructure,
    required String? commonRootPath,
  }) async {
    final release = await _copySemaphore.acquire();
    try {
      final sourceFile = File(sourcePath);
      final fileName = p.basename(sourcePath);

      // Determine destination path
      String destPath;
      if (preserveStructure && commonRootPath != null) {
        final relativePath = p.relative(sourcePath, from: commonRootPath);
        destPath = p.join(targetDir, relativePath);
        final destDir = p.dirname(destPath);
        final subDir = Directory(destDir);
        if (!await subDir.exists()) {
          await subDir.create(recursive: true);
        }
      } else {
        destPath = p.join(targetDir, fileName);
        // Handle filename collision: append counter
        if (await File(destPath).exists()) {
          final nameNoExt = p.basenameWithoutExtension(fileName);
          final ext = p.extension(fileName);
          var counter = 1;
          while (await File(p.join(targetDir, '$nameNoExt ($counter)$ext')).exists()) {
            counter++;
          }
          destPath = p.join(targetDir, '$nameNoExt ($counter)$ext');
        }
      }

      try {
        if (!await sourceFile.exists()) return false;
        await sourceFile.copy(destPath);
        return true;
      } catch (_) {
        // 复制失败跳过，继续处理下一张
        return false;
      }
    } finally {
      release();
    }
  }
}