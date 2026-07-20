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
///   - 比 `package:image` 快 10-50 倍，内存占用降低 90%+。
///   - 不使用 Isolate.run — 原生解码本身就在 native 线程执行。
///   - 编码输出使用 `image.toByteData(format: ImageByteFormat.png)`。
///
/// **RAW/HEIC/HEIF/AVIF/TIFF**：使用 Windows WIC（Windows Imaging Component）
///   - 通过 PowerShell + WPF (PresentationCore) 的 BitmapImage 访问 WIC。
///   - WIC 是 Windows 内置组件，但需要安装对应 codec pack：
///     - HEIC/HEIF/AVIF："HEIF Image Extensions"（Microsoft Store 免费）
///     - RAW（CR2/NEF/ARW/DNG 等）："Raw Image Extension"（Microsoft Store 免费）
///     - 相机厂商也提供专用 codec pack（Canon/Nikon/Sony 等）
///   - 解码结果保存为 PNG 缓存，避免重复解码。
///   - Semaphore(6) 限制并发 PowerShell 进程数，每个约 30-50MB 内存。
///
/// ⚠️ 注意：当前使用 PowerShell 调用 WIC 的方式有启动延迟（~200ms 每进程），
/// 中长期应考虑 C++/WinRT 直接绑定 Windows WIC API 以消除延迟。
class ImageDecoderService {
  ImageDecoderService();

  /// Semaphore to limit concurrent WIC (PowerShell) processes.
  /// Each PowerShell process uses ~30-50MB memory; 4 concurrent = 120-200MB.
  /// 调高到 6：WIC 解码大部分时间花在 I/O 等待（读 RAW 文件），
  /// CPU 占用不高，适度增加并发可以提升批量缩略图生成吞吐量。
  /// 若内存不足（观察到 PowerShell 进程数 > 4 时内存 > 300MB），可降回 4。
  final Semaphore _wicSemaphore = Semaphore(6);

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

  /// 线程安全的递增临时文件 ID — 替代 DateTime 方式避免碰撞
  static int _tempIdCounter = 0;
  static int _nextTempId() {
    return ++_tempIdCounter;
  }

  /// 清理超过 24 小时未被访问的 WIC 临时文件
  /// 在应用启动时调用一次即可，避免临时目录无限膨胀
  Future<int> cleanStaleTempFiles() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      var count = 0;
      await for (final entity in tempDir.list()) {
        if (entity is File && entity.path.contains('spectra_wic_')) {
          try {
            final stat = await entity.stat();
            if (stat.modified.isBefore(cutoff)) {
              await entity.delete();
              count++;
            }
          } catch (_) {
            // 跳过无法 stat 或删除的文件
          }
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
  }
}