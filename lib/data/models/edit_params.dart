/// Non-destructive photo editing parameters.
///
/// All edit parameters are stored in the database as data classes;
/// the original files are never modified. When exporting,
/// [ImageEditService] bakes the final image.
///
/// Parameter ranges reference Lightroom / Capture One sliders:
/// - Exposure: -2.0 ~ +2.0 EV (0 = no adjustment)
/// - Contrast: -100 ~ +100 (0 = no adjustment)
/// - Highlights: -100 ~ +100
/// - Shadows: -100 ~ +100
/// - Whites: -100 ~ +100
/// - Blacks: -100 ~ +100
/// - Saturation: -100 ~ +100
/// - Vibrance: -100 ~ +100
/// - Temperature: -100 ~ +100 (negative=cool, positive=warm)
/// - Tint: -100 ~ +100 (negative=green, positive=magenta)
/// - Sharpness: 0 ~ 100
/// - Vignette: -100 ~ +100 (negative=darken, positive=brighten)
/// - Grain: 0 ~ 100
/// - Fade: 0 ~ 100
class EditParams {
  // ─── Basic adjustments ───
  /// Exposure compensation (EV), range -2.0 ~ +2.0.
  final double exposure;

  /// Contrast, range -100 ~ +100.
  final double contrast;

  /// Highlight recovery, range -100 ~ +100.
  final double highlights;

  /// Shadow brightening, range -100 ~ +100.
  final double shadows;

  /// Whites, range -100 ~ +100.
  final double whites;

  /// Blacks, range -100 ~ +100.
  final double blacks;

  // ─── Color adjustments ───
  /// Saturation, range -100 ~ +100.
  final double saturation;

  /// Vibrance, range -100 ~ +100.
  final double vibrance;

  /// Color temperature, range -100 ~ +100 (negative=cool/blue, positive=warm/yellow).
  final double temperature;

  /// Tint, range -100 ~ +100 (negative=green, positive=magenta).
  final double tint;

  // ─── Effects ───
  /// Sharpness, range 0 ~ 100.
  final double sharpness;

  /// Vignette, range -100 ~ +100 (negative=darken, positive=brighten).
  final double vignette;

  /// Grain (film grain), range 0 ~ 100.
  final double grain;

  /// Fade (desaturate shadows), range 0 ~ 100.
  final double fade;

  // ─── Re-composition ───
  /// Crop X offset (0.0 ~ 1.0, proportional to original width).
  final double cropX;

  /// Crop Y offset (0.0 ~ 1.0, proportional to original height).
  final double cropY;

  /// Crop width (0.0 ~ 1.0, proportional to original width).
  final double cropWidth;

  /// Crop height (0.0 ~ 1.0, proportional to original height).
  final double cropHeight;

  /// Rotation angle (0, 90, 180, 270 degrees).
  final int rotation;

  /// Horizontal flip.
  final bool flipH;

  /// Vertical flip.
  final bool flipV;

  const EditParams({
    this.exposure = 0.0,
    this.contrast = 0.0,
    this.highlights = 0.0,
    this.shadows = 0.0,
    this.whites = 0.0,
    this.blacks = 0.0,
    this.saturation = 0.0,
    this.vibrance = 0.0,
    this.temperature = 0.0,
    this.tint = 0.0,
    this.sharpness = 0.0,
    this.vignette = 0.0,
    this.grain = 0.0,
    this.fade = 0.0,
    this.cropX = 0.0,
    this.cropY = 0.0,
    this.cropWidth = 1.0,
    this.cropHeight = 1.0,
    this.rotation = 0,
    this.flipH = false,
    this.flipV = false,
  });

  /// Default parameters (no adjustment).
  static const EditParams defaultParams = EditParams();

  /// Whether any edits have been made (non-default values).
  bool get hasEdits {
    return exposure != 0.0 ||
        contrast != 0.0 ||
        highlights != 0.0 ||
        shadows != 0.0 ||
        whites != 0.0 ||
        blacks != 0.0 ||
        saturation != 0.0 ||
        vibrance != 0.0 ||
        temperature != 0.0 ||
        tint != 0.0 ||
        sharpness != 0.0 ||
        vignette != 0.0 ||
        grain != 0.0 ||
        fade != 0.0 ||
        cropX != 0.0 ||
        cropY != 0.0 ||
        cropWidth != 1.0 ||
        cropHeight != 1.0 ||
        rotation != 0 ||
        flipH ||
        flipV;
  }

