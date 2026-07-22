# Spectra

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://img.shields.io/github/v/release/dsclca12/Spectra?style=flat-square&label=Release&color=blue">
    <img alt="GitHub Release" src="https://img.shields.io/github/v/release/dsclca12/Spectra?style=flat-square&label=Release&color=blue">
  </picture>
  <img alt="Platform" src="https://img.shields.io/badge/platform-Windows%20%7C%20Linux-blue?style=flat-square">
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-3.29+-blue?style=flat-square&logo=flutter">
  <img alt="License" src="https://img.shields.io/github/license/dsclca12/Spectra?style=flat-square">
  <img alt="Stars" src="https://img.shields.io/github/stars/dsclca12/Spectra?style=flat-square">
  <img alt="PRs Welcome" src="https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square">
  <img alt="Last Commit" src="https://img.shields.io/github/last-commit/dsclca12/Spectra?style=flat-square">
  <img alt="Issues" src="https://img.shields.io/github/issues/dsclca12/Spectra?style=flat-square">
</p>

<p align="center">
  <a href="README.md"><strong>🇨🇳 中文</strong></a> ·
  <a href="README.en.md"><strong>🇬🇧 English</strong></a>
</p>

<p align="center">
  <em>A cross-platform (Windows / Linux) desktop photo categorization &amp; asset management (DAM) app for professional photographers.</em>
</p>

> **Classify first, edit with专业 tools.**  
> Spectra focuses on the most time-consuming phase of a photographer's workflow: **import → cull → tag → archive → search**. It does NOT replace RAW editors — instead, it acts as a front-end workflow tool for Lightroom / Capture One / Photoshop, helping photographers cull and categorize photos at maximum speed after a shoot.

> 🐧 **Linux Support**: Spectra now supports Linux desktop builds (Flutter Linux). Latest releases include `*-linux-x64.tar.gz` downloads.

---

## ✨ Features

### Phase 1 — MVP ✅

| Feature | Description |
|---------|-------------|
| ⚡ **Lightning Import** | Folder import + drag-and-drop + folder watch for incremental scanning |
| 🖼️ **Multi-View Browsing** | Adaptive grid / list / full-screen viewer, smooth with 10K+ photos |
| ⭐ **Cull Trio** | Star ratings (1-5) + flags (Pick/Reject) + color labels (6 colors) |
| 🏷️ **Hierarchical Tags** | Keyword tag tree, M:N associations, parent-child, batch ops |
| 🔍 **Combined Filtering** | Stars + flags + colors + date + camera + keywords, freely combinable |
| 📷 **EXIF Metadata** | Full EXIF readout (camera, lens, focal length, ISO, aperture, shutter, GPS) |
| 🎯 **Keyboard-Driven** | Numeric ratings, P/U flags, F fullscreen, arrow navigation — no mouse needed |
| 📦 **Batch Operations** | Batch rate, batch tag, batch flag for multi-selected photos |
| 🗂️ **SQLite Catalog** | Drift ORM catalog DB, incremental scan, instant startup |
| 📸 **Multi-Format** | JPEG/PNG/WebP/BMP/GIF + HEIC/HEIF/AVIF + TIFF + all major RAW formats |
| 🐧 **Linux Support** | Flutter Linux desktop, AppImage / tar.gz distribution |

### Phase 2 — Professional Workflow 🔄

- 📝 **IPTC Editing**: Title, description, copyright — write to XMP sidecar
- 📤 **Smart Export**: Export by filter criteria + variable rename templates
- 💾 **Auto Backup**: Simultaneous backup on import

### Phase 3 — Advanced 🗺️

- 🗺️ **Map View**: Geo-tagged photo map
- 🤝 **Collaboration**: Shared catalogs
- ⚙️ **Script Automation**: Custom automation scripts

---

## 📸 Supported Formats

| Category | Formats | Decoder | Notes |
|----------|---------|---------|-------|
| **Standard** | JPEG, PNG, WebP, BMP, GIF | Flutter native (dart:ui / Skia) | Out of the box |
| **HEIC/HEIF** | .heic, .heif, .hif | Windows WIC | Requires "HEIF Image Extensions" |
| **AVIF** | .avif | Windows WIC | Requires AVIF codec |
| **TIFF** | .tif, .tiff | Windows WIC | Out of the box |
| **Canon RAW** | .cr2, .cr3, .crw | Windows WIC | Requires Raw Image Extension |
| **Nikon RAW** | .nef, .nrw | Windows WIC | Requires Raw Image Extension |
| **Sony RAW** | .arw, .sr2, .srf | Windows WIC | Requires Raw Image Extension |
| **Adobe DNG** | .dng | Windows WIC | Out of the box |
| **Fujifilm RAW** | .raf | Windows WIC | Requires Raw Image Extension |
| **Panasonic RAW** | .rw2, .raw | Windows WIC | Requires Raw Image Extension |
| **Olympus RAW** | .orf | Windows WIC | Requires Raw Image Extension |
| **Pentax RAW** | .pef | Windows WIC | Requires Raw Image Extension |
| **Samsung RAW** | .srw | Windows WIC | Requires Raw Image Extension |
| **Other RAW** | .mrw, .x3f, .3fr, .fff, .iiq, .mos, .rwl, .kdc, .dcr, .r3d | Windows WIC | Requires codec pack |

### Codec Packs (Optional)

Install from Microsoft Store for RAW/HEIC thumbnail/preview support:

- **HEIC/HEIF**: Search for "HEIF Image Extensions" (Microsoft Corporation)
- **RAW**: Search for "Raw Image Extension" (Microsoft Corporation)

