import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/concurrency.dart';

/// 统一图像解码服务 — 为不同格式提供统一的解码入口。
///
/// 解码策略：
///
/// **标准格式（JPEG/PNG/WebP/BMP/GIF）**：使用 `dart:ui` 原生解码器（Skia/Impeller）
///   - 在 native 线程异步执行，不阻塞 UI 线程。
///   - `targetWidth` 参数让解码器直接解码到目标尺寸，无需解码全分辨率。
///
/// **RAW/HEIC/HEIF/AVIF/TIFF**：
///   - Windows：使用 WIC（Windows Imaging Component），通过 PowerShell + WPF 访问。
///   - Linux：使用 `ffmpeg` / `dcraw` / ImageMagick `convert` 等系统工具。
///
/// ## Linux 依赖
///   需要安装以下工具之一：
///   - `ffmpeg`（推荐） — 支持 HEIC/AVIF/TIFF 解码
///   - `dcraw` — RAW 格式解码（CR2/NEF/ARW/DNG 等）
///   - ImageMagick `convert` — 通用回退方案
///   
///   安装方式：
///   ```bash
///   # Debian/Ubuntu
///   sudo apt install ffmpeg dcraw imagemagick
///   # Fedora
///   sudo dnf install ffmpeg dcraw ImageMagick
///   # Arch
///   sudo pacman -S ffmpeg dcraw imagemagick
///   ```
class ImageDecoderService {
  ImageDecoderService();

  /// Semaphore to limit concurrent external decoder processes.
  /// Each process uses ~30-50MB memory.
  final Semaphore _decoderSemaphore = Semaphore(4);

  /// Flutter 原生支持的格式（dart:ui / Skia 可直接解码）
  static const Set<String> flutterSupportedExtensions = {
    'jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif', 'wbmp',
  };

  /// 需要外部解码器的格式（非标准格式）
  static const Set<String> externalRequiredExtensions = {
    // HEIC / HEIF / AVIF
    'heic', 'heif', 'hif', 'avif',
    // TIFF（dart:ui 不支持）
    'tif', 'tiff',
    // Canon
    'cr2', 'cr3', 'crw',
    // Nikon
    'nef', 'nrw',
    // Sony
    'arw', 'sr2', 'srf',
    // Adobe
    'dng',
    // Fujifilm
    'raf',
    // Panasonic
    'rw2', 'raw',
    // Olympus
    'orf',
    // Pentax
    'pef',
    // Samsung
    'srw',
    // Minolta
    'mrw',
    // Sigma
    'x3f',
    // Hasselblad
    '3fr', 'fff',
    // Phase One / Leaf
    'iiq', 'mos',
    // Leica
    'rwl',
    // Kodak
    'kdc', 'dcr',
    // Red
    'r3d',
  };

  /// 所有支持的图像格式
  static Set<String> get allSupportedExtensions =>
      {...flutterSupportedExtensions, ...externalRequiredExtensions};

  bool requiresExternalDecoder(String filePath) {
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
    return externalRequiredExtensions.contains(ext);
  }

  /// 判断文件格式是否被支持
  bool isSupported(String filePath) {
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
    return allSupportedExtensions.contains(ext);
  }

  Future<ui.Image?> decode(String filePath, {int? targetWidth}) async {
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');

    if (flutterSupportedExtensions.contains(ext)) {
      return _decodeWithDartUI(filePath, targetWidth: targetWidth);
    } else if (externalRequiredExtensions.contains(ext)) {
      if (Platform.isWindows) {
        return _decodeWithWIC(filePath, targetWidth: targetWidth);
      } else {
        return _decodeWithLinux(filePath, targetWidth: targetWidth);
      }
    }
    return null;
  }

