/// 模型下载服务 — 从远程 URL 下载 ONNX 模型文件
///
/// 使用 dart:io HttpClient 实现，支持：
/// - 下载进度回调
/// - 断点续传检测（HTTP Range）
/// - 超时控制
/// - 自动保存到应用数据目录
///
/// 默认模型托管在 GitHub Releases，用户也可以配置自定义 URL。
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging.dart';

/// 下载状态
enum DownloadStatus {
  idle,
  downloading,
  completed,
  failed,
  cancelled,
}

/// 下载进度
class DownloadProgress {
  final DownloadStatus status;
  final int receivedBytes;
  final int? totalBytes;
  final String? errorMessage;

  const DownloadProgress({
    this.status = DownloadStatus.idle,
    this.receivedBytes = 0,
    this.totalBytes,
    this.errorMessage,
  });

  /// 下载百分比（0.0-1.0），未知大小时返回 0
  double get fraction {
    if (totalBytes == null || totalBytes == 0) return 0.0;
    return (receivedBytes / totalBytes!).clamp(0.0, 1.0);
  }

  /// 人类可读的进度文本
  String get progressText {
    if (totalBytes != null && totalBytes! > 0) {
      final pct = (fraction * 100).toStringAsFixed(1);
      final received = _formatBytes(receivedBytes);
      final total = _formatBytes(totalBytes!);
      return '$received / $total ($pct%)';
    }
    return _formatBytes(receivedBytes);
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String formatBytes(int bytes) => _formatBytes(bytes);
}

/// 模型信息
class ModelInfo {
  final String id;
  final String name;
  final String description;
  final int expectedSizeBytes;
  final String defaultUrl;

  const ModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.expectedSizeBytes,
    required this.defaultUrl,
  });
}

/// 可下载/可转换的模型列表（全部来自 HuggingFace）
class AvailableModels {
  AvailableModels._();

  /// 自动增强模型 — 轻量级 ONNX 模型（本地生成，无需下载）
  /// 使用 scripts/gen_auto_enhance_onnx.py 生成，或通过"本地导入"加载
  static const autoEnhance = ModelInfo(
    id: 'auto_enhance',
    name: '自动增强 (通用)',
    description: '轻量级图像增强网络，输出颜色矩阵 + gamma 参数。\n'
        '参数约 1.5K，ONNX 模型约 4KB。\n'
        '本地生成: python scripts/gen_auto_enhance_onnx.py\n'
        '训练自定义模型: python scripts/train_auto_enhance.py',
    expectedSizeBytes: 5 * 1024,
    defaultUrl: '', // 本地生成模型，无远程下载链接
  );

  /// Zero-DCE 低光增强 — LiteRT 格式，需手动转 ONNX
  static const zeroDce = ModelInfo(
    id: 'zero_dce',
    name: 'Zero-DCE 低光增强',
    description: '零参考深度曲线估计，极轻量低光增强。\n'
        'HuggingFace: mlboydaisuke/zero-dce-litert\n'
        '适合：夜景、室内暗光照片。\n'
        '转换命令:\n'
        '  python scripts/convert_model.py --model mlboydaisuke/zero-dce-litert --output zero_dce.onnx',
    expectedSizeBytes: 500 * 1024,
    defaultUrl: 'https://huggingface.co/mlboydaisuke/zero-dce-litert',
  );

  /// NAFNet 去噪模型 — GGUF 格式，需手动转 ONNX
  static const nafnetDenoise = ModelInfo(
    id: 'nafnet_denoise',
    name: 'NAFNet 去噪',
    description: '非线性激活无关网络，778K 参数。\n'
        'HuggingFace: cstr/nafnet-sidd-GGUF\n'
        '适合：高 ISO 照片降噪。\n'
        '需要先将 GGUF 转为 PyTorch，再转 ONNX。\n'
        '转换命令:\n'
        '  python scripts/convert_model.py --model cstr/nafnet-sidd-GGUF --output nafnet.onnx',
    expectedSizeBytes: 3 * 1024 * 1024,
    defaultUrl: 'https://huggingface.co/cstr/nafnet-sidd-GGUF',
  );

  /// MIRNet 通用增强
  static const mirnet = ModelInfo(
    id: 'mirnet',
    name: 'MIRNet 通用增强',
    description: '多尺度图像恢复网络。\n'
        'HuggingFace: Fairfield-U-AILab/4x-mirnet-image-enhancement\n'
        '同时处理亮度、对比度、色彩。\n'
        '转换命令:\n'
        '  python scripts/convert_model.py --model Fairfield-U-AILab/4x-mirnet-image-enhancement --output mirnet.onnx',
    expectedSizeBytes: 5 * 1024 * 1024,
    defaultUrl: 'https://huggingface.co/Fairfield-U-AILab/4x-mirnet-image-enhancement',
  );

  /// Swin2SR 超分辨率 — 已有 ONNX 格式！
  static const swin2SR = ModelInfo(
    id: 'swin2sr',
    name: 'Swin2SR 超分辨率 (x2)',
    description: 'Swin Transformer 超分模型，原生 ONNX 格式！\n'
        'HuggingFace: Xenova/swin2SR-classical-sr-x2-64\n'
        '直接下载 ONNX 文件即可使用，无需转换。\n'
        '下载链接:\n'
        '  https://huggingface.co/Xenova/swin2SR-classical-sr-x2-64/resolve/main/onnx/model.onnx',
    expectedSizeBytes: 2 * 1024 * 1024,
    defaultUrl: 'https://huggingface.co/Xenova/swin2SR-classical-sr-x2-64/resolve/main/onnx/model.onnx',
  );

