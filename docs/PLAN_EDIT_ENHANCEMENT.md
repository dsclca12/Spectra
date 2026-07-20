# 实施计划：高级编辑功能 + 编辑历史 + 自动保存

> **版本**：v0.1.x 编辑增强
> **日期**：2026-07-13
> **范围**：自动调整、编辑快照 + 操作历史 + 版本对比、全场景自动保存

---

## 一、需求确认

| 需求项 | 选择 | 说明 |
|--------|------|------|
| 高级编辑功能 | **自动调整** | 一键自动曝光/白平衡/色调优化 |
| 编辑历史功能 | **D — 全部** | 编辑快照 + 完整操作历史 + 版本对比 |
| 自动保存 | **E — 全部** | 实时 + 防抖 + 切换照片时 + 关闭查看器时 |
| 历史持久化 | **是** | 编辑历史/快照持久化到数据库，跨会话可用 |

---

## 二、现有架构分析

### 已有的编辑能力

```
EditParams (data model)
├── 基础: exposure, contrast, highlights, shadows, whites, blacks
├── 色彩: saturation, vibrance, temperature, tint
├── 效果: sharpness, vignette, grain, fade
└── 几何: cropX/Y/W/H, rotation, flipH, flipV

EditSessionNotifier (state management)
├── undoStack / redoStack (内存中, 最多 50 步, 切换照片后丢失)
├── updateParam() → 推入 undoStack
├── undo() / redo() / reset()
└── save() → 写入 PhotoEdits 表 (单条记录, upsert)

PhotoEdits (database table)
└── 每张照片最多一条编辑参数记录 (无历史)

实时预览: FragmentShader (assets/shaders/photo_edit.frag)
烘焙导出: ImageEditService (package:image 像素级处理)
```

### 关键文件

| 文件 | 职责 |
|------|------|
| `lib/data/models/edit_params.dart` | 编辑参数数据模型 |
| `lib/data/database/tables.dart` | `PhotoEdits` 表定义 |
| `lib/data/database/daos/edit_dao.dart` | 编辑参数 CRUD |
| `lib/data/database/app_database.dart` | 数据库 schema (v2) |
| `lib/providers/edit_provider.dart` | `EditSessionNotifier` 状态管理 |
| `lib/data/services/image_edit_service.dart` | 烘焙导出服务 |
| `lib/ui/layout/panels/edit_panel.dart` | 编辑面板 UI |
| `lib/ui/components/editable_image_view.dart` | Shader 实时预览 |
| `lib/ui/components/crop_overlay.dart` | 裁剪交互 |
| `lib/ui/screens/viewer_screen.dart` | 全屏查看器 |
| `lib/providers/settings_provider.dart` | 应用设置 |
| `assets/shaders/photo_edit.frag` | Fragment Shader |

### 当前问题

1. **无自动调整** — 用户需手动逐项调节所有参数
2. **无持久化历史** — 撤销/重做仅在内存中，切换照片或重启后丢失
3. **无快照** — 无法保存中间编辑状态供回退
4. **无版本对比** — 无法并排比较不同编辑版本
5. **手动保存** — 用户需手动点击"保存"按钮，容易遗忘

---

## 三、实施方案

### 模块 A：自动调整

#### A1. 自动调整算法 (`AutoAdjustService`)

**新文件**：`lib/data/services/auto_adjust_service.dart`

**算法**：分析图片直方图，自动计算最优编辑参数。

```
输入: 图片文件路径
输出: EditParams (仅包含自动调整后的非默认值)

算法流程:
1. 解码图片为缩略图 (256px 长边, 用于快速分析)
2. 计算亮度直方图 (256 bins)
3. 自动曝光:
   - 计算平均亮度 meanLum
   - 目标亮度 = 0.5 (中灰)
   - exposure = log2(targetLum / meanLum), clamp 到 [-1.5, +1.5]
4. 自动对比度:
   - 计算 5% 和 95% 百分位 (p5, p95)
   - 若 p5 > 0.05 或 p95 < 0.95 → 对比度不足
   - contrast = ((0.5 - p5) + (0.95 - p95)) * 100, clamp [-50, +50]
5. 自动白平衡:
   - 计算 R/G/B 通道平均值
   - 灰场假设: R≈G≈B
   - temperature = (avgG - avgR) * 200, clamp [-80, +80]
   - tint = (avgG - avgB) * 150, clamp [-60, +60]
6. 自动高光/阴影:
   - 若 p95 > 0.9 → 高光过曝 → highlights = -(p95 - 0.9) * 500, clamp [-100, 0]
   - 若 p5 < 0.05 → 阴影欠曝 → shadows = (0.05 - p5) * 500, clamp [0, +100]
7. 自动自然饱和度:
   - 计算平均饱和度 avgSat
   - 若 avgSat < 0.3 → vibrance = (0.3 - avgSat) * 100, clamp [0, +40]
```

