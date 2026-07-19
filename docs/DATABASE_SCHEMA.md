# Spectra 数据库 Schema 详细设计

> 本文档定义 Spectra 的数据库表结构、索引策略、查询模式和数据迁移方案。
>
> 使用 **Drift** (SQLite ORM) 进行类型安全的数据库操作。

---

## 一、实体关系总览

```
┌───────────┐       ┌────────────────┐       ┌───────────┐
│  Folders  │──1:N──│    Photos      │──N:M──│   Tags    │
└───────────┘       │                │       │           │
                    │                │       │ (层级，自  │
                    │                │       │  引用)    │
                    └───────┬────────┘       └───────────┘
                            │N:M
                            │
                    ┌───────┴────────┐
                    │ Collections    │
                    │ (手动/智能)     │
                    └────────────────┘
```

---

## 二、表定义 (Drift)

### 2.1 `photos` — 照片主表

```dart
class Photos extends Table {
  // ——— 主键 ———
  IntColumn get id => integer().autoIncrement()();

  // ——— 引用 ———
  IntColumn get folderId => integer().references(Folders, #id).nullable()();

  // ——— 文件信息 ———
  TextColumn get path => text().unique()();           // 完整路径（唯一约束）
  TextColumn get fileName => text()();                 // 文件名（含扩展名）
  TextColumn get fileHash => text()();                 // SHA256 文件哈希（用于去重）
  IntColumn get fileSize => integer()();               // 文件大小（字节）
  DateTimeColumn get modifiedAt => dateTime()();       // 文件修改时间
  DateTimeColumn get importedAt => dateTime()();       // 导入时间

  // ——— 图像信息（EXIF） ———
  IntColumn get width => integer().nullable()();
  IntColumn get height => integer().nullable()();
  IntColumn get orientation => integer().nullable()(); // EXIF Orientation (1-8)
  TextColumn get mimeType => text().nullable()();       // image/jpeg, image/x-adobe-dng 等

  // ——— 拍摄参数（EXIF） ———
  DateTimeColumn get dateTaken => dateTime().nullable()(); // DateTimeOriginal
  TextColumn get cameraMake => text().nullable()();        // 相机厂商
  TextColumn get cameraModel => text().nullable()();       // 相机型号
  TextColumn get lensModel => text().nullable()();          // 镜头型号
  RealColumn get focalLength => real().nullable()();        // 焦距（mm）
  RealColumn get focalLength35mm => real().nullable()();   // 35mm等效焦距
  RealColumn get aperture => real().nullable()();           // 光圈值
  RealColumn get iso => real().nullable()();                // ISO
  TextColumn get shutterSpeed => text().nullable()();       // 快门速度（字符串，如 "1/250"）
  RealColumn get exposureBias => real().nullable()();       // 曝光补偿（EV）
  TextColumn get meteringMode => text().nullable()();       // 测光模式
  TextColumn get whiteBalance => text().nullable()();       // 白平衡
  TextColumn get flash => text().nullable()();              // 闪光灯状态
  TextColumn get artist => text().nullable()();             // 摄影师
  TextColumn get copyright => text().nullable()();          // 版权信息

  // ——— GPS ———
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  RealColumn get altitude => real().nullable()();         // 海拔（米）

  // ——— 分类信息 ———
  IntColumn get rating => integer().withDefault(const Constant(0))(); // 0-5，0=未评分
  IntColumn get pickLabel => integer().withDefault(const Constant(0))(); // 0=none, 1=pick, 2=reject
  IntColumn get colorLabel => integer().withDefault(const Constant(0))(); // 0=none, 1=红, 2=黄, 3=绿, 4=蓝, 5=紫, 6=灰

  // ——— IPTC 元数据 ———
  TextColumn get iptcTitle => text().nullable()();
  TextColumn get iptcDescription => text().nullable()();
  TextColumn get iptcKeywords => text().nullable()();      // 逗号分隔
  TextColumn get iptcCredit => text().nullable()();
  TextColumn get iptcByline => text().nullable()();

  // ——— 缩略图状态 ———
  IntColumn get thumbnailStatus => integer().withDefault(const Constant(0))(); // 0=未生成, 1=生成中, 2=已生成, 3=失败
  DateTimeColumn get thumbnailGeneratedAt => dateTime().nullable()();

  // ——— 同步状态 ———
  IntColumn get syncStatus => integer().withDefault(const Constant(0))(); // 0=正常, 1=文件缺失, 2=已修改
}
```