> Without codec packs, unsupported formats show placeholder thumbnails. Import and metadata reading still work normally.

---

## 🚀 Quick Start

### 📥 Download

Get the latest build from [GitHub Releases](https://github.com/dsclca12/Spectra/releases):

```powershell
# Download spectra-*.windows-x64.zip, extract and run spectra.exe
# No installation required — just extract and launch
```

### 🔧 Build from Source

#### Windows Build

##### Prerequisites

- **Flutter**: 3.29+ (Windows Stable channel)
- **Windows**: Windows 10 20H2+ / Windows 11
- **Tools**: Visual Studio 2022 (with "Desktop development with C++" workload)

##### Steps

```powershell
# Clone
git clone https://github.com/dsclca12/Spectra.git
cd spectra

# Enable Windows desktop
flutter config --enable-windows-desktop

# Dependencies
flutter pub get

# Run
flutter run -d windows

# Build release
flutter build windows --release
```

#### Linux Build

##### Prerequisites

- **Flutter**: 3.29+ (Linux Stable channel)
- **Linux**: Ubuntu 20.04+ / Debian 11+ / Fedora 38+ etc.
- **Tools**: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`, `liblzma-dev`

##### Install Linux system dependencies

```bash
# Debian / Ubuntu
sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev
```

##### Build Steps

```bash
# Clone
git clone https://github.com/dsclca12/Spectra.git
cd spectra

# Enable Linux desktop
flutter config --enable-linux-desktop

# Dependencies
flutter pub get

# One-liner: build native libs + Flutter Linux release
./scripts/build.sh release

# Or step by step:
# 1. Build native C libraries
./scripts/build.sh native
# 2. Build Flutter Linux release
flutter build linux --release
# 3. Package as tar.gz
cd build/linux/x64/release
tar czf spectra-$(date +%Y%m%d)-linux-x64.tar.gz bundle/
```

The build output is in `build/linux/x64/release/bundle/`, containing the `spectra` executable and all dependencies.

---

## 🏗️ Tech Stack

| Layer | Technology | Rationale |
|-------|------------|-----------|
| **Framework** | Flutter 3.29+ Windows Stable | Desktop-ready, cross-platform potential |
| **State Management** | Riverpod + `riverpod_generator` | Async-native, compile-safe, cache control |
| **Database** | Drift (SQLite ORM) | Type-safe, reactive streams, auto migration |
| **EXIF Reading** | `exif` + file header parsing | Pure Dart, supports major RAW formats |
| **Thumbnails** | `dart:ui` + Windows WIC | Native decoders, RAW/HEIC support |
| **File Watching** | `watcher` | Pure Dart incremental scan |
| **Image Viewer** | `InteractiveViewer` (Flutter built-in) | Zoom/pan/gestures/caching |
| **Shortcuts** | Flutter `Shortcuts` + `Actions` | Type-safe declarative keybindings |

---

## 📁 Project Structure

```
spectra/
├── lib/                           # 🎯 Application core
│   ├── main.dart                  #   Entry point
│   ├── app.dart                   #   Root widget
│   ├── core/                      #   Infrastructure
│   │   ├── constants.dart         #     Globals + feature flags
│   │   ├── enums.dart             #     Core enums
│   │   ├── theme.dart             #     Theme system
│   │   ├── errors.dart            #     Error definitions
│   │   ├── logging.dart           #     Logging
│   │   └── concurrency.dart       #     Concurrency utils
│   ├── data/                      #   Data layer
│   │   ├── database/              #     Drift ORM
│   │   │   ├── app_database.dart
│   │   │   ├── daos/
│   │   │   └── migrations/
│   │   ├── models/
│   │   ├── services/
│   │   └── ...
│   ├── providers/                 #   Riverpod state
│   ├── ui/                        #   UI layer
│   │   ├── components/
│   │   ├── screens/
│   │   └── layout/
│   └── ...
├── assets/                        # 📁 Resources
├── native/                        # 🔧 Native FFI
│   ├── ort_bridge/                #     ONNX Runtime bindings
│   └── preprocess/                #     Image preprocessing
├── test/                          # 🧪 Tests
├── windows/                       # 🪟 Windows platform
├── docs/                          # 📖 Documentation
└── README.md
```

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Software architecture |
| [SPECIFICATION.md](docs/SPECIFICATION.md) | Functional specification |
| [DATABASE_SCHEMA.md](docs/DATABASE_SCHEMA.md) | Database schema design |
| [UX_GUIDE.md](docs/UX_GUIDE.md) | UX design guidelines |
| [ROADMAP.md](docs/ROADMAP.md) | Roadmap & milestones |
| [CHANGELOG.md](CHANGELOG.md) | Release history |
| [CONTRIBUTING.md](docs/CONTRIBUTING.md) | Contribution guide |

---

## 🎯 Design Principles

1. **Non-destructive** — All classification operations modify only the database, never original files.
2. **Speed First** — Inspired by Photo Mechanic's philosophy; every action should feel instant.
3. **Keyboard-Driven** — Professional photographers need full keyboard workflows.
4. **Offline-First** — All features work locally; no network required.
5. **Dark Mode** — Optimized for low-light working environments.
6. **Progressive** — MVP focuses on core classification; more features added incrementally.

---

## 📄 License

Licensed under [Apache 2.0](LICENSE).

---

## 🙏 Acknowledgments

Spectra's design has been influenced by:

- **Photo Mechanic** — Speed-obsessed culling workflow
- **Adobe Lightroom Classic** — Smart collections & taxonomy
- **DigiKam** — Open-source DAM database design
- **Capture One** — Session-based catalog philosophy