  /// 是否有色彩调整（用于判断是否需要应用 shader）
  bool get hasColorEdits {
    return exposure != 0.0 ||
        contrast != 0.0 ||
        highlights != 0.0 ||
        shadows != 0.0 ||
        whites != 0.0 ||
        blacks != 0.0 ||
        saturation != 0.0 ||
        vibrance != 0.0 ||
        temperature != 0.0 ||
        tint != 0.0 ||
        vignette != 0.0 ||
        grain != 0.0 ||
        fade != 0.0;
  }

  /// 是否有几何变换（裁剪/旋转/翻转）
  bool get hasGeometryEdits {
    return cropX != 0.0 ||
        cropY != 0.0 ||
        cropWidth != 1.0 ||
        cropHeight != 1.0 ||
        rotation != 0 ||
        flipH ||
        flipV;
  }

  /// 创建可变副本
  EditParams copyWith({
    double? exposure,
    double? contrast,
    double? highlights,
    double? shadows,
    double? whites,
    double? blacks,
    double? saturation,
    double? vibrance,
    double? temperature,
    double? tint,
    double? sharpness,
    double? vignette,
    double? grain,
    double? fade,
    double? cropX,
    double? cropY,
    double? cropWidth,
    double? cropHeight,
    int? rotation,
    bool? flipH,
    bool? flipV,
  }) {
    return EditParams(
      exposure: exposure ?? this.exposure,
      contrast: contrast ?? this.contrast,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      whites: whites ?? this.whites,
      blacks: blacks ?? this.blacks,
      saturation: saturation ?? this.saturation,
      vibrance: vibrance ?? this.vibrance,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      sharpness: sharpness ?? this.sharpness,
      vignette: vignette ?? this.vignette,
      grain: grain ?? this.grain,
      fade: fade ?? this.fade,
      cropX: cropX ?? this.cropX,
      cropY: cropY ?? this.cropY,
      cropWidth: cropWidth ?? this.cropWidth,
      cropHeight: cropHeight ?? this.cropHeight,
      rotation: rotation ?? this.rotation,
      flipH: flipH ?? this.flipH,
      flipV: flipV ?? this.flipV,
    );
  }

  /// 序列化为 JSON（用于存储/导出）
  Map<String, dynamic> toJson() {
    return {
      'exposure': exposure,
      'contrast': contrast,
      'highlights': highlights,
      'shadows': shadows,
      'whites': whites,
      'blacks': blacks,
      'saturation': saturation,
      'vibrance': vibrance,
      'temperature': temperature,
      'tint': tint,
      'sharpness': sharpness,
      'vignette': vignette,
      'grain': grain,
      'fade': fade,
      'cropX': cropX,
      'cropY': cropY,
      'cropWidth': cropWidth,
      'cropHeight': cropHeight,
      'rotation': rotation,
      'flipH': flipH,
      'flipV': flipV,
    };
  }