### 2.2 `folders` — 文件夹表

```dart
class Folders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text().unique()();        // 文件夹完整路径
  TextColumn getName => text()();                   // 文件夹名称
  IntColumn get parentId => integer().references(Folders, #id).nullable()(); // 父文件夹
  IntColumn get photoCount => integer().withDefault(const Constant(0))();     // 缓存的照片数量
  DateTimeColumn get lastScannedAt => dateTime().nullable()(); // 最后扫描时间
  IntColumn get isWatched => integer().withDefault(const Constant(1))(); // 是否监听变更
}
```

### 2.3 `tags` — 标签表（层级）

```dart
class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();                  // 标签名称（同一父级下唯一）
  IntColumn get parentId => integer().references(Tags, #id).nullable()(); // 父标签 ID
  TextColumn get description => text().nullable()(); // 标签描述
  TextColumn get color => text().nullable()();        // 标签颜色（十六进制，可选）
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();   // 排序
  DateTimeColumn get createdAt => dateTime()();       // 创建时间
}
```

### 2.4 `photo_tags` — 照片-标签关联表

```dart
class PhotoTags extends Table {
  IntColumn get photoId => integer().references(Photos, #id, onDelete: Cascade)();
  IntColumn get tagId => integer().references(Tags, #id, onDelete: Cascade)();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {photoId, tagId};
}
```

### 2.5 `collections` — 收藏集表

```dart
class Collections extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get type => text()();                     // 'manual' 或 'smart'
  TextColumn get ruleJson => text().nullable()();       // 智能收藏集规则（JSON）
  TextColumn get iconName => text().nullable()();       // 图标名称
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}
```

### 2.6 `collection_photos` — 收藏集-照片关联表

```dart
class CollectionPhotos extends Table {
  IntColumn get collectionId => integer().references(Collections, #id, onDelete: Cascade)();
  IntColumn get photoId => integer().references(Photos, #id, onDelete: Cascade)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))(); // 手动排序

  @override
  Set<Column> get primaryKey => {collectionId, photoId};
}
```

### 2.7 `settings` — 应用设置表

```dart
class AppSettings extends Table {
  TextColumn get key => text()();                     // 设置键名
  TextColumn get value => text()();                   // 设置值（JSON 编码）
  TextColumn get group => text().nullable()();         // 设置分组

  @override
  Set<Column> get primaryKey => {key};
}
```

---

## 三、索引策略

```sql
-- ========== 主索引（Drift 自动创建） ==========
-- photos.id (主键)
-- tags.id (主键)
-- folders.id (主键)

-- ========== 外键索引（手动创建提升 JOIN 性能） ==========
CREATE INDEX idx_photos_folder_id ON photos(folder_id);
CREATE INDEX idx_photos_thumbnail_status ON photos(thumbnail_status);
CREATE INDEX idx_folders_parent_id ON folders(parent_id);
CREATE INDEX idx_tags_parent_id ON tags(parent_id);

-- ========== 查询索引（覆盖主要筛选场景） ==========
CREATE INDEX idx_photos_date_taken ON photos(date_taken);
CREATE INDEX idx_photos_imported_at ON photos(imported_at);
CREATE INDEX idx_photos_rating ON photos(rating);
CREATE INDEX idx_photos_pick_label ON photos(pick_label);
CREATE INDEX idx_photos_color_label ON photos(color_label);
CREATE INDEX idx_photos_camera ON photos(camera_make, camera_model);
CREATE INDEX idx_photos_file_hash ON photos(file_hash);

-- ========== 复合索引（覆盖常见组合查询） ==========
-- 筛选: 文件夹 + 星级 + 拍摄日期排序
CREATE INDEX idx_photos_folder_rating_date
    ON photos(folder_id, rating, date_taken);

-- 筛选: Pick + 文件夹
CREATE INDEX idx_photos_folder_pick
    ON photos(folder_id, pick_label);

-- ========== 全文搜索索引（文件名） ==========
CREATE INDEX idx_photos_file_name ON photos(file_name);
```

