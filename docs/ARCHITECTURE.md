# Spectra 软件架构

> 本文档描述 Spectra 的总体架构设计、分层职责和关键设计决策。

---

## 一、架构总览

Spectra 采用 **分层架构**，从上到下依次为：UI 层 → Provider 层 → Service 层 → 数据层。各层之间通过依赖注入和接口解耦。

```
┌──────────────────────────────────────────────────────────────────┐
│                        UI LAYER                                  │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────────┐  │
│  │ Screens     │  │ Components   │  │ Layout / Panels        │  │
│  │ (Pages)     │  │ (Widgets)    │  │ (Three-column layout)  │  │
│  └──────┬──────┘  └──────┬───────┘  └───────────┬────────────┘  │
│         │                │                       │               │
│    ┌────┴────────────────┴───────────────────────┴────┐         │
│    │           Riverpod Providers                      │         │
│    │  CatalogProvider │ FilterProvider │ TagProvider   │         │
│    │  SelectionProvider │ ImportProvider               │         │
│    │  ThumbnailProvider │ ViewModeProvider             │         │
│    └───────────────────────┬───────────────────────────┘         │
├────────────────────────────┼─────────────────────────────────────┤
│                      SERVICE LAYER                               │
│  ┌──────────┐ ┌───────────────┐ ┌──────────────────────────┐    │
│  │ Catalog  │ │ FileSystem    │ │ ThumbnailService         │    │
│  │ Service  │ │ Service       │ │ (image + Windows FFI)    │    │
│  ├──────────┤ ├───────────────┤ └──────────────────────────┘    │
│  │ Metadata │ │ Import        │                                │
│  │ Service  │ │ Service       │                                │
│  └────┬─────┘ └──────┬────────┘                                │
├───────┼───────────────┼─────────────────────────┼────────────────┤
│       │               │                         │                │
│  ┌────┴───────────────┴─────────────────────────┴────┐          │
│  │                  DATA LAYER                         │         │
│  │  ┌──────────┐  ┌────────────┐  ┌────────────────┐  │         │
│  │  │ Drift DB │  │ Repositori-│  │ Models         │  │         │
│  │  │ + DAO    │  │ es         │  │ (Pure Dart)    │  │         │
│  │  └──────────┘  └────────────┘  └────────────────┘  │         │
│  └──────────────────────────────────────────────────────┘         │
└──────────────────────────────────────────────────────────────────┘
```

---

## 二、各层职责

### 2.1 UI 层

负责界面渲染和用户交互，**不包含业务逻辑**。

```
ui/
├── screens/           # 完整页面
│   ├── home_screen.dart          # 主界面（三栏布局容器）
│   ├── viewer_screen.dart        # 全屏查看器
│   ├── import_screen.dart        # 导入对话框流程
│   ├── tag_manager_screen.dart   # 标签管理器
│   └── settings_screen.dart      # 设置页
├── layout/            # 布局管理
│   ├── app_layout.dart           # 布局状态（面板宽、折叠等）
│   └── panels/
│       ├── folder_panel.dart     # 左栏：文件夹树
│       ├── grid_panel.dart       # 中栏：照片网格/列表
│       ├── preview_panel.dart    # 中栏：单张预览
│       └── info_panel.dart       # 右栏：信息面板
└── components/        # 可复用组件
    ├── photo_grid.dart
    ├── photo_list.dart
    ├── thumbnail_widget.dart
    ├── star_rating.dart
    ├── color_label.dart
    ├── tag_chip.dart
    ├── filter_bar.dart
    └── keyboard_shortcuts.dart
```

**设计约束**：
- Widget 只通过 Provider 读取状态，不直接调用 Service
- Component 不依赖具体 Screen，保持可复用
- 所有用户事件 → Provider 方法调用 → Service → 状态更新

### 2.2 Provider 层

基于 **Riverpod** 的状态管理层，连接 UI 与 Service。

```
providers/
├── catalog_provider.dart      # 照片列表状态（当前文件夹/搜索结果）
├── filter_provider.dart       # 筛选条件状态（星级/旗标/色标/日期等）
├── selection_provider.dart    # 多选状态管理
├── import_provider.dart       # 导入任务状态（进度/状态）
├── tag_provider.dart          # 标签树状态
├── thumbnail_provider.dart    # 缩略图加载状态
├── view_mode_provider.dart    # 视图模式（网格密度/列表/排序）
└── settings_provider.dart     # 应用设置
```

**Provider 设计原则**：

| 原则 | 说明 |
|------|------|
| **一个关注点一个 Provider** | 不创建"大而全"的 Provider |
| `AsyncValue` 三态 | 所有异步数据使用 `AsyncValue.loading/error/data` |
| `family` 参数化 | 照片级状态用 `family(photoId)` |
| `invalidate` 刷新 | 数据变更通过 `ref.invalidate()` 触发刷新 |
| 避免 `notifyListeners` | 使用 Riverpod 原生状态更新而非 ChangeNotifier |