  /// 从 JSON 反序列化
  factory EditParams.fromJson(Map<String, dynamic> json) {
    return EditParams(
      exposure: (json['exposure'] as num?)?.toDouble() ?? 0.0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 0.0,
      highlights: (json['highlights'] as num?)?.toDouble() ?? 0.0,
      shadows: (json['shadows'] as num?)?.toDouble() ?? 0.0,
      whites: (json['whites'] as num?)?.toDouble() ?? 0.0,
      blacks: (json['blacks'] as num?)?.toDouble() ?? 0.0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 0.0,
      vibrance: (json['vibrance'] as num?)?.toDouble() ?? 0.0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.0,
      tint: (json['tint'] as num?)?.toDouble() ?? 0.0,
      sharpness: (json['sharpness'] as num?)?.toDouble() ?? 0.0,
      vignette: (json['vignette'] as num?)?.toDouble() ?? 0.0,
      grain: (json['grain'] as num?)?.toDouble() ?? 0.0,
      fade: (json['fade'] as num?)?.toDouble() ?? 0.0,
      cropX: (json['cropX'] as num?)?.toDouble() ?? 0.0,
      cropY: (json['cropY'] as num?)?.toDouble() ?? 0.0,
      cropWidth: (json['cropWidth'] as num?)?.toDouble() ?? 1.0,
      cropHeight: (json['cropHeight'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toInt() ?? 0,
      flipH: json['flipH'] as bool? ?? false,
      flipV: json['flipV'] as bool? ?? false,
    );
  }

  /// 对比两个 [EditParams] 的差异，生成可读的操作描述。
  ///
  /// 用于在历史记录中显示「曝光 +0.5」「对比度 +20」等标签。
  /// 当 [previous] 不为 null 时，用 [previous] 表示「上一次记录的参数」，
  /// 以累计变化值；否则直接用 [oldParams] 作为基准。
  static String describeDifference(
    EditParams oldParams,
    EditParams newParams, {
    EditParams? previous,
  }) {
    // 找出所有差异字段
    final changes = <String>[];

    void check(String label, double old, double cur) {
      if (old == cur) return;
      final diff = cur - old;
      final sign = diff >= 0 ? '+' : '';
      final val = diff.abs() < 1 ? diff.toStringAsFixed(2) : diff.toStringAsFixed(1);
      changes.add('$label $sign$val');
    }

    void checkBool(String label, bool old, bool cur) {
      if (old == cur) return;
      changes.add(cur ? '$label ✓' : '$label ✗');
    }

    void checkInt(String label, int old, int cur) {
      if (old == cur) return;
      changes.add('$label $cur°');
    }

    check('曝光', oldParams.exposure, newParams.exposure);
    check('对比度', oldParams.contrast, newParams.contrast);
    check('高光', oldParams.highlights, newParams.highlights);
    check('阴影', oldParams.shadows, newParams.shadows);
    check('白色', oldParams.whites, newParams.whites);
    check('黑色', oldParams.blacks, newParams.blacks);
    check('饱和度', oldParams.saturation, newParams.saturation);
    check('自然饱和度', oldParams.vibrance, newParams.vibrance);
    check('色温', oldParams.temperature, newParams.temperature);
    check('色调', oldParams.tint, newParams.tint);
    check('锐化', oldParams.sharpness, newParams.sharpness);
    check('暗角', oldParams.vignette, newParams.vignette);
    check('颗粒', oldParams.grain, newParams.grain);
    check('褪色', oldParams.fade, newParams.fade);
    checkBool('水平翻转', oldParams.flipH, newParams.flipH);
    checkBool('垂直翻转', oldParams.flipV, newParams.flipV);
    if (oldParams.rotation != newParams.rotation) {
      checkInt('旋转', oldParams.rotation, newParams.rotation);
    }
    if (oldParams.cropWidth != newParams.cropWidth ||
        oldParams.cropHeight != newParams.cropHeight ||
        oldParams.cropX != newParams.cropX ||
        oldParams.cropY != newParams.cropY) {
      changes.add('裁剪');
    }

    return changes.isEmpty ? '编辑' : changes.join('; ');
  }

  @override
  String toString() {
    return 'EditParams(exposure: $exposure, contrast: $contrast, '
        'highlights: $highlights, shadows: $shadows, '
        'saturation: $saturation, vibrance: $vibrance, '
        'temperature: $temperature, tint: $tint, '
        'sharpness: $sharpness, vignette: $vignette, '
        'crop: ($cropX, $cropY, $cropWidth×$cropHeight), '
        'rotation: $rotation, flipH: $flipH, flipV: $flipV)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EditParams &&
        other.exposure == exposure &&
        other.contrast == contrast &&
        other.highlights == highlights &&
        other.shadows == shadows &&
        other.whites == whites &&
        other.blacks == blacks &&
        other.saturation == saturation &&
        other.vibrance == vibrance &&
        other.temperature == temperature &&
        other.tint == tint &&
        other.sharpness == sharpness &&
        other.vignette == vignette &&
        other.grain == grain &&
        other.fade == fade &&
        other.cropX == cropX &&
        other.cropY == cropY &&
        other.cropWidth == cropWidth &&
        other.cropHeight == cropHeight &&
        other.rotation == rotation &&
        other.flipH == flipH &&
        other.flipV == flipV;
  }

  @override
  int get hashCode =>
      exposure.hashCode ^
      contrast.hashCode ^
      highlights.hashCode ^
      shadows.hashCode ^
      whites.hashCode ^
      blacks.hashCode ^
      saturation.hashCode ^
      vibrance.hashCode ^
      temperature.hashCode ^
      tint.hashCode ^
      sharpness.hashCode ^
      vignette.hashCode ^
      grain.hashCode ^
      fade.hashCode ^
      cropX.hashCode ^
      cropY.hashCode ^
      cropWidth.hashCode ^
      cropHeight.hashCode ^
      rotation.hashCode ^
      flipH.hashCode ^
      flipV.hashCode;
}