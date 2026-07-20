# Spectra

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://img.shields.io/github/v/release/dsclca12/Spectra?style=flat-square&label=Release&color=blue">
    <img alt="GitHub Release" src="https://img.shields.io/github/v/release/dsclca12/Spectra?style=flat-square&label=Release&color=blue">
  </picture>
  <img alt="Platform" src="https://img.shields.io/badge/platform-Windows-blue?style=flat-square">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.29+-blue?style=flat-square&logo=flutter">
  <img alt="License" src="https://img.shields.io/github/license/dsclca12/Spectra?style=flat-square">
  <img alt="Stars" src="https://img.shields.io/github/stars/dsclca12/Spectra?style=flat-square">
  <img alt="PRs Welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square">
</p>

**面向专业摄影师的 Windows 桌面端照片分类与资产管理（DAM）应用**

> 分类优先，编辑交给专业工具。

Spectra 聚焦于摄影师工作流中最耗时的环节：**导入 → 筛选 → 标注 → 归档 → 搜索**。不做 RAW 编辑，而是作为 Lightroom / Capture One / Photoshop 等编辑工具的前置流程，帮助摄影师在拍摄后以最快速度完成照片的筛选和分类。

---

## 核心特性

### Phase 1 — MVP

| 特性 | 说明 |
|------|------|
| ⚡ **极速导入** | 文件夹导入 + 拖拽导入 + 文件夹监听增量扫描，即开即用 |
| 🖼️ **多视图浏览** | 自适应网格 / 列表 / 全屏查看器，流畅浏览万张照片 |
| ⭐ **分类三板斧** | 星级评分(1-5) + 旗标(Pick/Reject) + 色标(6色)，专业摄影师核心工作流 |
| 🏷️ **层级标签** | 关键词标签树，多对多关联，支持父子层级和批量操作 |
| 🔍 **组合筛选** | 星级 + 旗标 + 色标 + 日期 + 相机 + 关键词自由组合过滤 |
| 📷 **元数据展示** | EXIF 全字段读取（相机、镜头、焦距、ISO、光圈、快门、GPS） |
| 🎯 **全键盘操作** | 数字评分、P/U 旗标、F 键全屏、方向键浏览，全程无需鼠标 |
| 📦 **批量操作** | 多选后批量评分、批量标签、批量旗标 |
| 🗂️ **SQLite 目录** | Drift ORM 驱动的分类数据库，增量扫描，秒级启动 |
| 📸 **多格式支持** | JPEG/PNG/WebP/BMP/GIF + HEIC/HEIF/AVIF + TIFF + 各厂 RAW（见下表） |

### Phase 2 — 专业工作流

- 📝 **IPTC 编辑**：标题、描述、版权写入 XMP sidecar
- 📤 **智能导出**：按分类条件导出 + 变量重命名模板
- 💾 **自动备份**：导入同时备份到第二位置

---

## 支持的图像格式

Spectra 支持广泛的图像格式，包括各种 RAW 和现代压缩格式：

| 类别 | 格式 | 解码方式 | 备注 |
|------|------|----------|------|
| **标准格式** | JPEG, PNG, WebP, BMP, GIF | Flutter 原生（dart:ui / Skia） | 开箱即用 |
| **HEIC/HEIF** | .heic, .heif, .hif | Windows WIC | 需安装「HEIF 图像扩展」 |
| **AVIF** | .avif | Windows WIC | 需安装 AVIF codec |
| **TIFF** | .tif, .tiff | Windows WIC | 开箱即用 |
| **Canon RAW** | .cr2, .cr3, .crw | Windows WIC | 需安装 Raw Image Extension |
| **Nikon RAW** | .nef, .nrw | Windows WIC | 需安装 Raw Image Extension |
| **Sony RAW** | .arw, .sr2, .srf | Windows WIC | 需安装 Raw Image Extension |
| **Adobe DNG** | .dng | Windows WIC | 开箱即用 |
| **Fujifilm RAW** | .raf | Windows WIC | 需安装 Raw Image Extension |
| **Panasonic RAW** | .rw2, .raw | Windows WIC | 需安装 Raw Image Extension |
| **Olympus RAW** | .orf | Windows WIC | 需安装 Raw Image Extension |
| **Pentax RAW** | .pef | Windows WIC | 需安装 Raw Image Extension |
| **Samsung RAW** | .srw | Windows WIC | 需安装 Raw Image Extension |
| **其他 RAW** | .mrw, .x3f, .3fr, .fff, .iiq, .mos, .rwl, .kdc, .dcr, .r3d | Windows WIC | 需安装对应 codec pack |

### 安装 Codec Pack（可选）

RAW 和 HEIC 格式需要安装 Windows codec pack 才能生成缩略图和预览。从 Microsoft Store 免费安装：

- **HEIC/HEIF**：搜索「HEIF 图像扩展」（Microsoft Corporation）
- **RAW**：搜索「Raw Image Extension」（Microsoft Corporation），或安装相机厂商的 RAW codec pack

> 未安装 codec pack 时，对应格式会显示占位图而非缩略图，但不影响导入和元数据读取。

---

## 快速开始

### 📥 下载安装