**依赖**：`package:image` (已存在于 pubspec.yaml)

**Provider 注册**：在 `lib/providers/providers.dart` 中添加 `autoAdjustServiceProvider`。

#### A2. UI 集成

在 `edit_panel.dart` 的顶部标题栏区域添加"自动调整"按钮：

```
编辑面板顶部:
┌─────────────────────────────────────┐
│ 🎛 编辑          [✨自动] [裁剪]    │
├─────────────────────────────────────┤
│ ▸ 基础                              │
│ ▸ 色彩                              │
│ ▸ 效果                              │
│ ▸ 几何                              │
├─────────────────────────────────────┤
│ ↶ ↷ ⟳          未保存    [保存]   │
└─────────────────────────────────────┘
```

- 点击"自动"按钮 → 调用 `AutoAdjustService.analyze()`
- 分析期间显示加载指示器
- 分析完成 → `replaceParams(result)` (推入撤销栈, 可撤销)
- 自动调整仅设置非零参数, 不覆盖用户已手动调整的参数 (可选: 提供"全部覆盖"和"仅填充未调整"两种模式)

#### A3. 快捷键

在 `viewer_screen.dart` 中添加 `A` 键触发自动调整。

---

### 模块 B：编辑历史 (快照 + 操作历史 + 版本对比)

#### B1. 数据库 Schema 变更

**新增表**：`EditSnapshots` — 编辑快照

```dart
/// 编辑快照表 — 保存命名的编辑参数快照
class EditSnapshots extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get photoId =>
      integer().references(Photos, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();  // 快照名称
  TextColumn get paramsJson => text()();  // EditParams 序列化为 JSON
  DateTimeColumn get createdAt => dateTime()();
  BoolColumn get isAuto => boolean().withDefault(const Constant(false))();
  // isAuto=true 表示系统自动创建的快照 (如自动保存节点)
}
```

**新增表**：`EditHistory` — 完整操作历史

```dart
/// 编辑操作历史表 — 记录每次编辑操作
class EditHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get photoId =>
      integer().references(Photos, #id, onDelete: KeyAction.cascade)();
  TextColumn get paramsJson => text()();  // 操作后的完整 EditParams
  TextColumn get actionLabel => text().nullable()();  // 操作描述 (如 "曝光 +0.5")
  DateTimeColumn get createdAt => dateTime()();
}
```

**Schema 版本**：v2 → v3

```dart
@override
int get schemaVersion => 3;

@override
MigrationStrategy get migration {
  return MigrationStrategy(
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.createTable(photoEdits);
      }
      if (from < 3) {
        // v3: 添加编辑快照表和操作历史表
        await m.createTable(editSnapshots);
        await m.createTable(editHistory);
        // 创建索引
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_edit_snapshots_photo_id ON edit_snapshots(photo_id);');
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_edit_history_photo_id ON edit_history(photo_id);');
      }
    },
  );
}
```

**`@DriftDatabase` 注解更新**：
```dart
@DriftDatabase(
  tables: [Photos, Folders, Tags, PhotoTags, Collections, CollectionPhotos,
           AppSettings, PhotoEdits, EditSnapshots, EditHistory],
  daos: [PhotoDao, TagDao, FolderDao, SettingsDao, EditDao,
         EditSnapshotDao, EditHistoryDao],
)
```

#### B2. EditParams JSON 序列化

**修改文件**：`lib/data/models/edit_params.dart`

添加 `toJson()` / `fromJson()` 方法：

```dart
Map<String, dynamic> toJson() => {
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

factory EditParams.fromJson(Map<String, dynamic> json) => EditParams(
  exposure: (json['exposure'] as num?)?.toDouble() ?? 0.0,
  // ... 其余字段同理
);
```

#### B3. DAO 层

**新文件**：`lib/data/database/daos/edit_snapshot_dao.dart`