  Future<String?> decodeToPngFile(
    String filePath, {
    required String outputPath,
    int? targetWidth,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');

    if (flutterSupportedExtensions.contains(ext)) {
      return _decodeAndSavePngWithDartUI(filePath, outputPath,
          targetWidth: targetWidth);
    } else if (externalRequiredExtensions.contains(ext)) {
      if (Platform.isWindows) {
        return _decodeAndSavePngWithWIC(filePath, outputPath,
            targetWidth: targetWidth);
      } else {
        return _decodeAndSavePngWithLinux(filePath, outputPath,
            targetWidth: targetWidth);
      }
    }
    return null;
  }

  // ─── dart:ui 解码（标准格式）──

  /// 使用 `dart:ui` 解码（JPEG/PNG/WebP/BMP/GIF）
  ///
  /// `instantiateImageCodec` 在 native 线程异步执行，不阻塞 UI。
  /// `targetWidth` 让解码器直接解码到目标尺寸，无需解码全分辨率。
  ///
  /// ⚠️ 内存说明：
  /// - `readAsBytes()` 将整个文件加载到内存。对于大图（BMP/TIFF 可能 50MB+），
  ///   这会导致峰值内存上升。但这是 `instantiateImageCodec` API 的要求 —
  ///   Skia 解码器需要完整的数据缓冲区才能创建 codec。
  /// - 缩略图场景（targetWidth=128/512）：解码器内部只解码部分数据，
  ///   但调用方仍需读完整个文件。这是 dart:ui 的已知限制。
  /// - 若出现内存问题，可考虑：1) 先用文件头判断尺寸后降采样读取；
  ///   2) 改为 WIC 解码路径（WIC 支持流式解码）。
  Future<ui.Image?> _decodeWithDartUI(
    String filePath, {
    int? targetWidth,
  }) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      codec.dispose();
      return image;
    } catch (_) {
      return null;
    }
  }

  /// 使用 `dart:ui` 解码并保存为 PNG
  Future<String?> _decodeAndSavePngWithDartUI(
    String filePath,
    String outputPath, {
    int? targetWidth,
  }) async {
    try {
      final image = await _decodeWithDartUI(filePath, targetWidth: targetWidth);
      if (image == null) return null;

      final pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (pngBytes == null) return null;
      await File(outputPath).writeAsBytes(pngBytes.buffer.asUint8List());
      return outputPath;
    } catch (_) {
      return null;
    }
  }

  // ─── WIC 解码（RAW/HEIC/AVIF/TIFF）──

  /// 使用 Windows WIC 解码并保存为 PNG
  ///
  /// 通过 PowerShell + WPF（PresentationCore）的 `BitmapImage` 访问 WIC。
  /// WIC 支持 HEIC（需 HEIF codec pack）和 RAW（需 RAW codec pack）。
  /// 使用 base64 编码脚本避免转义问题。
  Future<String?> _decodeAndSavePngWithWIC(
    String filePath,
    String outputPath, {
    int? targetWidth,
  }) async {
    // 信号量限流 — 避免同时启动大量 PowerShell 进程
    final release = await _wicSemaphore.acquire();
    try {
      // 构建 PowerShell 脚本 — 使用 raw string 避免 $ 转义问题
      // 占位符 __INPUT__ / __OUTPUT__ / __WIDTH_LINE__ 后替换
      final script = r"""
Add-Type -AssemblyName PresentationCore -ErrorAction Stop
try {
    $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.UriSource = [Uri]::new('__INPUT__', [UriKind]::Absolute)
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
__WIDTH_LINE__
    $bitmap.EndInit()
    $bitmap.Freeze()

    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [System.IO.File]::Create('__OUTPUT__')
    $encoder.Save($stream)
    $stream.Close()
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
"""
          .replaceAll('__INPUT__', filePath.replaceAll(r'\', '/'))
          .replaceAll('__OUTPUT__', outputPath.replaceAll(r'\', '/'))
          .replaceAll(
            '__WIDTH_LINE__',
            targetWidth != null
                ? '    \$bitmap.DecodePixelWidth = $targetWidth'
                : '',
          );

      // base64 编码避免转义问题
      final encoded = base64Encode(utf8.encode(script));

      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-EncodedCommand', encoded],
        stdoutEncoding: systemEncoding,
        stderrEncoding: systemEncoding,
      );

      if (result.exitCode != 0) return null;
      if (!await File(outputPath).exists()) return null;
      return outputPath;
    } catch (_) {
      return null;
    } finally {
      release();
    }
  }

  /// 使用 WIC 解码为 `ui.Image`
  ///
  /// 先用 WIC 解码为临时 PNG 文件，再用 `dart:ui` 加载为 `ui.Image`。
  Future<ui.Image?> _decodeWithWIC(
    String filePath, {
    int? targetWidth,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      // 用 UUID -style 文件名避免并发解码时的文件名冲突
      // microsecond 精度在批量导入大量 RAW 文件时仍可能碰撞
      final tempName = 'spectra_wic_${_nextTempId()}.png';
      final tempPath = p.join(tempDir.path, tempName);

      final result = await _decodeAndSavePngWithWIC(
        filePath,
        tempPath,
        targetWidth: targetWidth,
      );

      if (result == null) {
        // 清理可能的部分写入文件
        final tempFile = File(tempPath);
        if (await tempFile.exists()) await tempFile.delete();
        return null;
      }

      final image = await _decodeWithDartUI(tempPath);
      // 解码完毕后立即删除临时文件，避免临时目录积累大量 WIC 缓存
      // 注意：即使删除失败也不影响主流程，静默忽略
      try {
        await File(tempPath).delete();
      } catch (_) {
        // 临时文件删除失败不影响调用方
      }
      return image;
    } catch (_) {
      return null;
    }
  }

  // ─── Linux 解码（RAW/HEIC/AVIF/TIFF）──

  /// 使用 Linux 系统工具解码并保存为 PNG
  ///
  /// 尝试以下工具（按优先级）：
  ///   1. `dcraw` — RAW 格式（CR2/NEF/ARW/DNG 等）
  ///   2. `ffmpeg` — HEIC/AVIF/TIFF 及通用格式
  ///   3. `convert` (ImageMagick) — 通用回退
  Future<String?> _decodeAndSavePngWithLinux(
    String filePath,
    String outputPath, {
    int? targetWidth,
  }) async {
    final release = await _decoderSemaphore.acquire();
    try {
      // 先尝试使用 dcraw 解码 RAW 格式
      final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
      final isRaw = !['heic', 'heif', 'hif', 'avif', 'tif', 'tiff']
          .contains(ext);

      if (isRaw) {
        try {
          final result = await Process.run(
            'dcraw',
            ['-c', '-q', '3', '-w', filePath],
            stdoutEncoding: null,
            stderrEncoding: null,
          );
          if (result.exitCode == 0 && result.stdout is List<int>) {
            // dcraw outputs 16-bit PPM; convert to PNG
            // Use ffmpeg to convert PPM to PNG with optional resize
            final widthArgs = targetWidth != null
                ? ['-vf', 'scale=$targetWidth:-1']
                : <String>[];
            final convertResult = await Process.run(
              'ffmpeg',
              [
                '-y', '-f', 'image2pipe', '-c:v', 'ppm',
                '-i', '-',
                ...widthArgs,
                '-q:v', '1',
                outputPath,
              ],
              stdin: result.stdout as List<int>,
              stdoutEncoding: null,
              stderrEncoding: null,
            );
            if (convertResult.exitCode == 0) {
              if (await File(outputPath).exists()) return outputPath;
            }
          }
        } catch (_) {
          // dcraw failed, try next tool
        }
      }

      // 使用 ffmpeg 直接解码
      try {
        final scaleFilter = targetWidth != null
            ? ['-vf', 'scale=$targetWidth:-1']
            : <String>[];
        final result = await Process.run(
          'ffmpeg',
          [
            '-y', '-i', filePath,
            ...scaleFilter,
            '-q:v', '1',
            outputPath,
          ],
          stdoutEncoding: null,
          stderrEncoding: null,
        );
        if (result.exitCode == 0 && await File(outputPath).exists()) {
          return outputPath;
        }
      } catch (_) {
        // ffmpeg failed, try ImageMagick
      }

      // 使用 ImageMagick convert 作为最后回退
      try {
        final sizeArgs = targetWidth != null
            ? ['-resize', '${targetWidth}x']
            : <String>[];
        final result = await Process.run(
          'convert',
          [
            filePath,
            ...sizeArgs,
            outputPath,
          ],
          stdoutEncoding: null,
          stderrEncoding: null,
        );
        if (result.exitCode == 0 && await File(outputPath).exists()) {
          return outputPath;
        }
      } catch (_) {
        // All tools failed
      }

      return null;
    } catch (_) {
      return null;
    } finally {
      release();
    }
  }

  /// 使用 Linux 系统工具解码为 `ui.Image`
  Future<ui.Image?> _decodeWithLinux(
    String filePath, {
    int? targetWidth,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final tempName = 'spectra_linux_dec_${_nextTempId()}.png';
      final tempPath = p.join(tempDir.path, tempName);

      final result = await _decodeAndSavePngWithLinux(
        filePath,
        tempPath,
        targetWidth: targetWidth,
      );

      if (result == null) {
        final tempFile = File(tempPath);
        if (await tempFile.exists()) await tempFile.delete();
        return null;
      }

      final image = await _decodeWithDartUI(tempPath);
      try {
        await File(tempPath).delete();
      } catch (_) {}
      return image;
    } catch (_) {
      return null;
    }
  }

  /// 线程安全的递增临时文件 ID
  static int _tempIdCounter = 0;
  static int _nextTempId() {
    return ++_tempIdCounter;
  }

  /// 清理超过 24 小时未被访问的临时解码文件
  Future<int> cleanStaleTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      var count = 0;
      await for (final entity in tempDir.list()) {
        if (entity is File &&
            (entity.path.contains('spectra_wic_') ||
                entity.path.contains('spectra_linux_dec_'))) {
          try {
            final stat = await entity.stat();
            if (stat.modified.isBefore(cutoff)) {
              await entity.delete();
              count++;
            }
          } catch (_) {}
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
  }
}