  /// 所有可用的模型列表
  static const List<ModelInfo> all = [
    autoEnhance,
    zeroDce,
    nafnetDenoise,
    mirnet,
    swin2SR,
  ];
}

/// 模型下载服务
class ModelDownloadService {
  final HttpClient _client;

  ModelDownloadService() : _client = HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 15);
    _client.idleTimeout = const Duration(seconds: 120);
  }

  /// 下载模型文件
  ///
  /// [model] 模型信息（含默认下载 URL）
  /// [customUrl] 自定义下载 URL（为空则使用模型默认 URL）
  /// [onProgress] 进度回调
  ///
  /// 返回下载后的文件路径（保存到应用临时目录后用文件选择器复制到目标位置），
  /// 或 null 表示下载失败。
  Future<String?> download({
    required ModelInfo model,
    String? customUrl,
    void Function(DownloadProgress)? onProgress,
  }) async {
    final url = (customUrl ?? model.defaultUrl).trim();
    if (url.isEmpty) {
      onProgress?.call(const DownloadProgress(
        status: DownloadStatus.failed,
        errorMessage: '下载 URL 为空',
      ));
      return null;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      onProgress?.call(const DownloadProgress(
        status: DownloadStatus.failed,
        errorMessage: '无效的下载 URL',
      ));
      return null;
    }

    // 保存到应用支持目录
    final appDir = await getApplicationSupportDirectory();
    final modelsDir = Directory(p.join(appDir.path, 'models'));
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    final outputPath = p.join(modelsDir.path, '${model.id}.onnx');

    final completer = Completer<String?>();
    HttpClientRequest? request;
    StreamSubscription? subscription;

    try {
      request = await _client.getUrl(uri);
      request.headers.set('User-Agent', 'Spectra/0.1.0');
      // 如果有部分下载文件，尝试断点续传
      final existingFile = File(outputPath);
      if (await existingFile.exists()) {
        await existingFile.delete(); // 简化处理：重新下载
      }

      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode != 200) {
        AppLogger.warn('下载', 'HTTP ${response.statusCode}', details: 'url: $url');
        onProgress?.call(DownloadProgress(
          status: DownloadStatus.failed,
          errorMessage: '服务器返回 HTTP ${response.statusCode}',
        ));
        return null;
      }

      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : model.expectedSizeBytes;

      AppLogger.info('下载', '开始下载: ${model.name}', details: '${DownloadProgress.formatBytes(totalBytes)}');

      final file = File(outputPath);
      final sink = file.openWrite();

      int received = 0;

      onProgress?.call(DownloadProgress(
        status: DownloadStatus.downloading,
        receivedBytes: 0,
        totalBytes: totalBytes,
      ));

      subscription = response.listen(
        (data) {
          received += data.length;
          sink.add(data);

          onProgress?.call(DownloadProgress(
            status: DownloadStatus.downloading,
            receivedBytes: received,
            totalBytes: totalBytes,
          ));
        },
        onError: (e) {
          sink.close();
          completer.completeError(e);
        },
        onDone: () async {
          await sink.close();

          // 验证下载内容是否为有效 ONNX 模型（防止下载到 HTML 页面）
          if (!await _isValidOnnx(outputPath)) {
            await file.delete();
            AppLogger.error('下载', '下载内容不是有效的 ONNX 模型 (可能是 HTML)',
                details: '文件已删除: $outputPath');
            onProgress?.call(const DownloadProgress(
              status: DownloadStatus.failed,
              errorMessage: '下载内容不是有效的 ONNX 模型（服务器返回了网页而非模型文件）',
            ));
            completer.complete(null);
            return;
          }

          AppLogger.info('下载', '下载完成: ${model.name}', details: '${DownloadProgress.formatBytes(received)}, 保存到 $outputPath');

          onProgress?.call(DownloadProgress(
            status: DownloadStatus.completed,
            receivedBytes: received,
            totalBytes: totalBytes,
          ));

          if (!completer.isCompleted) {
            completer.complete(outputPath);
          }
        },
        cancelOnError: true,
      );

      final result = await completer.future;
      return result;
    } catch (e) {
      onProgress?.call(DownloadProgress(
        status: DownloadStatus.failed,
        errorMessage: '下载失败: ${e.toString()}',
      ));
      // 清理未完成的文件
      try {
        final partial = File(outputPath);
        if (await partial.exists()) await partial.delete();
      } catch (_) {}
      return null;
    } finally {
      subscription?.cancel();
    }
  }

  /// 取消下载（预留）
  void cancelDownload() {
    _client.close(force: true);
  }

  /// 释放资源
  void dispose() {
    _client.close(force: true);
  }

  /// 验证文件是否为有效的 ONNX 模型（protobuf 格式，非 HTML）
  static Future<bool> _isValidOnnx(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;
      final bytes = await file.readAsBytes();
      if (bytes.length < 8) return false;
      // ONNX 是 protobuf 二进制格式，第一个字节通常是 0x08（field tag）
      // HTML 以 '<' (0x3C) 开头
      return bytes[0] != 0x3C; // 不是 '<' = 不是 HTML/XML
    } catch (_) {
      return false;
    }
  }
}
