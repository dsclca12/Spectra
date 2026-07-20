import 'dart:io';

import 'package:drift/drift.dart';
import 'package:exif/exif.dart';

import '../database/app_database.dart';

/// 元数据服务 — EXIF 读取与解析
///
/// ⚡ 性能策略：
/// - 第一阶段：只读文件头前 64KB 快速获取图像尺寸和 MIME 类型。
///   对于 JPEG 文件，EXIF 信息通常在前 64KB 内（APP1 标记段）。
///   对于 RAW 文件（20-100MB），避免加载整个文件到内存。
/// - 第二阶段：使用 exif 包的 readExifFromFile（RandomAccessFile），
///   只读取文件的 EXIF 相关区域，不加载整个文件。
///   （旧实现用 readAsBytes + readExifFromBytes 把整个 RAW 文件读到内存）
/// - IPTC 字段（标题/描述/关键词）当前未从文件中读取，
///   仅数据库字段预留。后续可通过 ExifTool 或 Windows WIC 的
///   QueryCapabilities 获取。
/// - GPS 坐标采用 DMS→十进制度数转换，精度保留 6 位小数（约 0.1 米）。
class MetadataService {
  MetadataService();

  /// 读取 EXIF 数据
  ///
  /// 返回 [PhotosCompanion] 包含 EXIF 字段，可用于更新数据库。
  /// 先快速解析文件头获取尺寸/MIME，再用 `exif` 包读取 EXIF。
  Future<PhotosCompanion?> readExif(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return null;
      }

      // ── 第一阶段：快速读取文件头获取尺寸和 MIME ──
      int? width;
      int? height;
      String? mimeType;

      final raf = await file.open();
      try {
        final headerBytes = await raf.read(64 * 1024);
        final imageInfo = _getImageInfo(headerBytes, filePath);
        width = imageInfo.width;
        height = imageInfo.height;
        mimeType = imageInfo.mimeType;
      } finally {
        await raf.close();
      }

      // ── 第二阶段：完整 EXIF 解析 ──
      // 使用 readExifFromFile 而非 readExifFromBytes：
      // - 不将整个文件读入内存（对 RAW 文件可能上百 MB）
      // - exif 包内部通过 RandomAccessFile 只读取 EXIF 相关区域
      Map<String, IfdTag>? exifData;
      try {
        exifData = await readExifFromFile(file);
      } catch (_) {
        // EXIF 解析失败不影响尺寸/MIME
      }

      // 构建 PhotosCompanion
      final companion = PhotosCompanion(
        width: width != null ? Value(width) : const Value.absent(),
        height: height != null ? Value(height) : const Value.absent(),
        mimeType: mimeType != null ? Value(mimeType) : const Value.absent(),
      );

      if (exifData == null || exifData.isEmpty) {
        return companion;
      }

