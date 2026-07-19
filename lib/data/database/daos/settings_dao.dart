import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'settings_dao.g.dart';

/// 应用设置数据访问对象
@DriftAccessor(tables: [AppSettings])
class SettingsDao extends DatabaseAccessor<AppDatabase> with _$SettingsDaoMixin {
  SettingsDao(super.db);

  /// 获取设置值
  Future<String?> get(String key) async {
    final result =
        await (select(appSettings)..where((s) => s.key.equals(key))).get();
    return result.isEmpty ? null : result.first.value;
  }

  /// 设置值（UPSERT）
  Future<void> set(String key, String value, {String? group}) =>
      into(appSettings).insertOnConflictUpdate(
        AppSetting(key: key, value: value, group: group),
      );

  /// 按分组获取设置
  Future<Map<String, String>> getByGroup(String group) async {
    final result = await (select(appSettings)
          ..where((s) => s.group.equals(group)))
        .get();
    return {for (final s in result) s.key: s.value};
  }

  /// 删除设置
  Future<int> deleteSetting(String key) =>
      (this.delete(appSettings)..where((s) => s.key.equals(key))).go();

  /// 获取所有设置
  Future<Map<String, String>> getAll() async {
    final result = await select(appSettings).get();
    return {for (final s in result) s.key: s.value};
  }
}