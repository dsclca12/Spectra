import '../database/app_database.dart';

/// 照片数据模型扩展 — 提供便捷的领域方法
extension PhotoX on Photo {
  /// 是否已评分
  bool get isRated => rating > 0;

  /// 是否为 Pick
  bool get isPick => pickLabel == 1;

  /// 是否为 Reject
  bool get isReject => pickLabel == 2;

  /// 是否有色标
  bool get hasColorLabel => colorLabel > 0;

  /// 是否有缩略图
  bool get hasThumbnail => thumbnailStatus == 2;

  /// 文件扩展名（小写，不含点）
  String get extension {
    final dotIndex = fileName.lastIndexOf('.');
    return dotIndex >= 0 ? fileName.substring(dotIndex + 1).toLowerCase() : '';
  }

  /// 是否为 RAW 格式
  bool get isRaw {
    const rawExtensions = {
      'cr2', 'cr3', 'crw',   // Canon
      'nef', 'nrw',          // Nikon
      'arw', 'sr2', 'srf',   // Sony
      'dng',                 // Adobe
      'raf',                 // Fujifilm
      'rw2', 'raw',          // Panasonic
      'orf',                 // Olympus
      'pef',                 // Pentax
      'srw',                 // Samsung
      'mrw',                 // Minolta
      'x3f',                 // Sigma
      '3fr', 'fff',          // Hasselblad
      'iiq', 'mos',          // Phase One / Leaf
      'rwl',                 // Leica
      'kdc', 'dcr',          // Kodak
      'r3d',                 // Red
    };
    return rawExtensions.contains(extension);
  }

  /// 是否为 HEIC/HEIF/AVIF 格式
  bool get isHeic {
    const heicExtensions = {'heic', 'heif', 'hif', 'avif'};
    return heicExtensions.contains(extension);
  }

  /// 是否需要外部解码器（非 Flutter 原生支持格式）
  bool get requiresExternalDecoder {
    const externalExtensions = {
      // HEIC / HEIF / AVIF
      'heic', 'heif', 'hif', 'avif',
      // TIFF
      'tif', 'tiff',
      // 所有 RAW 格式
      'cr2', 'cr3', 'crw', 'nef', 'nrw', 'arw', 'sr2', 'srf',
      'dng', 'raf', 'rw2', 'raw', 'orf', 'pef', 'srw', 'mrw',
      'x3f', '3fr', 'fff', 'iiq', 'mos', 'rwl', 'kdc', 'dcr', 'r3d',
    };
    return externalExtensions.contains(extension);
  }

  /// 格式化的文件大小
  String get formattedFileSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// 格式化的分辨率
  String get formattedResolution {
    if (width == null || height == null) return '未知';
    final mp = (width! * height!) / 1000000;
    return '${width}×${height} (${mp.toStringAsFixed(1)}MP)';
  }

  /// 光圈格式化
  String get formattedAperture =>
      aperture != null ? 'f/${aperture!.toStringAsFixed(1)}' : '未知';

  /// 创建可变副本
  Photo copyWith({
    int? id,
    int? folderId,
    String? path,
    String? fileName,
    String? fileHash,
    int? fileSize,
    DateTime? modifiedAt,
    DateTime? importedAt,
    int? width,
    int? height,
    int? orientation,
    String? mimeType,
    DateTime? dateTaken,
    String? cameraMake,
    String? cameraModel,
    String? lensModel,
    double? focalLength,
    double? focalLength35mm,
    double? aperture,
    double? iso,
    String? shutterSpeed,
    double? exposureBias,
    String? meteringMode,
    String? whiteBalance,
    String? flash,
    String? artist,
    String? copyright,
    double? latitude,
    double? longitude,
    double? altitude,
    int? rating,
    int? pickLabel,
    int? colorLabel,
    String? iptcTitle,
    String? iptcDescription,
    String? iptcKeywords,
    String? iptcCredit,
    String? iptcByline,
    int? thumbnailStatus,
    DateTime? thumbnailGeneratedAt,
    int? syncStatus,
  }) {
    return Photo(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      path: path ?? this.path,
      fileName: fileName ?? this.fileName,
      fileHash: fileHash ?? this.fileHash,
      fileSize: fileSize ?? this.fileSize,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      importedAt: importedAt ?? this.importedAt,
      width: width ?? this.width,
      height: height ?? this.height,
      orientation: orientation ?? this.orientation,
      mimeType: mimeType ?? this.mimeType,
      dateTaken: dateTaken ?? this.dateTaken,
      cameraMake: cameraMake ?? this.cameraMake,
      cameraModel: cameraModel ?? this.cameraModel,
      lensModel: lensModel ?? this.lensModel,
      focalLength: focalLength ?? this.focalLength,
      focalLength35mm: focalLength35mm ?? this.focalLength35mm,
      aperture: aperture ?? this.aperture,
      iso: iso ?? this.iso,
      shutterSpeed: shutterSpeed ?? this.shutterSpeed,
      exposureBias: exposureBias ?? this.exposureBias,
      meteringMode: meteringMode ?? this.meteringMode,
      whiteBalance: whiteBalance ?? this.whiteBalance,
      flash: flash ?? this.flash,
      artist: artist ?? this.artist,
      copyright: copyright ?? this.copyright,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      rating: rating ?? this.rating,
      pickLabel: pickLabel ?? this.pickLabel,
      colorLabel: colorLabel ?? this.colorLabel,
      iptcTitle: iptcTitle ?? this.iptcTitle,
      iptcDescription: iptcDescription ?? this.iptcDescription,
      iptcKeywords: iptcKeywords ?? this.iptcKeywords,
      iptcCredit: iptcCredit ?? this.iptcCredit,
      iptcByline: iptcByline ?? this.iptcByline,
      thumbnailStatus: thumbnailStatus ?? this.thumbnailStatus,
      thumbnailGeneratedAt:
          thumbnailGeneratedAt ?? this.thumbnailGeneratedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}