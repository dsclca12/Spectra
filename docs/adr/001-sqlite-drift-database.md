# 1. ADR-001: SQLite + Drift as Local Database

## Status

Accepted (initial architecture decision).

## Context

Spectra needs a local database to store photo metadata (EXIF), classification data (ratings, flags, labels, tags), and indexing state. Requirements:

- **Local-only**: No network dependency for core operations.
- **SQL-based**: Rich query support for combined filtering.
- **Type-safe**: Dart compile-time checks for queries.
- **Reactive**: Stream support for live UI updates.
- **Schema migrations**: Support for evolving schema across versions.

Options considered: Drift (SQLite ORM), Hive, Isar, raw sqflite, objectbox.

## Decision

Use **Drift** (formerly Moor) as the database layer, backed by SQLite via `sqlite3_flutter_libs`.

Rationale:

1. Drift generates type-safe Dart code from SQL or DAO definitions.
2. Built-in `Stream` support for reactive queries.
3. Automatic migration generation between schema versions.
4. Mature ecosystem with Flutter desktop support.
5. SQLite is battle-tested for local-first applications.

## Consequences

- Schema changes require migration scripts.
- SQLite concurrency requires careful write serialization (WAL mode + single writer).
- RAW file metadata extracted at import time is stored in SQLite; full EXIF reread from file on demand.