```dart
@DriftAccessor(tables: [EditSnapshots])
class EditSnapshotDao extends DatabaseAccessor<AppDatabase>
    with _$EditSnapshotDaoMixin {
  EditSnapshotDao(super.db);

  Future<List<EditSnapshot>> getByPhotoId(int photoId);
  Future<int> create(EditSnapshotsCompanion companion);
  Future<void> deleteById(int id);
  Future<void> deleteByPhotoId(int photoId);
  Future<void> rename(int id, String name);
}
```

**新文件**：`lib/data/database/daos/edit_history_dao.dart`

```dart
@DriftAccessor(tables: [EditHistory])
class EditHistoryDao extends DatabaseAccessor<AppDatabase>
    with _$EditHistoryDaoMixin {
  EditHistoryDao(super.db);

  Future<List<EditHistory>> getByPhotoId(int photoId);
  Future<int> add(EditHistoryCompanion companion);
  Future<void> deleteByPhotoId(int photoId);
  Future<void> pruneHistory(int photoId, int keepCount);  // 保留最近 N 条
}
```

#### B4. 编辑会话状态管理重构

**修改文件**：`lib/providers/edit_provider.dart`

`EditSessionState` 扩展：

```dart
class EditSessionState {
  final EditParams params;
  final bool isDirty;
  final List<EditParams> undoStack;      // 内存撤销栈 (快速撤销)
  final List<EditParams> redoStack;      // 内存重做栈
  final List<EditSnapshot> snapshots;    // 持久化快照列表
  final List<EditHistory> history;       // 持久化操作历史
  final bool isAutoSaving;               // 正在自动保存
  final DateTime? lastSavedAt;           // 最后保存时间
}
```

`EditSessionNotifier` 新增方法：

```dart
/// 创建快照 (手动命名)
Future<void> createSnapshot(String name);

/// 删除快照
Future<void> deleteSnapshot(int snapshotId);

/// 重命名快照
Future<void> renameSnapshot(int snapshotId, String name);

/// 跳转到快照 (加载快照的参数, 推入撤销栈)
Future<void> restoreSnapshot(int snapshotId);

/// 跳转到历史节点 (加载历史记录的参数, 推入撤销栈)
Future<void> restoreHistory(int historyId);

/// 加载快照列表和历史列表
Future<void> loadHistory();

/// 记录操作到历史表 (自动调用)
Future<void> _recordHistory(EditParams params, String? label);

/// 清空历史 (保留快照)
Future<void> clearHistory();
```

**操作历史记录策略**：
- 每次 `updateParam` / `replaceParams` 后，防抖 2 秒记录到 `EditHistory` 表
- 历史记录上限：每张照片最多 200 条，超过自动清理最旧的
- 自动保存的节点标记 `isAuto=true`

#### B5. UI — 快照面板

**新文件**：`lib/ui/components/snapshot_panel.dart`

在编辑面板中添加"快照"标签页 (与"调整"标签页并列)：

```
编辑面板:
┌─────────────────────────────────────┐
│ 🎛 编辑    [调整] [快照] [历史]  ✨ │
├─────────────────────────────────────┤
│ 快照标签页:                          │
│ ┌─────────────────────────────────┐ │
│ │ 📸 初始状态      2026-07-13 14:│ │
│ │    [恢复] [重命名] [删除]       │ │
│ ├─────────────────────────────────┤ │
│ │ 📸 暖色调        2026-07-13 15:│ │
│ │    [恢复] [重命名] [删除]       │ │
│ ├─────────────────────────────────┤ │
│ │ 📸 黑白风格      2026-07-13 16:│ │
│ │    [恢复] [重命名] [删除]       │ │
│ └─────────────────────────────────┘ │
│                                     │
│        [+ 创建快照]                 │
└─────────────────────────────────────┘
```

- 创建快照 → 弹出命名对话框 → 保存当前 `EditParams` 为快照
- 恢复快照 → 加载快照参数到当前编辑会话 (推入撤销栈, 可撤销)
- 快照列表从数据库加载, 跨会话持久

#### B6. UI — 历史面板

**新文件**：`lib/ui/components/history_panel.dart`

