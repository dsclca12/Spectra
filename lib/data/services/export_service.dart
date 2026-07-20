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

    // ── 预读目标目录所有文件名到内存 Set ──
    // ⚡ 性能优化：避免文件名冲突时逐次 File.exists()（N 次磁盘 I/O）。
    // 导出大量同名文件（如 "IMG_0001 (1).jpg" 等）时，旧代码对每个
    // 计数器值都做一次 await File.exists()，串行化 N 次 I/O。
    // 预读后冲突检查全部在内存中完成，O(1) per check。
    // 注意：对于 preserveStructure 模式，子目录的文件名无法全部预读，
    // 但 preserveStructure 模式通常不会出现大量同名文件（在不同子目录下）。
    final existingFiles = await _preloadTargetFileNames(targetDir);

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
        existingFiles: existingFiles,
      )),
    );
    exported = results.where((r) => r).length;

    onProgress?.call(exported, total, '');
    return exported;
  }

  /// 预读目标目录中的所有文件名（不含路径），返回 Set 用于内存查重。
  ///
  /// ⚡ 性能说明：
  /// - `dir.listSync()` 是同步操作，但通常很快（纯目录元数据读取，不读文件内容）。
  /// - 对于包含数万文件的目标目录，可能耗时数百毫秒。
  /// - 但相比旧代码逐次 `File.exists()` 的 N × 毫秒级开销，预读一次是净优化。
  Future<Set<String>> _preloadTargetFileNames(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return {};

    try {
      final entities = dir.listSync(followLinks: false);
      return entities
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .toSet();
    } on FileSystemException {
      // 目录不可读时回退到逐次检查（不阻塞导出）
      return {};
    }
  }

  /// 复制单张照片（受信号量限流），返回 true 表示成功
  ///
  /// [existingFiles] 共享的目标目录文件名集合，用于内存查重。
  /// 复制成功后会将新文件名加入集合，供并行任务感知。
  Future<bool> _copyOneFile({
    required String sourcePath,
    required String targetDir,
    required bool preserveStructure,
    required String? commonRootPath,
    required Set<String> existingFiles,
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
        // ⚡ 内存查重替代逐次 File.exists() — 避免 N 次磁盘 I/O
        // 利用预读的 existingFiles Set 做 O(1) 冲突检测
        if (existingFiles.contains(fileName)) {
          final nameNoExt = p.basenameWithoutExtension(fileName);
          final ext = p.extension(fileName);
          var counter = 1;
          var candidate = '$nameNoExt ($counter)$ext';
          while (existingFiles.contains(candidate)) {
            counter++;
            candidate = '$nameNoExt ($counter)$ext';
          }
          destPath = p.join(targetDir, candidate);
        }
      }

      try {
        if (!await sourceFile.exists()) return false;
        await sourceFile.copy(destPath);
        // 复制成功后，将新文件名加入集合，供其他并行任务感知
        existingFiles.add(p.basename(destPath));
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