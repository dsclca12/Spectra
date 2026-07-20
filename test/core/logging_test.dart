import 'package:flutter_test/flutter_test.dart';

import 'package:spectra/core/logging.dart';

void main() {
  group('LogEntry', () {
    test('创建 LogEntry 字段正确', () {
      final entry = LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        category: 'Test',
        message: 'Hello',
        details: 'details',
      );
      expect(entry.level, LogLevel.info);
      expect(entry.category, 'Test');
      expect(entry.message, 'Hello');
      expect(entry.details, 'details');
    });

    test('toString 包含关键字段', () {
      final entry = LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.warn,
        category: 'Import',
        message: 'Duplicate',
      );
      final str = entry.toString();
      expect(str, contains('[WARN]'));
      expect(str, contains('Import'));
      expect(str, contains('Duplicate'));
    });
  });

  group('AppLogger', () {
    test('info 记录日志不抛异常', () {
      expect(
        () => AppLogger.info('Test', 'message'),
        returnsNormally,
      );
    });

    test('warn 记录日志不抛异常', () {
      expect(
        () => AppLogger.warn('Test', 'warning'),
        returnsNormally,
      );
    });

    test('error 记录日志不抛异常', () {
      expect(
        () => AppLogger.error('Test', 'error'),
        returnsNormally,
      );
    });

    test('entries 返回最近的日志', () {
      AppLogger.info('Test', 'log1');
      AppLogger.info('Test', 'log2');
      final logs = AppLogger.entries;
      expect(logs.length, greaterThanOrEqualTo(2));
    });

    test('clear 清除所有日志', () {
      AppLogger.info('Test', 'to be cleared');
      AppLogger.clear();
      expect(AppLogger.entries, isEmpty);
    });
  });
}