```
编辑面板:
┌─────────────────────────────────────┐
│ 🎛 编辑    [调整] [快照] [历史]  ✨ │
├─────────────────────────────────────┤
│ 历史标签页:                          │
│ ┌─────────────────────────────────┐ │
│ │ ● 现在              16:32  当前 │ │
│ │ ○ 自动调整          16:30       │ │
│ │ ○ 曝光 +0.5 EV      16:28       │ │
│ │ ○ 对比度 +15        16:25       │ │
│ │ ○ 色温 暖 20        16:20       │ │
│ │ ○ 裁剪 3:2          16:15       │ │
│ │ ○ 初始状态          16:10       │ │
│ └─────────────────────────────────┘ │
│                                     │
│  点击任意节点可回退到该状态          │
│  [清空历史]                         │
└─────────────────────────────────────┘
```

- 历史列表从 `EditHistory` 表加载, 按时间倒序
- 点击历史节点 → `restoreHistory(id)` → 加载该节点参数 (推入撤销栈)
- "现在"节点 = 当前编辑状态
- 操作描述 (`actionLabel`) 自动生成 (如 "曝光 +0.5 EV", "自动调整", "裁剪 3:2")

#### B7. UI — 版本对比

**新文件**：`lib/ui/components/version_compare_dialog.dart`

```
┌───────────────────────────────────────────────┐
│  版本对比                                      │
├───────────────────┬───────────────────────────┤
│  快照: 暖色调     │   当前编辑                │
│                   │                           │
│  [图片预览]       │   [图片预览]              │
│  (应用快照参数)   │   (应用当前参数)          │
│                   │                           │
│  曝光: +0.3 EV    │   曝光: +0.5 EV           │
│  色温: 暖 30      │   色温: 暖 20             │
│  ...              │   ...                     │
├───────────────────┴───────────────────────────┤
│  [恢复到快照]        [保持当前]               │
└───────────────────────────────────────────────┘
```

- 从快照面板点击"对比" → 打开版本对比对话框
- 左侧: 选定快照的参数预览 (使用 `EditableImageView` 渲染)
- 右侧: 当前编辑参数预览
- 底部参数 diff 表格: 高亮差异项
- "恢复到快照" → `restoreSnapshot(id)` 并关闭对话框

---

### 模块 C：自动保存

#### C1. 设置项

**修改文件**：`lib/providers/settings_provider.dart`

新增设置键：

```dart
class SettingKeys {
  // ... 现有键 ...

  // 编辑
  static const editAutoSave = 'edit.autoSave';              // 总开关
  static const editAutoSaveDebounceMs = 'edit.autoSaveDebounce';  // 防抖延迟
  static const editAutoSaveOnSwitch = 'edit.autoSaveOnSwitch';    // 切换照片时保存
  static const editAutoSaveOnClose = 'edit.autoSaveOnClose';      // 关闭查看器时保存
  static const editHistoryEnabled = 'edit.historyEnabled';        // 操作历史开关
  static const editHistoryMaxCount = 'edit.historyMaxCount';      // 历史上限
}
```

`AppSettingsState` 新增字段：

```dart
final bool editAutoSave;              // 默认 true
final int editAutoSaveDebounceMs;     // 默认 2000
final bool editAutoSaveOnSwitch;      // 默认 true
final bool editAutoSaveOnClose;       // 默认 true
final bool editHistoryEnabled;        // 默认 true
final int editHistoryMaxCount;        // 默认 200
```

#### C2. 防抖自动保存

**修改文件**：`lib/providers/edit_provider.dart`

`EditSessionNotifier` 添加防抖保存逻辑：

```dart
class EditSessionNotifier extends StateNotifier<EditSessionState> {
  Timer? _autoSaveTimer;
  Timer? _historyTimer;

  /// 更新参数 — 推入撤销栈, 触发防抖自动保存
  void updateParam(EditParams Function(EditParams) updater) {
    // ... 现有逻辑 ...

    // 触发防抖自动保存
    _scheduleAutoSave();

    // 触发防抖历史记录
    _scheduleHistoryRecord();
  }

  /// 防抖自动保存
  void _scheduleAutoSave() {
    final settings = _ref.read(settingsProvider);
    if (!settings.editAutoSave) return;

    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(
      Duration(milliseconds: settings.editAutoSaveDebounceMs),
      () => _autoSave(),
    );
  }

  /// 执行自动保存 (静默, 不更新 isDirty 状态显示)
  Future<void> _autoSave() async {
    if (!state.isDirty) return;
    await save();  // 复用现有 save() 逻辑
  }

  /// 防抖历史记录
  void _scheduleHistoryRecord() {
    final settings = _ref.read(settingsProvider);
    if (!settings.editHistoryEnabled) return;

    _historyTimer?.cancel();
    _historyTimer = Timer(
      const Duration(seconds: 2),
      () => _recordHistory(state.params, null),
    );
  }

  /// 切换照片时调用 — 立即保存
  Future<void> saveOnSwitch() async {
    final settings = _ref.read(settingsProvider);
    if (settings.editAutoSaveOnSwitch && state.isDirty) {
      _autoSaveTimer?.cancel();
      await save();
    }
  }

  /// 关闭查看器时调用 — 立即保存
  Future<void> saveOnClose() async {
    final settings = _ref.read(settingsProvider);
    if (settings.editAutoSaveOnClose && state.isDirty) {
      _autoSaveTimer?.cancel();
      await save();
    }
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _historyTimer?.cancel();
    super.dispose();
  }
}
```

