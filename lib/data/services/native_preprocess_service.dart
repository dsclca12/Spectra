/// Native NCHW 预处理 FFI 绑定
///
/// 调用 C 原生库进行高性能 RGBA → NCHW 转换。
/// 对于 256×256 图片，C 版本比纯 Dart 快 5-10 倍。
///
/// 使用方式：
/// ```dart
/// final preprocess = NativePreprocessService();
/// final nchw = preprocess.rgbaToNCHW(rgbaBytes, 256, 256);
/// ```
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' show malloc;
import 'package:path/path.dart' as p;

/// C 函数签名
typedef NchwRgbaToPlanarNative = Void Function(
  Pointer<Uint8> rgba,
  Int32 width,
  Int32 height,
  Pointer<Float> nchwOut,
  Int32 normalize,
);

typedef NchwRgbaToPlanarDart = void Function(
  Pointer<Uint8> rgba,
  int width,
  int height,
  Pointer<Float> nchwOut,
  int normalize,
);

typedef ComputeImageStatsNative = Void Function(
  Pointer<Uint8> rgba,
  Int32 width,
  Int32 height,
  Pointer<Double> stats,
);

typedef ComputeImageStatsDart = void Function(
  Pointer<Uint8> rgba,
  int width,
  int height,
  Pointer<Double> stats,
);

/// 原生预处理服务
///
/// 加载 `nchw_preprocess.dll` 并使用 FFI 调用其函数。
/// 如果 DLL 不可用，回退到纯 Dart 实现。
///
/// ⚡ 性能优化（v0.4.9）：
/// - 旧实现：构造函数中同步加载 DLL（file.existsSync()），阻塞主线程。
///   对于使用 AI 功能时才需要加载的场景不友好。
/// - 新实现：异步延迟加载，构造函数只发起 Future（非阻塞），
///   首次调用 rgbaToNCHW / computeStats 时可能尚未加载完成，
///   此时自动回退到纯 Dart 实现。确保加载完成可 await ensureLoaded()。
/// - `Directory.current.path` 在 Flutter 中不可靠（随引擎启动方式变化），
///   改为先从 `Platform.resolvedExecutable` 推导 DLL 路径。
class NativePreprocessService {
  DynamicLibrary? _lib;
  NchwRgbaToPlanarDart? _rgbaToPlanar;
  ComputeImageStatsDart? _computeStats;
  bool _initialized = false;
  late final Future<void> _loadFuture;

  /// 是否成功加载原生库
  bool get isAvailable => _initialized;

  /// 构造函数 — 立即发起异步加载（非阻塞），返回后即可使用实例。
  /// 加载完成前调用 rgbaToNCHW 会静默回退到纯 Dart 实现。
  /// 如需确保原生库已加载，请 await ensureLoaded()。
  NativePreprocessService() {
    _loadFuture = _initAsync();
  }

  /// 等待原生库加载完成
  Future<void> ensureLoaded() => _loadFuture;

  Future<void> _initAsync() async {
    try {
      final libName = Platform.isWindows
          ? 'nchw_preprocess.dll'
          : 'libnchw_preprocess.so';
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final candidates = [
        // 可执行文件同级目录 / lib 子目录
        p.join(exeDir, libName),
        if (!Platform.isWindows) p.join(exeDir, 'lib', libName),
        // 当前目录
        p.join(Directory.current.path, libName),
        // Windows 构建输出
        if (Platform.isWindows) ...[
          p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner',
              'Debug', libName),
          p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner',
              'Release', libName),
        ],
        // Linux 构建输出
        if (!Platform.isWindows) ...[
          p.join(Directory.current.path, 'build', 'linux', 'x64', 'runner',
              'bundle', 'lib', libName),
        ],
        // 原生构建输出
        p.join(Directory.current.path, 'native', 'preprocess', 'build', libName),
      ];

      for (final path in candidates) {
        final file = File(path);
        if (await file.exists()) {
          _lib = DynamicLibrary.open(path);
          break;
        }
      }

      if (_lib != null) {
        _rgbaToPlanar = _lib!
            .lookupFunction<NchwRgbaToPlanarNative, NchwRgbaToPlanarDart>(
                'nchw_rgba_to_planar');
        _computeStats = _lib!
            .lookupFunction<ComputeImageStatsNative, ComputeImageStatsDart>(
                'compute_image_stats');
        _initialized = true;
      }
    } catch (_) {
      _initialized = false;
    }
  }

  /// 将 RGBA uint8 数据转换为 NCHW Float32 格式
  ///
  /// 返回 [R平面, G平面, B平面] 的连续 Float32List，值归一化到 [0, 1]。
  /// 如果原生库不可用，使用纯 Dart 回退。
  Float32List rgbaToNCHW(Uint8List rgbaBytes, int width, int height) {
    final totalPixels = width * height;
    final result = Float32List(3 * totalPixels);

    if (_initialized && _rgbaToPlanar != null) {
      // 使用 C 原生实现
      final rgbaPtr = malloc.allocate<Uint8>(rgbaBytes.length);
      final rgbaList = rgbaPtr.asTypedList(rgbaBytes.length);
      rgbaList.setAll(0, rgbaBytes);

      final nchwPtr = malloc.allocate<Float>(3 * totalPixels);

      _rgbaToPlanar!(rgbaPtr, width, height, nchwPtr, 1);

      final nchwList = nchwPtr.asTypedList(3 * totalPixels);
      result.setAll(0, nchwList);

      malloc.free(rgbaPtr);
      malloc.free(nchwPtr);
    } else {
      // 纯 Dart 回退
      _rgbaToNCHWDart(rgbaBytes, width, height, result);
    }

    return result;
  }

  /// 纯 Dart 实现（回退方案）
  void _rgbaToNCHWDart(
      Uint8List rgba, int width, int height, Float32List result) {
    final totalPixels = width * height;
    final inv255 = 1.0 / 255.0;
    for (int i = 0; i < totalPixels; i++) {
      final src = i * 4;
      result[i] = rgba[src] * inv255;
      result[totalPixels + i] = rgba[src + 1] * inv255;
      result[2 * totalPixels + i] = rgba[src + 2] * inv255;
    }
  }

  /// 计算图像统计（原生实现，比 Dart 快 3-5 倍）
  ///
  /// 返回 [avgR, avgG, avgB, avgLum, stdLum,
  ///        p5, p50, p95,
  ///        highlightClip, shadowClip, neutralRatio, avgSat]
  /// 如果原生库不可用，返回 null。
  Float64List? computeStats(Uint8List rgbaBytes, int width, int height) {
    if (!_initialized || _computeStats == null) return null;

    final rgbaPtr = malloc.allocate<Uint8>(rgbaBytes.length);
    final rgbaList = rgbaPtr.asTypedList(rgbaBytes.length);
    rgbaList.setAll(0, rgbaBytes);

    final statsPtr = malloc.allocate<Double>(12);

    _computeStats!(rgbaPtr, width, height, statsPtr);

    final statsList = statsPtr.asTypedList(12);
    final result = Float64List.fromList(statsList);

    malloc.free(rgbaPtr);
    malloc.free(statsPtr);

    return result;
  }
}