从 [GitHub Releases](https://github.com/dsclca12/Spectra/releases) 下载最新版本：

```powershell
# 下载 spectra-*.windows-x64.zip 解压后直接运行 spectra.exe
# 无需安装，即解即用
```

> 如需 RAW/HEIC 支持，请从 Microsoft Store 安装 **Raw Image Extension** 和 **HEIF 图像扩展**。

### 🔧 从源码构建

#### 环境要求

- **Flutter**: 3.29+（Windows Stable 通道）
- **Windows**: Windows 10 20H2 或更高版本 / Windows 11
- **工具**: Visual Studio 2022（含"C++ 桌面开发"工作负载）

#### 构建步骤

```powershell
# 克隆项目
git clone https://github.com/dsclca12/Spectra.git
cd spectra

# 获取依赖
flutter pub get

# 运行
flutter run -d windows

# 构建发布包
flutter build windows --release
```

### 开发环境配置

```powershell
# 启用 Windows 桌面支持
flutter config --enable-windows-desktop

# 验证配置
flutter doctor -v
```

---

## 技术栈

| 层 | 技术 | 选型理由 |
|----|------|----------|
| **框架** | Flutter 3.29+ Windows Stable | 桌面生产就绪，跨平台潜质 |
| **状态管理** | Riverpod + `riverpod_generator` | 异步原生、编译安全、缓存控制 |
| **数据库** | Drift (SQLite ORM) | 类型安全、响应式 Stream、自动迁移 |
| **EXIF 读取** | `exif` + 文件头解析 | 纯 Dart，支持主流 RAW 格式 |
| **缩略图** | `dart:ui` + Windows WIC | 原生解码器，支持 RAW/HEIC |
| **文件监听** | `watcher` | 纯 Dart 增量扫描 |
| **图片查看** | `InteractiveViewer`（Flutter 内置） | 缩放/平移/手势/缓存 |
| **快捷键** | Flutter 内置 `Shortcuts` + `Actions` | 类型安全声明式 |

---

## 项目结构

```
spectra/
├── lib/                           # 🎯 应用核心代码
│   ├── main.dart                  #   应用入口
│   ├── app.dart                   #   根 Widget
│   ├── core/                      #   基础设施层
│   │   ├── constants.dart         #     全局常量 + 功能开关
│   │   ├── enums.dart             #     核心枚举类型
│   │   ├── theme.dart             #     主题系统
│   │   ├── errors.dart            #     错误定义
│   │   ├── logging.dart           #     日志系统
│   │   └── concurrency.dart       #     并发工具
│   ├── data/                      #   数据层
│   │   ├── database/              #     Drift ORM 数据库
│   │   │   ├── app_database.dart
│   │   │   ├── daos/              #     数据访问对象
│   │   │   └── migrations/        #     数据库迁移
│   │   ├── models/                #     数据模型
│   │   ├── services/              #     业务服务
│   │   └── ... 
│   ├── providers/                 #   Riverpod 状态管理
│   ├── ui/                        #   UI 层
│   │   ├── components/            #     通用可复用组件
│   │   ├── screens/               #     页面
│   │   └── layout/                #     布局组件
│   └── ...
├── assets/                        # 📁 资源文件
│   ├── icons/                     #     应用图标
│   └── shaders/                   #     GLSL 着色器
├── native/                        # 🔧 原生 FFI 模块
│   ├── ort_bridge/                #     ONNX Runtime 绑定
│   └── preprocess/                #     图像预处理
├── test/                          # 🧪 测试
│   ├── core/                      #     单元测试
│   ├── data/                      #     数据层测试
│   └── providers/                 #     Provider 测试
├── windows/                       # 🪟 Windows 平台代码
├── docs/                          # 📖 文档
├── .github/                       # 🤖 GitHub 配置
│   ├── workflows/                 #     CI/CD 工作流
│   ├── ISSUE_TEMPLATE/            #     Issue 模板
│   └── ...
├── pubspec.yaml
└── README.md
```

---

## 设计原则

1. **非破坏性** — 所有分类操作只修改数据库，从不修改原始文件
2. **速度优先** — 借鉴 Photo Mechanic 的设计哲学，每一步操作即时反馈
3. **键盘驱动** — 专业摄影师需要全键盘工作流
4. **离线优先** — 所有功能在本地完成，无需网络
5. **深色模式** — 暗光工作环境友好
6. **渐进式** — MVP 聚焦核心分类流程，后续逐步扩展

---

## 路线图

| Phase | 内容 | 时间 |
|-------|------|------|
| 🚀 **Phase 1** | MVP 核心分类工作流（导入 → 筛选 → 标注 → 搜索） | 🟢 已发布 v0.1.0 |
| 📝 **Phase 2** | 专业工作流 — IPTC 编辑、智能导出、自动备份 | 🔄 开发中 — 2026 Q4 |
| 🗺️ **Phase 3** | 进阶功能 — 地图视图、协作共享、脚本自动化 | 📅 规划中 — 2027 Q1+ |

详见 [ROADMAP.md](docs/ROADMAP.md)

---

## 文档索引

| 文档 | 说明 |
|------|------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | 软件架构详细说明 |
| [SPECIFICATION.md](docs/SPECIFICATION.md) | 功能规格说明书 |
| [DATABASE_SCHEMA.md](docs/DATABASE_SCHEMA.md) | 数据库 Schema 详细设计 |
| [UX_GUIDE.md](docs/UX_GUIDE.md) | UX 设计指南与交互规范 |
| [ROADMAP.md](docs/ROADMAP.md) | 详细路线图与里程碑 |
| [CONTRIBUTING.md](docs/CONTRIBUTING.md) | 贡献指南 |

---

## 许可

本项目采用 [Apache 2.0](LICENSE) 许可证。

---

## 致谢

Spectra 的设计参考和吸收了以下产品的优秀理念：

- **Photo Mechanic** — 速度至上的筛选工作流
- **Adobe Lightroom Classic** — 智能收藏集与分类体系
- **DigiKam** — 开源 DAM 的数据库设计
- **Capture One** — Session 模式的目录组织理念


