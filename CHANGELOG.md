# Changelog

All notable changes to Spectra will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