#### C3. 切换照片时自动保存

**修改文件**：`lib/ui/screens/viewer_screen.dart`

在 `_navigate()` 和 `onPageChanged` 中, 切换前保存当前照片的编辑：

```dart
void _navigate(int direction) {
  // 切换前自动保存当前照片编辑
  ref.read(editSessionProvider(_currentPhotoId).notifier).saveOnSwitch();

  // ... 现有导航逻辑 ...
}

// onPageChanged 回调中:
onPageChanged: (page) {
  if (_programmaticNavigation) return;
  // 切换前自动保存
  ref.read(editSessionProvider(_currentPhotoId).notifier).saveOnSwitch();
  // ... 现有逻辑 ...
},
```

#### C4. 关闭查看器时自动保存

**修改文件**：`lib/ui/screens/viewer_screen.dart`

在 `dispose()` 中触发保存：

```dart
@override
void dispose() {
  // 关闭查看器时自动保存
  // 注意: dispose 中不能 await, 使用 fire-and-forget
  final session = ref.read(editSessionProvider(_currentPhotoId).notifier);
  session.saveOnClose();  // 内部检查 isDirty 和设置

  _transformController.removeListener(_onTransformControllerChanged);
  // ... 现有 dispose 逻辑 ...
}
```

> **注意**：`dispose()` 中不能使用 `await`。`saveOnClose()` 内部会检查设置开关和 `isDirty` 状态, 若无需保存则立即返回。实际的数据库写入是 fire-and-forget, 由于 Riverpod 的 `autoDispose` 会在 dispose 后清理 notifier, 需要确保 `save()` 在 notifier 被销毁前完成。解决方案：在 `saveOnClose()` 中直接持有 `editDao` 引用执行写入, 不依赖 notifier 生命周期。

#### C5. 设置界面

**修改文件**：`lib/ui/screens/settings_screen.dart`

在设置页左侧导航添加"编辑"分区：

```dart
final _sections = const [
  (Icons.palette, '外观'),
  (Icons.image, '缩略图与画质'),
  (Icons.download, '导入'),
  (Icons.search, '搜索'),
  (Icons.grid_view, '浏览'),
  (Icons.speed, '性能'),
  (Icons.edit, '编辑'),          // ← 新增
  (Icons.keyboard, '快捷键'),
  (Icons.info, '关于'),
];
```

编辑设置页内容：

```
编辑设置:
┌─────────────────────────────────────────┐
│ 编辑                                     │
│ 自动保存、编辑历史、自动调整              │
├─────────────────────────────────────────┤
│ 自动保存                                 │
│ ☑ 启用自动保存           [开关]          │
│     编辑后自动保存到数据库                │
│ 防抖延迟: 2000 [────●────] ms            │
│ ☑ 切换照片时自动保存      [开关]          │
│ ☑ 关闭查看器时自动保存    [开关]          │
├─────────────────────────────────────────┤
│ 编辑历史                                 │
│ ☑ 启用操作历史记录        [开关]          │
│ 历史上限: 200 [──●──────] 条             │
├─────────────────────────────────────────┤
│ 自动调整                                 │
│ ☑ 自动调整时保留用户已调参数 [开关]       │
└─────────────────────────────────────────┘
```

---

## 四、文件变更清单

### 新增文件 (8 个)

