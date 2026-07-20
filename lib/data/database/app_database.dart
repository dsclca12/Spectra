// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables.dart';
import 'daos/photo_dao.dart';
import 'daos/tag_dao.dart';
import 'daos/folder_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/edit_dao.dart';
import 'daos/edit_snapshot_dao.dart';
import 'daos/edit_history_dao.dart';

part 'app_database.g.dart';

/// Spectra 主数据库
@DriftDatabase(
  tables: [Photos, Folders, Tags, PhotoTags, Collections, CollectionPhotos, AppSettings, PhotoEdits, EditSnapshots, EditHistory],
  daos: [PhotoDao, TagDao, FolderDao, SettingsDao, EditDao, EditSnapshotDao, EditHistoryDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// 创建文件系统数据库实例
  static Future<AppDatabase> create() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'spectra.db'));
    return AppDatabase(NativeDatabase.createInBackground(
      file,
      setup: (db) {
        // ── SQLite 性能 PRAGMA ──
        // WAL 模式：读写不互斥，并发性能大幅提升
        db.execute('PRAGMA journal_mode=WAL;');
        // 外键约束
        db.execute('PRAGMA foreign_keys=ON;');
        // 正常同步级别 — WAL 模式下 NORMAL 足够安全且更快
        // (FULL 在每次事务后 fsync，NORMAL 只在 checkpoint 时 fsync)
        db.execute('PRAGMA synchronous=NORMAL;');
        // 临时表/排序使用 20MB 内存，避免磁盘临时文件
        db.execute('PRAGMA temp_store=MEMORY;');
        // 20MB 页缓存（约 5120 页 × 4KB），覆盖大多数工作集
        db.execute('PRAGMA cache_size=-20480;');
        // 启用 cache_spill — SQLite 在缓存满时自动将脏页刷入磁盘
        // 注意：cache_spill 是布尔值（ON/OFF），不是页数！
        // 旧代码曾错误写成 cache_spill=200（用数值表示条数），
        // SQLite 会静默忽略无效值导致 cache_spill=OFF
        db.execute('PRAGMA cache_spill=ON;');
        // mmap 映射 256MB — 大数据库读取不经过页缓存直接内存映射
        // 适合照片管理场景的频繁只读查询（浏览/筛选）
        db.execute('PRAGMA mmap_size=268435456;');
        // WAL 自动 checkpoint 每 1000 页
        db.execute('PRAGMA wal_autocheckpoint=1000;');
        // 优化 LIKE/IN 子句的索引使用 — 查询照片文件名/标签时受益
        db.execute('PRAGMA case_sensitive_like=OFF;');
      },
    ));
  }

  /// 创建内存数据库实例（用于测试）
  factory AppDatabase.forTesting(QueryExecutor e) => AppDatabase(e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        // 创建索引
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photos_folder_id ON photos(folder_id);');
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photos_thumbnail_status ON photos(thumbnail_status);');
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_folders_parent_id ON folders(parent_id);');
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_tags_parent_id ON tags(parent_id);');
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photos_date_taken ON photos(date_taken);');
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photos_imported_at ON photos(imported_at);');
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photos_rating ON photos(rating);');
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photos_pick_label ON photos(pick_label);');
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photos_color_label ON photos(color_label);');
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photos_camera ON photos(camera_make, camera_model);');
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photos_file_hash ON photos(file_hash);');
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photos_file_name ON photos(file_name);');
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photos_folder_rating_date ON photos(folder_id, rating, date_taken);');
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_photos_folder_pick ON photos(folder_id, pick_label);');

        // 初始化默认设置
        await into(appSettings).insert(
          AppSetting(key: 'schema_version', value: '1', group: 'system'),
        );
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          // v2: 添加照片编辑参数表
          await m.createTable(photoEdits);
        }
        if (from < 3) {
          // v3: 添加编辑快照表和操作历史表
          await m.createTable(editSnapshots);
          await m.createTable(editHistory);
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_edit_snapshots_photo_id ON edit_snapshots(photo_id);');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_edit_history_photo_id ON edit_history(photo_id);');
        }
      },
    );
  }
}
