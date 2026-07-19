import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/concurrency.dart';

/// Image decoding service — unified decoding for various image formats.
///
/// Decoding strategy:
/// - **Standard formats** (JPEG/PNG/WebP/BMP/GIF): Uses `dart:ui` native decoder (Skia/Impeller)
///   - Executes on native thread asynchronously, doesn't block UI
///   - `targetWidth` parameter decodes directly to target size, avoiding full-resolution decode
///   - 10-50x faster than `package:image`, 90%+ less memory usage
///
/// - **RAW/HEIC/HEIF/AVIF/TIFF**: Uses Windows WIC (Windows Imaging Component)
///   - Accessed via PowerShell + WPF (PresentationCore)
///   - WIC is a built-in Windows component, no extra software required
///   - Requires corresponding codec packs:
///     - HEIC: "HEIF Image Extensions" (Microsoft Store, free)
///     - RAW: "Raw Image Extension" or camera vendor codec packs (Microsoft Store, free)
///   - Decoded results saved as PNG to avoid re-decoding
///   - Semaphore limits concurrent PowerShell processes to prevent process explosion
class ImageDecoderService {
  ImageDecoderService();

  /// Semaphore to limit concurrent WIC (PowerShell) processes.
  /// Each PowerShell process uses ~30-50MB memory; 4 concurrent = 120-200MB.
  final Semaphore _wicSemaphore = Semaphore(4);

  /// Flutter 原生支持的格式（dart:ui / Skia 可直接解码）
  static const Set<String> flutterSupportedExtensions = {
    'jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif', 'wbmp',
  };

  /// 需要通过 WIC 解码的格式
  static const Set<String> wicRequiredExtensions = {
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
      {...flutterSupportedExtensions, ...wicRequiredExtensions};

  /// 判断文件是否需要外部解码器（WIC）
  bool requiresExternalDecoder(String filePath) {
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
    return wicRequiredExtensions.contains(ext);
  }

  /// 判断文件格式是否被支持
  bool isSupported(String filePath) {
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
    return allSupportedExtensions.contains(ext);
  }

  /// 解码图像为 `ui.Image`
  ///
  /// [targetWidth] 如果指定，将图像解码到目标宽度（保持比例）。
  /// 返回 null 表示解码失败或格式不支持。
  Future<ui.Image?> decode(String filePath, {int? targetWidth}) async {
    final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');

    if (flutterSupportedExtensions.contains(ext)) {
      return _decodeWithDartUI(filePath, targetWidth: targetWidth);
    } else if (wicRequiredExtensions.contains(ext)) {
      return _decodeWithWIC(filePath, targetWidth: targetWidth);
    }
    return null;
  }

  /// 解码图像并保存为 PNG 文件
  ///
  /// 用于缩略图生成和预览图缓存。
  /// 返回 outputPath 表示成功，null 表示失败。
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
    } else if (wicRequiredExtensions.contains(ext)) {
      return _decodeAndSavePngWithWIC(filePath, outputPath,
          targetWidth: targetWidth);
    }
    return null;
  }

  // ─── dart:ui 解码（标准格式）──

  /// 使用 `dart:ui` 解码（JPEG/PNG/WebP/BMP/GIF）
  ///
  /// `instantiateImageCodec` 在 native 线程异步执行，不阻塞 UI。
  /// `targetWidth` 让解码器直接解码到目标尺寸，无需解码全分辨率。
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
      final tempPath = p.join(
        tempDir.path,
        'spectra_wic_${DateTime.now().microsecondsSinceEpoch}.png',
      );

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
      await File(tempPath).delete();
      return image;
    } catch (_) {
      return null;
    }
  }
}