| 文件 | 说明 |
|------|------|
| `lib/data/services/auto_adjust_service.dart` | 自动调整算法服务 |
| `lib/data/database/daos/edit_snapshot_dao.dart` | 快照 DAO |
| `lib/data/database/daos/edit_snapshot_dao.g.dart` | 快照 DAO 生成代码 |
| `lib/data/database/daos/edit_history_dao.dart` | 历史 DAO |
| `lib/data/database/daos/edit_history_dao.g.dart` | 历史 DAO 生成代码 |
| `lib/ui/components/snapshot_panel.dart` | 快照面板 UI |
| `lib/ui/components/history_panel.dart` | 历史面板 UI |
| `lib/ui/components/version_compare_dialog.dart` | 版本对比对话框 |

### 修改文件 (10 个)

| 文件 | 变更内容 |
|------|----------|
| `lib/data/database/tables.dart` | 新增 `EditSnapshots` 和 `EditHistory` 表定义 |
| `lib/data/database/app_database.dart` | schema v3, 新增表和 DAO, 迁移逻辑 |
| `lib/data/models/edit_params.dart` | 添加 `toJson()` / `fromJson()` |
| `lib/data/database/daos/edit_dao.dart` | 无变更 (保持不变) |
| `lib/providers/providers.dart` | 注册新 DAO 和 Service Provider |
| `lib/providers/edit_provider.dart` | 扩展状态, 添加快照/历史/自动保存方法 |
| `lib/providers/settings_provider.dart` | 新增编辑相关设置项 |
| `lib/ui/layout/panels/edit_panel.dart` | 标签页切换, 自动调整按钮, 快照/历史面板集成 |
| `lib/ui/screens/viewer_screen.dart` | 切换/关闭时自动保存, A 键快捷键 |
| `lib/ui/screens/settings_screen.dart` | 新增编辑设置分区 |

### 代码生成

```powershell
dart run build_runner build --delete-conflicting-outputs
```

---

## 五、实施顺序

### 阶段 1：数据层 (预计 2-3 小时)

1. **EditParams JSON 序列化** — `edit_params.dart` 添加 `toJson`/`fromJson`
2. **数据库表定义** — `tables.dart` 新增 `EditSnapshots` 和 `EditHistory`
3. **数据库迁移** — `app_database.dart` schema v3, 迁移逻辑
4. **DAO 实现** — `edit_snapshot_dao.dart` 和 `edit_history_dao.dart`
5. **代码生成** — `dart run build_runner build`
6. **Provider 注册** — `providers.dart` 注册新 DAO 和 Service

### 阶段 2：自动调整 (预计 2-3 小时)

7. **AutoAdjustService** — `auto_adjust_service.dart` 实现直方图分析算法
8. **Provider 注册** — `providers.dart` 注册 `autoAdjustServiceProvider`
9. **UI 集成** — `edit_panel.dart` 添加自动调整按钮和加载状态
10. **快捷键** — `viewer_screen.dart` 添加 `A` 键

### 阶段 3：编辑历史与快照 (预计 3-4 小时)

11. **EditSessionNotifier 扩展** — `edit_provider.dart` 添加快照/历史方法
12. **快照面板 UI** — `snapshot_panel.dart`
13. **历史面板 UI** — `history_panel.dart`
14. **版本对比对话框** — `version_compare_dialog.dart`
15. **编辑面板标签页集成** — `edit_panel.dart` 添加标签页切换

### 阶段 4：自动保存 (预计 2 小时)

16. **设置项** — `settings_provider.dart` 新增编辑设置字段
17. **防抖自动保存** — `edit_provider.dart` 添加 `_scheduleAutoSave` 逻辑
18. **切换照片时保存** — `viewer_screen.dart` 修改 `_navigate` 和 `onPageChanged`
19. **关闭查看器时保存** — `viewer_screen.dart` 修改 `dispose`
20. **设置界面** — `settings_screen.dart` 新增编辑设置分区

### 阶段 5：测试与验证 (预计 1-2 小时)

21. **单元测试** — `AutoAdjustService` 算法测试
22. **单元测试** — `EditSnapshotDao` / `EditHistoryDao` CRUD 测试
23. **集成测试** — 自动保存流程测试
24. **构建验证** — `flutter build windows --debug`
25. **运行验证** — 启动应用, 手动测试全流程

---

## 六、技术决策

### 1. 历史记录存储策略

**选择**：存储完整 `EditParams` JSON (非增量 diff)

