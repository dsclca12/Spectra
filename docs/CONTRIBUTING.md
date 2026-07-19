# 贡献指南

> 感谢你对 Spectra 的关注！本文档帮助你了解如何参与项目贡献。

---

## 一、行为准则

本项目采用 [Contributor Covenant 行为准则](https://www.contributor-covenant.org/)。参与即表示你同意遵守其条款。不可接受的行为可向项目维护者报告。

---

## 二、如何贡献

### 2.1 报告 Bug

提交 Issue 前请：

1. 搜索已有 Issue 避免重复
2. 使用 Bug Report 模板
3. 提供完整的环境信息：
   - Flutter 版本（`flutter --version`）
   - Windows 版本（`winver`）
   - 照片目录规模和数量
   - 可复现的最小步骤

### 2.2 功能请求

使用 Feature Request 模板，清晰描述：

- 目标用户场景
- 期望行为
- 替代方案（如有）
- 是否愿意参与实现

### 2.3 提交代码

#### 首次贡献

```powershell
# 1. Fork 仓库
# 2. 克隆到本地
git clone https://github.com/spectra-dam/spectra.git
cd spectra

# 3. 添加上游 remote
git remote add upstream https://github.com/spectra-dam/spectra.git

# 4. 从 main 分支创建功能分支
git checkout -b feat/your-feature-name main
```

#### 分支命名规范

| 前缀 | 用途 | 示例 |
|------|------|------|
| `feat/` | 新功能 | `feat/ai-auto-tagging` |
| `fix/` | Bug 修复 | `fix/thumbnail-crash-large-files` |
| `refactor/` | 重构 | `refactor/metadata-service` |
| `docs/` | 文档 | `docs/api-usage-guide` |
| `perf/` | 性能优化 | `perf/thumbnail-batch-processing` |
| `test/` | 测试 | `test/photo-dao-coverage` |

#### 提交信息规范

使用 [Conventional Commits](https://www.conventionalcommits.org/)：

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

类型：`feat` `fix` `refactor` `perf` `test` `docs` `chore`

示例：
```
feat(grid): add adaptive column width based on panel size

Implement responsive grid that recalculates column count
when the center panel is resized.

Closes #123
```

---

## 三、开发环境

### 3.1 环境要求

- **Flutter**: 3.29+（Windows Stable 通道）
- **Windows**: Windows 10 20H2+ / Windows 11
- **Visual Studio**: 2022 Community/Professional/Enterprise（含 C++ 桌面开发工作负载）
- **Dart**: 随 Flutter SDK 自带

### 3.2 推荐工具

| 工具 | 用途 |
|------|------|
| VS Code + Flutter 扩展 | 主 IDE |
| Flutter DevTools | 性能分析/调试 |
| GitLens | Git 历史浏览 |
| Dart Code Metrics | 代码质量分析 |

### 3.3 验证环境

```powershell
flutter doctor -v
flutter config --enable-windows-desktop
```

---

## 四、代码规范

### 4.1 Dart 风格

- 遵循 [Effective Dart](https://dart.dev/effective-dart) 指南
- 使用 `dart format` 格式化代码
- 使用 `dart analyze` 无警告

### 4.2 项目规范

```dart
// ——— 命名 ———
// 文件: snake_case
// 类/类型: PascalCase
// 变量/方法: camelCase
// 常量: camelCase（Dart 惯例）
// 私有: _camelCase

// ——— import 顺序 ———
// 1. dart: 库
// 2. 第三方包（按字母序）
// 3. 项目内部（按字母序）
import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:spectra/core/constants.dart';
import 'package:spectra/data/database/app_database.dart';
import 'package:spectra/data/models/photo.dart';

// ——— Widget 组织 ———
// 1. const 构造函数
// 2. final fields
// 3. build() 方法
// 4. 私有方法（按调用顺序）
class PhotoGrid extends ConsumerWidget {
  const PhotoGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ...
  }
}
```

### 4.3 文档注释

```dart
/// 生成指定照片的缩略图。
///
/// 如果缩略图已存在缓存中，直接返回缓存路径。
/// 否则根据照片类型选择解码方式：
/// - JPEG/PNG → 使用 `image` 包解码缩放
/// - RAW → 使用 Windows Shell API
///
/// 生成的缩略图保存为 WebP 格式。
///
/// Throws [ThumbnailException] 如果生成失败。
Future<String> generateThumbnail(Photo photo) async {
  // ...
}
```

### 4.4 测试要求

| 代码类型 | 测试覆盖要求 |
|----------|-------------|
| DAO / Repository | 90%+ 行覆盖 |
| Service 业务逻辑 | 85%+ 行覆盖 |
| Provider | 主要状态路径覆盖 |
| Widget | 交互行为覆盖 |
| Screen | 集成测试覆盖核心流程 |

```dart
// ——— 单元测试示例 ———
void main() {
  group('PhotoDao', () {
    late AppDatabase db;
    late PhotoDao dao;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      dao = PhotoDao(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('insert and query photo', () async {
      final photo = Photo(
        path: r'C:\test\photo.jpg',
        fileName: 'photo.jpg',
        fileSize: 1024,
        modifiedAt: DateTime.now(),
        importedAt: DateTime.now(),
      );
      final id = await dao.insert(photo);
      final retrieved = await dao.getById(id);
      expect(retrieved, isNotNull);
      expect(retrieved!.path, equals(photo.path));
    });
  });
}
```

---

## 五、审查流程

### 5.1 PR 要求

- CI 全部通过（`dart analyze` + `flutter test`）
- 添加或更新了对应测试
- 更新了相关文档（如需要）
- 一个 PR 解决一个问题（保持小规模）

### 5.2 审查标准

| 维度 | 检查项 |
|------|--------|
| **正确性** | 代码是否按预期工作？边界情况是否处理？ |
| **可维护性** | 代码是否清晰？是否过度抽象或不足？ |
| **性能** | 是否有不必要的重建？I/O 是否在 Isolate 中？ |
| **安全** | 路径遍历风险？SQL 注入防护？ |
| **测试** | 测试是否覆盖核心逻辑？是否可重复？ |

### 5.3 合并策略

- 使用 **Squash Merge** 保持主分支历史清洁
- 合并前确保至少有 1 名维护者批准

---

## 六、文档贡献

### 6.1 文档位置

| 文档类型 | 位置 |
|----------|------|
| 项目文档 | `docs/` 目录 |
| 代码内文档 | Dart doc comments |
| README | 项目根目录 |

### 6.2 文档风格

- 使用 Markdown
- 中英文间加空格（如 "使用 Flutter 框架"）
- 代码块标注语言（````dart`）
- 路径和文件名用反引号包裹

---

## 七、获取帮助

| 渠道 | 用途 |
|------|------|
| GitHub Issues | Bug 报告 / 功能请求 |
| 项目 Discussions | 讨论 / 问答 |
| PR 评论 | 代码审查交流 |

---

再次感谢你的贡献！🎉