---

## 四、核心查询模式

### 4.1 按文件夹浏览

```dart
Future<List<Photo>> getPhotosByFolder(int folderId, {
  int limit = 200,
  int offset = 0,
  String? sortBy,         // 'dateTaken', 'importedAt', 'rating', 'fileName'
  bool ascending = false,
}) {
  return (select(photos)
        ..where((p) => p.folderId.equals(folderId))
        ..limit(limit, offset: offset)
        ..orderBy([(p) => OrderingTerm(expression: p.dateTaken, mode: descending)]))
      .get();
}
```

### 4.2 组合筛选

```dart
Future<List<Photo>> queryFiltered({
  int? folderId,
  int? minRating,
  int? pickLabel,
  int? colorLabel,
  DateTime? dateFrom,
  DateTime? dateTo,
  String? cameraModel,
  String? searchQuery,     // 搜索文件名/标签
  int limit = 200,
  int offset = 0,
}) {
  // 构建动态查询
  // ... 根据筛选条件组合 WHERE 子句
}
```

### 4.3 按标签筛选照片

```dart
// 查询包含某标签（及子标签）的所有照片
Future<List<Photo>> getPhotosByTag(int tagId) async {
  // 1. 获取所有子标签 ID
  final subTagIds = await _getSubTagIds(tagId);
  final allTagIds = [tagId, ...subTagIds];

  // 2. 联表查询
  return (select(photos)
        .join([
          innerJoin(photoTags, photoTags.photoId.equalsExp(photos.id)),
        ])
        ..where(photoTags.tagId.isIn(allTagIds))
        ..distinct())
      .get();
}
```

### 4.4 智能收藏集匹配

```dart
// 智能收藏集规则示例（JSON）
{
  "conditions": [
    { "field": "rating", "op": "gte", "value": 4 },
    { "field": "pickLabel", "op": "eq", "value": 1 },
    { "field": "cameraModel", "op": "eq", "value": "ILCE-7M4" }
  ],
  "logic": "AND",
  "sortBy": "dateTaken",
  "sortOrder": "desc"
}
```

---

## 五、数据库迁移

Drift 使用版本号管理迁移：

```dart
@DriftDatabase(tables: [Photos, Folders, Tags, PhotoTags, Collections, CollectionPhotos, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        // 初始化默认设置
        await into(settings).insert(const AppSetting(key: 'schema_version', value: '1'));
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // 版本升级逻辑
        if (from < 2) {
          // 例如：添加新列
          // await m.addColumn(photos, photos.altitude);
        }
      },
    );
  }
}
```

### 迁移版本历史

| 版本 | 变更内容 |
|------|----------|
| 1 | 初始 Schema：Photos, Folders, Tags, PhotoTags, Collections, CollectionPhotos, Settings |

---

## 六、DAO 设计

### 6.1 PhotoDao

