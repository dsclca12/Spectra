# Changelog

All notable changes to Spectra will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.4.10] — 2026-07-20

### Added

- **English README**: New `README.en.md` with full English translation of the project documentation.
- **Language Switcher**: README now has 🇨🇳/🇬🇧 toggle at the top for bilingual navigation.
- **CI Format Check**: `dart format --set-exit-if-changed` added to CI pipeline to enforce code style.

### Changed

- **CHANGELOG.md**: Backfilled all v0.4.0–v0.4.9 release notes (previously only contained v0.3.0 and earlier).
- **CITATION.cff**: Version updated to 0.4.10.
- **SECURITY.md**: Supported versions table updated (0.4.x active, 0.3.x maintenance, <0.3 EOL).
- **FUNDING.yml**: Cleaned up template placeholders.
- **.gitattributes**: Added `*.iss` (Inno Setup) to LF text handling.

### Documentation

- Added GitHub badges for `last-commit` and `issues` to both Chinese and English READMEs.
- Added CHANGELOG.md link to documentation index in both README versions.
- Updated README Phase 2/3 descriptions with clearer status indicators.

---

## [0.4.9] — 2026-07-20

### Performance

- **NativePreprocessService**: Async lazy DLL loading — constructor no longer blocks on `file.existsSync()`. Falls back to pure Dart automatically. Uses `Platform.resolvedExecutable` instead of `Directory.current` for more reliable path resolution.
- **PhotoGrid Context Menu**: Added comprehensive Chinese performance comments documenting the `ref.invalidate` batch operation design decisions.

---

## [0.4.8] — 2026-07-20

### Performance

- **ThumbnailService LRU**: Batch eviction (10% of oldest entries) instead of single-entry removal, reducing boundary thrashing.
- **SettingsProvider resetAll**: Single `DELETE FROM app_settings` instead of ~50 individual `deleteSetting()` calls — ~50× faster reset.
- **ImageEditService**: Replaced custom `_pow` (recursive, stack overflow risk), `_sqrt` (Newton iteration ×20), and `_rgbSaturation` (per-pixel `List` allocation) with `dart:math` equivalents and inline comparisons. Zero-allocation saturation, CPU-instruction-level sqrt, C-level pow.

---

## [0.4.7] — 2026-07-20

### Fixed

- **Concurrency**: Removed unreachable `_QueuedRequest._release()` dead code that referenced out-of-scope variables — potential compile error.
- **ExportService**: Filename conflict counter now has a 9999 upper bound with timestamp fallback, preventing infinite loops in extreme edge cases.

### Performance

- **TagService batchAddTag/batchRemoveTag**: Replaced N individual `await` calls with drift batch API and single `DELETE WHERE photo_id IN (...)`. 100 photos: ~500ms → ~10ms.
- **ExportService**: `dir.listSync()` → `await dir.list()` for async directory traversal, no longer blocking the event loop.

---

## [0.4.6] — 2026-07-20

### Performance

- **FileSystemService**: `dir.listSync()` → `dir.list()` async traversal. Large directory scans no longer block the event loop for hundreds of milliseconds.
- **ExportService**: Pre-read target directory filenames into `Set<String>` for O(1) conflict detection instead of N disk I/O operations.

### Documentation

- Comprehensive Chinese performance annotations added to `FileSystemService`, `_walkDirectory`, `_listFilesInDirectory`, and `ExportService`.

---

## [0.4.5] — 2026-07-20

### Documentation

- Chinese performance annotations for `ExportService`, `ImageDecoderService`, `EditProvider`, `SettingsProvider`, `PhotoGrid`, and `main.dart`.

---

## [0.4.4] — 2026-07-20

### Documentation

- Version sync and continued Chinese annotation coverage across service and provider layers.

---

## [0.4.3] — 2026-07-20

### Documentation

- Full Chinese annotation pass for core modules: `ExportService`, `ImageDecoderService`, `EditProvider`, `SettingsProvider`, `PhotoGrid`, `main.dart`.

---

## [0.4.2] — 2026-07-20

### Performance

- **TagDao.mergeTags**: `batch.insertAll` replaces per-row `insert`, reducing N photo tag migrations from N INSERTs to 1 batch write.
- **countFiltered**: Extended to support date, camera, and search scope parameters — `catalogService.countPhotos` now passes all filter conditions.

### Documentation

- Chinese annotations added to `MetadataService`, `PhotoDao`, `SelectionProvider`, `ViewModeProvider`.

---

## [0.4.1] — 2026-07-20

### Performance

- **FolderDao.repairAllPhotoCounts**: Single `GROUP BY` query replaces N individual `COUNT` queries — folder count repair drops from O(N) to O(1) DB round-trips.
- **Composite Indexes**: Added covering indexes for common filter combinations (folder+color, folder+pick+rating, camera+date).

