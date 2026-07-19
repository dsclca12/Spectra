import 'dart:io';

import 'package:path/path.dart' as p;

/// Export service — copies photos to a target directory.
///
/// Supports filter-based export (including rating filters), optionally preserving
/// original directory structure or flattening.
class ExportService {
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

    var exported = 0;
    final total = photoPaths.length;

    for (final sourcePath in photoPaths) {
      final sourceFile = File(sourcePath);
      final fileName = p.basename(sourcePath);

      // Determine destination path
      String destPath;
      if (preserveStructure && commonRootPath != null) {
        // Preserve directory structure: get relative path from commonRootPath
        final relativePath = p.relative(sourcePath, from: commonRootPath);
        destPath = p.join(targetDir, relativePath);
        // Create subdirectory
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

      onProgress?.call(exported, total, fileName);

      try {
        // 检查源文件是否存在
        if (!await sourceFile.exists()) {
          continue;
        }
        await sourceFile.copy(destPath);
        exported++;
      } catch (_) {
        // 复制失败跳过，继续处理下一张
      }
    }

    onProgress?.call(exported, total, '');
    return exported;
  }
}