```dart
class PhotoDao {
  final AppDatabase _db;
  const PhotoDao(this._db);

  // ——— 查询 ———
  Future<List<Photo>> getAll({int? limit, int? offset});
  Future<Photo?> getById(int id);
  Future<Photo?> getByPath(String path);
  Future<List<Photo>> getByFolder(int folderId, {int? limit, int? offset});
  Future<List<Photo>> queryFiltered({required PhotoFilter filter, int? limit, int? offset});
  Future<int> countAll();
  Future<int> countByFolder(int folderId);
  Future<int> countFiltered({required PhotoFilter filter});

  // ——— 写入 ———
  Future<int> insert(Photo photo);
  Future<int> insertOnConflictUpdate(Photo photo);  // UPSERT
  Future<bool> update(Photo photo);
  Future<int> batchInsert(List<Photo> photos);

  // ——— 分类操作 ———
  Future<int> setRating(int photoId, int rating);
  Future<int> batchSetRating(List<int> photoIds, int rating);
  Future<int> setPickLabel(int photoId, int label);
  Future<int> batchSetPickLabel(List<int> photoIds, int label);
  Future<int> setColorLabel(int photoId, int label);
  Future<int> batchSetColorLabel(List<int> photoIds, int label);

  // ——— 标签关联 ———
  Future<void> addTag(int photoId, int tagId);
  Future<void> removeTag(int photoId, int tagId);
  Future<List<Tag>> getTagsForPhoto(int photoId);
  Future<List<Photo>> getPhotosByTag(int tagId);

  // ——— 删除 ———
  Future<int> delete(int photoId);
  Future<int> deleteByPath(String path);

  // ——— 统计 ———
  Future<Map<String, int>> getCameraModelCounts();
  Future<Map<int, int>> getRatingDistribution();
}
```

### 6.2 TagDao

```dart
class TagDao {
  final AppDatabase _db;
  const TagDao(this._db);

  Future<List<Tag>> getAll();
  Future<List<Tag>> getRootTags();           // 顶级标签（parentId IS NULL）
  Future<List<Tag>> getChildTags(int parentId);
  Future<Tag?> getById(int id);
  Future<int> insert(Tag tag);
  Future<bool> update(Tag tag);
  Future<int> delete(int tagId);
  Future<List<Tag>> search(String query);    // 搜索标签名
  Future<int> getPhotoCount(int tagId);      // 标签下的照片数（含子标签）
  Future<void> mergeTags(int sourceTagId, int targetTagId); // 标签合并
}
```

---

## 七、数据流示例

### 导入流程

```
FileSystemService.watch(path)
    ↓ 检测到新文件
ImportService.onFileCreated(filePath)
    ↓
PhotoDao.insert(Photo(
  path: filePath,
  fileName: 'DSC01234.ARW',
  fileHash: sha256(file),
  fileSize: 45MB,
  modifiedAt: file.lastModified,
  importedAt: now,
  thumbnailStatus: 0,  // 未生成
))
    ↓
MetadataService.readExif(filePath)
    ↓ 更新 EXIF 字段
PhotoDao.update(photo.copyWith(
  dateTaken: exif.dateTimeOriginal,
  cameraMake: exif.make,
  cameraModel: exif.model,
  ...
))
    ↓
ThumbnailService.generate(photo)
    ↓ 生成后更新状态
PhotoDao.update(photo.copyWith(
  thumbnailStatus: 2,  // 已生成
  thumbnailGeneratedAt: now,
))
```

---

## 八、性能说明

### 数据量预期

| 表 | 10K 照片 | 100K 照片 | 1M 照片 |
|----|----------|-----------|---------|
| `photos` | ~10K 行 | ~100K 行 | ~1M 行 |
| `tags` | ~200 行 | ~2K 行 | ~5K 行 |
| `photo_tags` | ~30K 行 | ~300K 行 | ~3M 行 |
| `folders` | ~100 行 | ~1K 行 | ~10K 行 |
| 数据库大小 | ~10 MB | ~100 MB | ~1 GB |

### WAL 模式

```dart
// 启用 WAL 模式提升并发读写性能
final database = AppDatabase(
  NativeDatabase(
    file.path,
    queryExecutorMode: QueryExecutorMode.wal,
  ),
);
```