### Fixed

- **Semaphore**: Added timeout mechanism to prevent deadlock on hung tasks.

### Documentation

- Chinese annotations added to core files (`main.dart`, providers, services).

---

## [0.4.0] — 2026-07-20

### Performance

- **ExportService**: Introduced `Semaphore(4)` parallel copy — replaces serial `await` per file, dramatically improving export throughput.
- **GridPanel**: `.select()` on `viewMode` prevents full middle-column rebuild on panel visibility changes.
- **FilterBar**: `.select()` on `viewMode` prevents unnecessary rebuilds from unrelated state changes.
- **Version sync**: `pubspec.yaml`, `constants.dart`, `strings.dart` unified to 0.4.0.

### Documentation

- Detailed Chinese performance annotations explaining the intent behind each optimization.

---

## [0.3.0] — 2026-07-20

### Added

- **Scroll Pagination**: New `catalogPageOffsetProvider` for incremental page loading (200 photos/page).
- **Import Dialog Deduplication**: Shared `showImportDialog()` function eliminating duplicate dialog code.

### Changed

- **Import Screens Refactored**: `HomeScreen` and `GridPanel` now share the same import dialog logic.

### Technical

- Decoupled import dialog from widget tree into standalone utility function.

---

## [0.2.1] — 2026-07-20

### Fixed

- **Parallelized Import Dedup**: `getExistingPaths()` batch SQLite IN queries now run in parallel via `Future.wait`, yielding 3-8× faster dedup for 5000+ file imports.

### Performance

- SQLite WAL mode's concurrent-read capability is now fully utilized during import deduplication.

---

## [0.2.0] — 2026-07-20

### Fixed

- **SQLite `cache_spill` PRAGMA**: `PRAGMA cache_spill=200` was silently ignored because `cache_spill` is a boolean (ON/OFF), not a page count. Fixed to `PRAGMA cache_spill=ON`.
- **Fire-and-forget Safety**: Added `.catchError()` fallback to EXIF background tasks in `ImportService` to prevent unhandled promise rejections.

### Performance

- **Thumbnail Cache Stats**: `getCacheSize()` and `pruneCache()` now use `Future.wait` for parallel `stat()` calls, 5-10× faster on directories with thousands of files.
- **LRU Cache Cleanup**: Batch file deletion instead of serial `await` per file, reducing I/O round-trips.
- **WIC Decode Concurrency**: Increased from 4 to 6 (I/O-bound workload, low CPU impact).
- **Temp File Collision Fix**: Replaced `DateTime.microsecondsSinceEpoch` with atomic counter for WIC temp file names.
- **Stale Temp File Cleanup**: Added `cleanStaleTempFiles()` to purge WIC temp files older than 24 hours.
- **RAW Preview Lazy Cleanup**: Auto-clean preview cache every 50 new previews to prevent unbounded disk usage.

### Changed

- **Filmstrip Rebuild Scope**: Used `Selector` to isolate selection state listening, avoiding full panel rebuild on unrelated selection changes.
- **Semaphore Documentation**: Added concurrency safety notes and `finally`-guarded usage contract.

---

## [0.1.0] — 2026-07-20

### Added

- **Photo Import**: Folder import, drag-and-drop import, and folder watch for incremental scanning.
- **Multi-View Browsing**: Adaptive grid, list, and full-screen viewer for smooth browsing of thousands of photos.
- **Rating System**: 1–5 star ratings, pick/reject flags, and 6-color labels.
- **Hierarchical Tags**: Keyword tag tree with many-to-many associations, parent-child hierarchy, and batch operations.
- **Combined Filtering**: Freeform combination of star ratings, flags, color labels, date range, camera model, and keywords.
- **EXIF Metadata**: Full EXIF field reading (camera, lens, focal length, ISO, aperture, shutter speed, GPS).
- **Keyboard Workflow**: Numeric ratings, P/U flags, F fullscreen, arrow key navigation — no mouse needed.
- **Batch Operations**: Batch rating, batch tagging, batch flagging for multi-selected photos.
- **SQLite Catalog**: Drift ORM-powered catalog database with incremental scanning and instant startup.
- **Multi-Format Support**: JPEG, PNG, WebP, BMP, GIF, HEIC/HEIF, AVIF, TIFF, and major RAW formats (CR3, NEF, ARW, DNG, RAF, RW2, ORF, PEF, SRW).

### Technical

- Flutter 3.29+ Windows desktop application.
- Riverpod for state management with compile-time safety.
- Drift (SQLite ORM) with type-safe queries and reactive streams.
- Native Windows WIC integration for RAW/HEIC thumbnail decoding.
- ONNX Runtime FFI for neural auto-adjust features.