**示例：CatalogProvider**

```dart
@riverpod
class Catalog extends _$Catalog {
  @override
  Future<List<Photo>> build() async {
    final filter = ref.watch(filterProvider);
    final folderId = ref.watch(currentFolderProvider);
    return ref.read(catalogServiceProvider).queryPhotos(
      folderId: folderId,
      filter: filter,
    );
  }

  Future<void> refresh() async => ref.invalidateSelf();
}
```

### 2.3 Service 层

业务逻辑的核心实现，**无状态（stateless）**，通过方法参数传递上下文。

```
services/
├── catalog_service.dart       # 照片查询/排序/分组逻辑
├── file_system_service.dart   # 文件系统遍历/监听/watcher
├── import_service.dart        # 导入任务编排
├── metadata_service.dart      # EXIF/IPTC/XMP 读写
├── thumbnail_service.dart     # 缩略图生成/缓存/清理
├── tag_service.dart           # 标签 CRUD + 层级管理
└── collection_service.dart    # 收藏集管理（Phase 2）
```

**Service 设计原则**：

| 原则 | 说明 |
|------|------|
| **纯逻辑** | 不含状态，所有输出通过返回值 |
| **可测试** | 依赖接口化，可 mock |
| **Isolate 友好** | 耗时操作设计为可运行在后台 isolate |
| **错误处理** | 统一使用 `Result<T>` 模式返回成功/失败 |

**示例：CatalogService**

```dart
class CatalogService {
  const CatalogService(this._photoDao);

  Future<List<Photo>> queryPhotos({
    int? folderId,
    required PhotoFilter filter,
    int limit = 200,
    int offset = 0,
  }) {
    return _photoDao.queryFiltered(
      folderId: folderId,
      filter: filter,
      limit: limit,
      offset: offset,
    );
  }

  Future<int> countPhotos({
    int? folderId,
    required PhotoFilter filter,
  }) {
    return _photoDao.countFiltered(folderId: folderId, filter: filter);
  }
}
```

### 2.4 数据层

数据库访问和纯数据模型。

```
data/
├── database/
│   ├── app_database.dart       # Drift Database 定义
│   ├── app_database.g.dart     # 自动生成
│   ├── daos/
│   │   ├── photo_dao.dart
│   │   ├── tag_dao.dart
│   │   └── collection_dao.dart
│   └── migrations/             # 数据库迁移脚本
├── models/
│   ├── photo.dart              # 照片数据模型
│   ├── tag.dart                # 标签数据模型
│   ├── collection.dart         # 收藏集数据模型
│   └── photo_filter.dart       # 筛选条件值对象
└── repositories/
    ├── photo_repository.dart   # 照片数据聚合
    └── tag_repository.dart     # 标签数据聚合
```

---

## 三、数据流

### 3.1 默认数据流（Provider → UI）

```
User Action → Provider.method()
                  ↓
            Service.call()
                  ↓
            DAO.query()
                  ↓
            Future<List<Photo>>
                  ↓
        AsyncValue.data(photos)
                  ↓
        UI rebuilds with new data
```

### 3.2 批量操作数据流

```
User selects 10 photos → SelectionProvider
User presses '3' (rate 3 stars)
    → SelectionProvider.rateSelected(3)
        → CatalogService.batchRate(photoIds, 3)
            → PhotoDao.batchUpdateRating(photoIds, 3)
        → ref.invalidate(catalogProvider)
    → UI rebuilds with updated ratings
```

### 3.3 后台缩略图生成

```
FileSystem watcher detects new files
    → ImportService queues thumbnails
        → ThumbnailService.generate(photo)
            → if cache hit: return cached
            → if JPEG/PNG: decode with `image` → resize → save cache
            → if RAW: Windows Shell IShellItemImageFactory → save cache
            → update database thumbnail_status
    → ref.invalidate(thumbnailProvider(photoId))
    → UI updates thumbnail
```

---

## 四、依赖注入

使用 Riverpod 的依赖注入能力，不需要第三方 DI 容器。

```dart
// ——— Service 注入 ———
final metadataServiceProvider = Provider<MetadataService>((ref) {
  return MetadataService(exifReader: exifReader);
});

final catalogServiceProvider = Provider<CatalogService>((ref) {
  return CatalogService(photoDao: ref.read(photoDaoProvider));
});

// ——— 数据库注入 ———
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

final photoDaoProvider = Provider<PhotoDao>((ref) {
  return ref.read(databaseProvider).photoDao;
});
```

---

## 五、并发模型

### 5.1 Isolate 使用场景