      // 解析 EXIF 字段
      return _mergeExif(companion, exifData);
    } catch (e) {
      return null;
    }
  }

  /// 将 EXIF IFD 数据合并到 PhotosCompanion
  PhotosCompanion _mergeExif(
    PhotosCompanion base,
    Map<String, IfdTag> exif,
  ) {
    String? cameraMake = _getString(exif, 'Image Make');
    String? cameraModel = _getString(exif, 'Image Model');
    String? lensModel = _getString(exif, 'EXIF LensModel');
    double? focalLength = _getRational(exif, 'EXIF FocalLength')?.toDouble();
    double? focalLength35mm =
        _getRational(exif, 'EXIF FocalLengthIn35mmFilm')?.toDouble();
    double? aperture = _getRational(exif, 'EXIF FNumber')?.toDouble();
    double? iso = _getDouble(exif, 'EXIF ISOSpeedRatings');
    String? shutterSpeed = _formatShutterSpeed(exif);
    double? exposureBias = _getRational(exif, 'EXIF ExposureBiasValue')?.toDouble();
    String? meteringMode = _getMeteringMode(exif);
    String? whiteBalance = _getWhiteBalance(exif);
    String? flash = _getFlashDescription(exif);
    String? artist = _getString(exif, 'Image Artist');
    String? copyright = _getString(exif, 'Image Copyright');
    DateTime? dateTaken = _getDateTime(exif);
    double? latitude = _getGpsCoordinate(exif, 'GPS GPSLatitude',
        _getString(exif, 'GPS GPSLatitudeRef'));
    double? longitude = _getGpsCoordinate(exif, 'GPS GPSLongitude',
        _getString(exif, 'GPS GPSLongitudeRef'));
    double? altitude = _getGpsAltitude(exif);

    return PhotosCompanion(
      width: base.width,
      height: base.height,
      mimeType: base.mimeType,
      dateTaken: dateTaken != null ? Value(dateTaken) : const Value.absent(),
      cameraMake:
          cameraMake != null ? Value(cameraMake) : const Value.absent(),
      cameraModel:
          cameraModel != null ? Value(cameraModel) : const Value.absent(),
      lensModel: lensModel != null ? Value(lensModel) : const Value.absent(),
      focalLength:
          focalLength != null ? Value(focalLength) : const Value.absent(),
      focalLength35mm: focalLength35mm != null
          ? Value(focalLength35mm)
          : const Value.absent(),
      aperture: aperture != null ? Value(aperture) : const Value.absent(),
      iso: iso != null ? Value(iso) : const Value.absent(),
      shutterSpeed:
          shutterSpeed != null ? Value(shutterSpeed) : const Value.absent(),
      exposureBias: exposureBias != null
          ? Value(exposureBias)
          : const Value.absent(),
      meteringMode: meteringMode != null
          ? Value(meteringMode)
          : const Value.absent(),
      whiteBalance: whiteBalance != null
          ? Value(whiteBalance)
          : const Value.absent(),
      flash: flash != null ? Value(flash) : const Value.absent(),
      artist: artist != null ? Value(artist) : const Value.absent(),
      copyright: copyright != null ? Value(copyright) : const Value.absent(),
      latitude: latitude != null ? Value(latitude) : const Value.absent(),
      longitude: longitude != null ? Value(longitude) : const Value.absent(),
      altitude: altitude != null ? Value(altitude) : const Value.absent(),
    );
  }

  /// 从 EXIF 获取字符串值
  String? _getString(Map<String, IfdTag> exif, String key) {
    final tag = exif[key];
    if (tag == null) return null;
    final vals = tag.values;
    if (vals.length > 0) {
      // printable 字段对于 ASCII 类型直接是解码后的字符串值
      // （exif 包的 ValuesToPrintable 用 utf8.decode 解码 IfdBytes）
      // 对于其他类型是值的 toString()
      // 直接使用 printable，不做分割处理
      final printable = tag.printable.trim();
      // 去除末尾可能的多余 null 字符或空白
      return printable.replaceAll(RegExp(r'[\x00]+$'), '').trim();
    }
    return null;
  }

  /// 从 EXIF 获取 Rational 值（如光圈 FNumber、焦距 FocalLength）
  Ratio? _getRational(Map<String, IfdTag> exif, String key) {
    final tag = exif[key];
    if (tag == null) return null;
    final vals = tag.values;
    if (vals is IfdRatios && vals.ratios.isNotEmpty) {
      return vals.ratios.first;
    }
    return null;
  }

  /// 从 EXIF 获取 double 值（如 ISO）
  double? _getDouble(Map<String, IfdTag> exif, String key) {
    final tag = exif[key];
    if (tag == null) return null;
    final vals = tag.values;
    if (vals is IfdRatios && vals.ratios.isNotEmpty) {
      return vals.ratios.first.toDouble();
    }
    if (vals is IfdInts && vals.ints.isNotEmpty) {
      return vals.ints.first.toDouble();
    }
    return null;
  }

  /// 从 EXIF 获取 int 值
  int? _getInt(Map<String, IfdTag> exif, String key) {
    final tag = exif[key];
    if (tag == null) return null;
    final vals = tag.values;
    if (vals is IfdInts && vals.ints.isNotEmpty) {
      return vals.ints.first;
    }
    if (vals is IfdRatios && vals.ratios.isNotEmpty) {
      return vals.ratios.first.toInt();
    }
    return null;
  }

  /// 从 EXIF 获取拍摄日期时间
  DateTime? _getDateTime(Map<String, IfdTag> exif) {
    final tag = exif['EXIF DateTimeOriginal'] ?? exif['Image DateTime'];
    if (tag == null) return null;
    // exif 包的 DateTime 标签 printable 格式: "YYYY:MM:DD HH:MM:SS"
    final printable = tag.printable;
    try {
      final parts = printable.split(' ');
      if (parts.length != 2) return null;
      final dateParts = parts[0].split(':');
      final timeParts = parts[1].split(':');
      if (dateParts.length != 3 || timeParts.length != 3) return null;
      return DateTime(
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(dateParts[2]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
        int.parse(timeParts[2]),
      );
    } catch (_) {
      return null;
    }
  }

  /// 格式化快门速度
  String? _formatShutterSpeed(Map<String, IfdTag> exif) {
    final ratio = _getRational(exif, 'EXIF ExposureTime');
    if (ratio == null) return null;
    final seconds = ratio.toDouble();
    if (seconds >= 1) {
      return '${seconds.toStringAsFixed(seconds == seconds.roundToDouble() ? 0 : 1)}s';
    } else {
      // 分数表示: 1/N
      if (ratio.numerator == 1) {
        return '1/${ratio.denominator}';
      }
      // 约分
      final g = _gcd(ratio.numerator, ratio.denominator);
      return '${ratio.numerator ~/ g}/${ratio.denominator ~/ g}';
    }
  }

  int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

  /// 获取测光模式描述
  String? _getMeteringMode(Map<String, IfdTag> exif) {
    final val = _getInt(exif, 'EXIF MeteringMode');
    if (val == null) return null;
    return switch (val) {
      0 => '未知',
      1 => '平均测光',
      2 => '中央重点平均测光',
      3 => '点测光',
      4 => '多点测光',
      5 => '多区测光',
      6 => '局部测光',
      _ => '其他',
    };
  }

  /// 获取白平衡描述
  String? _getWhiteBalance(Map<String, IfdTag> exif) {
    final val = _getInt(exif, 'EXIF WhiteBalance');
    if (val == null) return null;
    return switch (val) {
      0 => '自动',
      1 => '手动',
      _ => '未知',
    };
  }

  /// 获取闪光灯描述
  String? _getFlashDescription(Map<String, IfdTag> exif) {
    final val = _getInt(exif, 'EXIF Flash');
    if (val == null) return null;
    // EXIF Flash 是位域
    if (val == 0) return '未闪光';
    final fired = (val & 1) != 0;
    return fired ? '闪光' : '未闪光';
  }

  /// 解析 GPS 坐标（纬度/经度）
  double? _getGpsCoordinate(
    Map<String, IfdTag> exif,
    String key,
    String? ref,
  ) {
    final tag = exif[key];
    if (tag == null) return null;
    final vals = tag.values;
    if (vals is IfdRatios && vals.ratios.length >= 3) {
      // GPS 坐标: [度, 分, 秒] — 每个 Ratio
      final degrees = vals.ratios[0].toDouble();
      final minutes = vals.ratios[1].toDouble();
      final seconds = vals.ratios[2].toDouble();
      var decimal = degrees + minutes / 60 + seconds / 3600;
      // S 和 W 为负值
      if (ref == 'S' || ref == 'W') decimal = -decimal;
      return decimal;
    }
    return null;
  }

  /// 解析 GPS 海拔
  double? _getGpsAltitude(Map<String, IfdTag> exif) {
    final ratio = _getRational(exif, 'GPS GPSAltitude');
    if (ratio == null) return null;
    var alt = ratio.toDouble();
    // GPSAltitudeRef: 0 = 海平面以上, 1 = 海平面以下
    final refVal = _getInt(exif, 'GPS GPSAltitudeRef');
    if (refVal != null && refVal == 1) alt = -alt;
    return alt;
  }

  /// 获取图像基本信息（从文件头字节解析）
  _ImageInfo _getImageInfo(List<int> bytes, String filePath) {
    String? mimeType;
    int? width;
    int? height;

    if (bytes.length >= 2) {
      // JPEG: FF D8
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        mimeType = 'image/jpeg';
        final dims = _parseJpegDimensions(bytes);
        width = dims.$1;
        height = dims.$2;
      }
      // PNG: 89 50 4E 47
      else if (bytes.length >= 4 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        mimeType = 'image/png';
        if (bytes.length >= 24) {
          width = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
          height = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
        }
      }
      // WebP: 52 49 46 46 ... 57 45 42 50
      else if (bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        mimeType = 'image/webp';
      }
    }

    // 根据扩展名推断 MIME
    if (mimeType == null) {
      final ext = filePath.split('.').last.toLowerCase();
      mimeType = switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'tif' || 'tiff' => 'image/tiff',
        'webp' => 'image/webp',
        'bmp' => 'image/bmp',
        'gif' => 'image/gif',
        // HEIC / HEIF / AVIF
        'heic' || 'heif' || 'hif' => 'image/heic',
        'avif' => 'image/avif',
        // Canon
        'cr2' => 'image/x-canon-cr2',
        'cr3' => 'image/x-canon-cr3',
        'crw' => 'image/x-canon-crw',
        // Nikon
        'nef' => 'image/x-nikon-nef',
        'nrw' => 'image/x-nikon-nrw',
        // Sony
        'arw' => 'image/x-sony-arw',
        'sr2' => 'image/x-sony-sr2',
        'srf' => 'image/x-sony-srf',
        // Adobe
        'dng' => 'image/x-adobe-dng',
        // Fujifilm
        'raf' => 'image/x-fuji-raf',
        // Panasonic
        'rw2' => 'image/x-panasonic-rw2',
        'raw' => 'image/x-panasonic-raw',
        // Olympus
        'orf' => 'image/x-olympus-orf',
        // Pentax
        'pef' => 'image/x-pentax-pef',
        // Samsung
        'srw' => 'image/x-samsung-srw',
        // Minolta
        'mrw' => 'image/x-minolta-mrw',
        // Sigma
        'x3f' => 'image/x-sigma-x3f',
        // Hasselblad
        '3fr' => 'image/x-hasselblad-3fr',
        'fff' => 'image/x-hasselblad-fff',
        // Phase One / Leaf
        'iiq' => 'image/x-phaseone-iiq',
        'mos' => 'image/x-leaf-mos',
        // Leica
        'rwl' => 'image/x-leica-rwl',
        // Kodak
        'kdc' => 'image/x-kodak-kdc',
        'dcr' => 'image/x-kodak-dcr',
        // Red
        'r3d' => 'image/x-red-r3d',
        _ => 'application/octet-stream',
      };
    }

    return _ImageInfo(width: width, height: height, mimeType: mimeType);
  }

  /// 解析 JPEG 图像尺寸
  (int?, int?) _parseJpegDimensions(List<int> bytes) {
    try {
      int i = 2; // 跳过 SOI 标记
      while (i < bytes.length - 1) {
        if (bytes[i] != 0xFF) {
          i++;
          continue;
        }
        final marker = bytes[i + 1];
        // SOF0-SOF15 (不含 SOF4, SOF8, SOF12)
        if (marker >= 0xC0 && marker <= 0xCF &&
            marker != 0xC4 && marker != 0xC8 && marker != 0xCC) {
          if (i + 9 < bytes.length) {
            final height = (bytes[i + 5] << 8) | bytes[i + 6];
            final width = (bytes[i + 7] << 8) | bytes[i + 8];
            return (width, height);
          }
          return (null, null);
        }
        // 跳过其他标记
        if (i + 3 < bytes.length) {
          final length = (bytes[i + 2] << 8) | bytes[i + 3];
          i += 2 + length;
        } else {
          break;
        }
      }
    } catch (_) {}
    return (null, null);
  }
}

/// 图像基本信息
class _ImageInfo {
  final int? width;
  final int? height;
  final String? mimeType;

  const _ImageInfo({this.width, this.height, this.mimeType});
}