**理由**：
- 实现简单, 回退时直接加载完整参数, 无需重放
- `EditParams` 仅 21 个 double/int/bool 字段, JSON 约 300 字节, 200 条历史约 60KB, 可忽略
- 增量 diff 方案虽节省空间, 但回退需从初始状态重放所有操作, 计算开销大

### 2. 自动保存与手动保存的关系

**选择**：自动保存复用现有 `save()` 方法, 不引入额外状态

**理由**：
- `save()` 已实现 upsert 逻辑, 幂等安全
- 自动保存后 `isDirty` 设为 false, UI 自动更新"未保存"标记
- 手动保存按钮在自动保存启用后变为可选操作 (仍保留, 作为强制保存)

### 3. dispose 中的自动保存

**问题**：`StateNotifier.dispose()` 中不能 `await`, 且 `autoDispose` 会销毁 notifier

**解决方案**：
- `saveOnClose()` 检查 `isDirty` 后, 直接通过 `_ref.read(editDaoProvider)` 获取 DAO
- DAO 是数据库级别的单例, 不依赖 notifier 生命周期
- 异步写入 fire-and-forget, 即使 notifier 被销毁, DAO 仍可完成写入

### 4. 自动调整算法精度

**选择**：基于缩略图 (256px) 的直方图分析, 非像素级精确计算

**理由**：
- 速度优先: 256px 缩略图仅 ~65K 像素, 分析耗时 < 50ms
- 自动调整是起点建议, 用户后续会微调
- 像素级精确计算耗时数百毫秒, 用户体验差

### 5. 编辑面板标签页 vs 折叠面板

**选择**：顶部标签页 (调整 / 快照 / 历史)

**理由**：
- 现有调整滑块已占满面板高度, 无法再叠加快照/历史列表
- 标签页切换清晰, 符合 Lightroom 的面板切换模式
- 裁剪模式保持独立切换 (图标按钮), 不受标签页影响

---

## 七、风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 数据库迁移失败 | 用户已有数据丢失 | 迁移仅新增表, 不修改现有表; 迁移前自动备份 |
| 自动调整算法效果差 | 用户信任度降低 | 算法基于标准直方图分析, 效果可接受; 提供"仅填充未调整参数"模式 |
| 自动保存频繁写入 | 数据库性能下降 | 防抖 2 秒, 最少间隔保证; WAL 模式下写入性能充足 |
| 历史记录膨胀 | 数据库体积增长 | 每照片上限 200 条, 自动清理最旧记录; 60KB/照片可忽略 |
| dispose 中异步保存失败 | 编辑丢失 | DAO 层写入, 不依赖 notifier; 失败时静默处理 (编辑仍在内存) |

---

## 八、验收标准

### 自动调整

- [ ] 点击"自动"按钮后, 3 秒内完成分析并应用参数
- [ ] 自动调整后参数可通过撤销恢复
- [ ] 按 `A` 键可触发自动调整
- [ ] 自动调整仅修改非默认参数, 不覆盖用户已调参数 (可选模式)

### 编辑快照

- [ ] 可创建命名快照, 快照列表持久化到数据库
- [ ] 可恢复到任意快照, 恢复后可撤销
- [ ] 可重命名和删除快照
- [ ] 重启应用后快照列表仍可用

### 操作历史

- [ ] 每次编辑操作自动记录到历史 (防抖 2 秒)
- [ ] 历史列表显示操作描述和时间
- [ ] 可点击历史节点回退到该状态
- [ ] 可清空历史 (保留快照)
- [ ] 历史上限 200 条, 超出自动清理

### 版本对比

- [ ] 可从快照面板发起版本对比
- [ ] 对比对话框并排显示快照和当前编辑的预览
- [ ] 参数 diff 高亮显示差异项
- [ ] 可选择恢复到快照或保持当前

### 自动保存

- [ ] 编辑后 2 秒无操作自动保存
- [ ] 切换照片时自动保存未保存的编辑
- [ ] 关闭查看器时自动保存未保存的编辑
- [ ] 设置中可开关各项自动保存行为
- [ ] 自动保存后"未保存"标记消失
- [ ] 手动保存按钮仍可用 (强制保存)

### 设置

- [ ] 设置页新增"编辑"分区
- [ ] 可配置自动保存开关、防抖延迟、切换/关闭时保存
- [ ] 可配置操作历史开关和上限

### 构建

- [ ] `dart run build_runner build` 无错误
- [ ] `flutter build windows --debug` 成功
- [ ] 应用启动无崩溃