| 场景 | 方案 | 说明 |
|------|------|------|
| 首次目录扫描 | `Isolate.run` | 大量文件 I/O，不阻塞 UI |
| 缩略图批量生成 | `Isolate.run` + 分片 | CPU 密集型解码/缩放 |
| EXIF 批量读取 | 分批 + `compute()` | 混合 I/O + 解析 |
| 数据库写入 | Drift isolate | Drift 内置 isolate 支持 |
| AI 模型推理 | `flutter_onnxruntime` 内部处理 | 插件自带 isolate |

### 5.2 主线程原则

- UI 更新、小状态变更 → 主线程
- 文件 I/O、EXIF 解析、缩略图生成 → Isolate
- 数据库读写 → Drift isolate（自动管理）

---

## 六、错误处理

### 6.1 Result 类型

```dart
sealed class Result<T> {
  const Result();
}

final class Success<T> extends Result<T> {
  final T data;
  const Success(this.data);
}

final class Failure<T> extends Result<T> {
  final AppException error;
  const Failure(this.error);
}
```

### 6.2 异常层级

```
AppException (基类)
├── DatabaseException      # 数据库错误
├── FileSystemException    # 文件访问错误
├── MetadataException      # EXIF/XMP 解析错误
├── ThumbnailException     # 缩略图生成错误
└── MLException            # AI 推理错误 (Phase 2)
```

### 6.3 Provider 层自动处理

```dart
@riverpod
Future<List<Photo>> catalog(CatalogRef ref) async {
  try {
    return await ref.read(catalogServiceProvider).queryPhotos(...);
  } on AppException catch (e) {
    throw AsyncError(e, StackTrace.current);
  }
}
```

UI 层通过 `AsyncValue.when(data:, error:, loading:)` 统一处理三态。

---

## 七、性能架构

### 7.1 缩略图分级缓存

| 等级 | 尺寸 | 格式 | 用途 | 生成时机 |
|------|------|------|------|----------|
| L1 | 128×128 | WebP | 网格视图缩略图 | 导入时后台生成 |
| L2 | 512×512 | WebP | 列表视图/预览 | L1 完成后异步生成 |
| L3 | 原始尺寸 | - | 全屏查看 | 按需加载 |

### 7.2 数据库索引策略

```sql
-- 覆盖主要查询场景的索引
CREATE INDEX idx_photos_date_taken ON photos(date_taken);
CREATE INDEX idx_photos_camera ON photos(camera_make, camera_model);
CREATE INDEX idx_photos_rating ON photos(rating);
CREATE INDEX idx_photos_pick_label ON photos(pick_label);
CREATE INDEX idx_photos_folder ON photos(folder_id);
CREATE INDEX idx_photos_file_hash ON photos(file_hash);
```

### 7.3 内存管理

- 网格视图使用 `GridView.builder` 懒加载
- 图片解码时指定 `cacheWidth` / `cacheHeight`
- `ImageCache.maximumSize` 根据系统内存动态调整
- 大图库分页加载（默认每页 200 张）

---

## 八、关键设计决策记录 (ADR)

### ADR-001: 选择 Riverpod 而非 Bloc

**决策**：使用 Riverpod。

**理由**：
- 异步原生支持，`AsyncValue` 三态天然适合数据加载场景
- 编译安全，避免 ProviderNotFoundException 运行时错误
- `ref.invalidate()` 模式比 Bloc 的事件驱动更简洁
- `family` 参数化支持照片级状态隔离

### ADR-002: 不直接编辑原始文件

**决策**：所有分类元数据存储在 SQLite 数据库中，不修改原始照片文件。

**理由**：
- 非破坏性是 DAM 的核心原则
- 避免 RAW 格式写入风险
- 支持撤销/重做操作
- 数据库可备份/恢复，独立于照片存储

### ADR-003: 缩略图缓存使用 WebP

**决策**：缩略图缓存统一使用 WebP 格式。

**理由**：
- WebP 有损压缩比 JPEG 小 25-35%，质量相当
- Flutter 原生支持 WebP 解码
- 减少磁盘 I/O 和缓存空间占用

### ADR-004: Phase 1 使用 exif_reader 只读

**决策**：Phase 1 仅读取 EXIF，不涉及写入。

**理由**：
- `exif_reader` 是唯一成熟的支持 Windows 和 RAW 的 Dart 包
- EXIF 写入在 Dart 生态中缺乏成熟方案
- 推迟到 Phase 3 评估 exiv2 FFI 或 win32 COM 方案

---

## 九、测试策略

| 层级 | 测试类型 | 框架 | 覆盖目标 |
|------|----------|------|----------|
| **Service** | 单元测试 | `flutter_test` + `mocktail` | 所有业务逻辑 |
| **DAO** | 数据库测试 | `drift_test` | 查询逻辑、事务 |
| **Provider** | Provider 测试 | `riverpod_test` | 状态转换、异步逻辑 |
| **Component** | Widget 测试 | `flutter_test` | UI 交互、渲染 |
| **Screen** | 集成测试 | `integration_test` | 完整流程 |
