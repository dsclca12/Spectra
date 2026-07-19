// SPDX-License-Identifier: Apache-2.0

import 'package:drift/drift.dart';

/// Main photos table.
class Photos extends Table {
  // ─── Primary key ───
  IntColumn get id => integer().autoIncrement()();

  // ─── References ───
  IntColumn get folderId => integer().references(Folders, #id).nullable()();

  // ─── File info ───
  TextColumn get path => text().unique()();
  TextColumn get fileName => text()();
  TextColumn get fileHash => text()();
  IntColumn get fileSize => integer()();
  DateTimeColumn get modifiedAt => dateTime()();
  DateTimeColumn get importedAt => dateTime()();

  // ─── Image info ───
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get orientation => integer().nullable()();
  TextColumn get mimeType => text().nullable()();

  // ─── Capture parameters (EXIF) ───
  DateTimeColumn get dateTaken => dateTime().nullable()();
  TextColumn get cameraMake => text().nullable()();
  TextColumn get cameraModel => text().nullable()();
  TextColumn get lensModel => text().nullable()();
  RealColumn get focalLength => real().nullable()();
  RealColumn get focalLength35mm => real().nullable()();
  RealColumn get aperture => real().nullable()();
  RealColumn get iso => real().nullable()();
  TextColumn get shutterSpeed => text().nullable()();
  RealColumn get exposureBias => real().nullable()();
  TextColumn get meteringMode => text().nullable()();
  TextColumn get whiteBalance => text().nullable()();
  TextColumn get flash => text().nullable()();
  TextColumn get artist => text().nullable()();
  TextColumn get copyright => text().nullable()();

  // ─── GPS ───
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  RealColumn get altitude => real().nullable()();

  // ─── Classification ───
  IntColumn get rating => integer().withDefault(const Constant(0))();
  IntColumn get pickLabel => integer().withDefault(const Constant(0))();
  IntColumn get colorLabel => integer().withDefault(const Constant(0))();

  // ─── IPTC metadata ───
  TextColumn get iptcTitle => text().nullable()();
  TextColumn get iptcDescription => text().nullable()();
  TextColumn get iptcKeywords => text().nullable()();
  TextColumn get iptcCredit => text().nullable()();
  TextColumn get iptcByline => text().nullable()();

  // ─── Thumbnail status ───
  IntColumn get thumbnailStatus => integer().withDefault(const Constant(0))();
  DateTimeColumn get thumbnailGeneratedAt => dateTime().nullable()();

  // ─── Sync status ───
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
}

/// Folders table.
class Folders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text().unique()();
  TextColumn get name => text()();
  IntColumn get parentId =>
      integer().references(Folders, #id).nullable()();
  IntColumn get photoCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastScannedAt => dateTime().nullable()();
  IntColumn get isWatched => integer().withDefault(const Constant(1))();
}

/// Tags table (hierarchical).
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  IntColumn get parentId => integer().references(Tags, #id).nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get color => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
}

/// Photo-to-tag junction table.
class PhotoTags extends Table {
  IntColumn get photoId =>
      integer().references(Photos, #id, onDelete: KeyAction.cascade)();
  IntColumn get tagId =>
      integer().references(Tags, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {photoId, tagId};
}

/// Collections table.
class Collections extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get type => text()(); // 'manual' or 'smart'
  TextColumn get ruleJson => text().nullable()();
  TextColumn get iconName => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// Collection-to-photo junction table.
class CollectionPhotos extends Table {
  IntColumn get collectionId =>
      integer().references(Collections, #id, onDelete: KeyAction.cascade)();
  IntColumn get photoId =>
      integer().references(Photos, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {collectionId, photoId};
}

/// Application settings table.
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  TextColumn get group => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Photo edit parameters table — non-destructive editing.
///
/// Each photo has at most one edit parameter record. The original file
/// is never modified; ImageEditService bakes the final image on export.
class PhotoEdits extends Table {
  /// Associated photo ID (primary key + foreign key, cascade on delete).
  IntColumn get photoId =>
      integer().references(Photos, #id, onDelete: KeyAction.cascade)();

  // ─── Basic adjustments ───
  /// Exposure compensation (EV), range -2.0 ~ +2.0.
  RealColumn get exposure => real().withDefault(const Constant(0.0))();

  /// Contrast, range -100 ~ +100.
  RealColumn get contrast => real().withDefault(const Constant(0.0))();

  /// Highlight recovery, range -100 ~ +100.
  RealColumn get highlights => real().withDefault(const Constant(0.0))();

  /// Shadow brightening, range -100 ~ +100.
  RealColumn get shadows => real().withDefault(const Constant(0.0))();

  /// Whites, range -100 ~ +100.
  RealColumn get whites => real().withDefault(const Constant(0.0))();

  /// Blacks, range -100 ~ +100.
  RealColumn get blacks => real().withDefault(const Constant(0.0))();

  // ─── Color adjustments ───
  /// Saturation, range -100 ~ +100.
  RealColumn get saturation => real().withDefault(const Constant(0.0))();

  /// Vibrance, range -100 ~ +100.
  RealColumn get vibrance => real().withDefault(const Constant(0.0))();

  /// Color temperature, range -100 ~ +100 (negative=cool, positive=warm).
  RealColumn get temperature => real().withDefault(const Constant(0.0))();

  /// Tint, range -100 ~ +100 (negative=green, positive=magenta).
  RealColumn get tint => real().withDefault(const Constant(0.0))();

  // ─── Effects ───
  /// Sharpness, range 0 ~ 100.
  RealColumn get sharpness => real().withDefault(const Constant(0.0))();

  /// Vignette, range -100 ~ +100.
  RealColumn get vignette => real().withDefault(const Constant(0.0))();

  /// Grain, range 0 ~ 100.
  RealColumn get grain => real().withDefault(const Constant(0.0))();

  /// Fade, range 0 ~ 100.
  RealColumn get fade => real().withDefault(const Constant(0.0))();

  // ─── Re-composition ───
  /// Crop X offset (0.0 ~ 1.0).
  RealColumn get cropX => real().withDefault(const Constant(0.0))();

  /// Crop Y offset (0.0 ~ 1.0).
  RealColumn get cropY => real().withDefault(const Constant(0.0))();

  /// Crop width (0.0 ~ 1.0).
  RealColumn get cropWidth => real().withDefault(const Constant(1.0))();

  /// Crop height (0.0 ~ 1.0).
  RealColumn get cropHeight => real().withDefault(const Constant(1.0))();

  /// Rotation angle (0, 90, 180, 270).
  IntColumn get rotation => integer().withDefault(const Constant(0))();

  /// Horizontal flip.
  IntColumn get flipH => integer().withDefault(const Constant(0))();

  /// Vertical flip.
  IntColumn get flipV => integer().withDefault(const Constant(0))();

  /// Last modification time.
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {photoId};
}

/// Edit snapshots table — stores named edit parameter snapshots.
///
/// Users can manually create named snapshots and restore edit state
/// from any snapshot. Snapshots are persisted across sessions.
class EditSnapshots extends Table {
  /// Auto-increment primary key.
  IntColumn get id => integer().autoIncrement()();

  /// Associated photo ID.
  IntColumn get photoId =>
      integer().references(Photos, #id, onDelete: KeyAction.cascade)();

  /// 快照名称（用户命名）
  TextColumn get name => text()();

  /// EditParams 序列化为 JSON
  TextColumn get paramsJson => text()();

  /// 是否为系统自动创建的快照
  BoolColumn get isAuto => boolean().withDefault(const Constant(false))();

  /// 创建时间
  DateTimeColumn get createdAt => dateTime()();
}

/// 编辑操作历史表 — 记录每次编辑操作后的完整参数
///
/// 自动记录编辑操作（防抖），可回退到任意历史节点。
/// 每张照片保留最近 N 条记录（默认 200 条）。
class EditHistory extends Table {
  /// 自增主键
  IntColumn get id => integer().autoIncrement()();

  /// 关联的照片 ID
  IntColumn get photoId =>
      integer().references(Photos, #id, onDelete: KeyAction.cascade)();

  /// 操作后的完整 EditParams（JSON）
  TextColumn get paramsJson => text()();

  /// 操作描述（如 "曝光 +0.5 EV"、"自动调整"）
  TextColumn get actionLabel => text().nullable()();

  /// 操作时间
  DateTimeColumn get createdAt => dateTime()();
}
