# Changelog

All notable changes to Spectra will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
