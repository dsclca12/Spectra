// SPDX-License-Identifier: Apache-2.0

/// Application log service — unified log recording and inspection.
///
/// Provides an in-memory ring buffer to store recent logs, viewable from the settings UI.
/// Also outputs via debugPrint (visible in the terminal / IDE Console).
///
/// Usage:
/// ```dart
/// AppLogger.info('Catalog', 'Scan complete', details: 'Found 1234 photos');
/// AppLogger.warn('Import', 'Duplicate file skipped', details: 'path/to/file.jpg');
/// AppLogger.error('Database', 'Migration failed', details: e.toString());
/// ```
library;

import 'dart:collection';
import 'package:flutter/foundation.dart' show debugPrint;

/// Log severity levels.
enum LogLevel {
  debug,
  info,
  warn,
  error,
}

/// A single log entry.
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String category;
  final String message;
  final String? details;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.details,
  });

  String get levelLabel {
    return switch (level) {
      LogLevel.debug => 'DEBUG',
      LogLevel.info => 'INFO ',
      LogLevel.warn => 'WARN ',
      LogLevel.error => 'ERROR',
    };
  }

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  @override
  String toString() => _format();

  String _format() {
    final cat = category.padRight(10);
    final base = '[$formattedTime] [$levelLabel] [$cat] $message';
    if (details != null) {
      // Replace newlines in details with spaces for single-line log
      final cleanDetails = details!.replaceAll('\n', ' | ');
      return '$base\n                          $cleanDetails';
    }
    return base;
  }
}

/// Application logging service — singleton.
class AppLogger {
  AppLogger._();

  /// Maximum log entries stored in memory.
  static const int _maxEntries = 1000;

  static final ListQueue<LogEntry> _entries = ListQueue(_maxEntries);

  /// All log entries (last 1000, most recent first).
  static List<LogEntry> get entries => _entries.toList(growable: false);

  /// Filter log entries by category.
  static List<LogEntry> entriesByCategory(String category) {
    return _entries.where((e) => e.category == category).toList();
  }

  /// Filter log entries by minimum level.
  static List<LogEntry> entriesByLevel(LogLevel minLevel) {
    return _entries.where((e) => e.level.index >= minLevel.index).toList();
  }

  /// Clear all log entries.
  static void clear() => _entries.clear();

  // ─── Log Methods ───

  static void debug(String category, String message, {String? details}) {
    _add(LogLevel.debug, category, message, details);
  }

  static void info(String category, String message, {String? details}) {
    _add(LogLevel.info, category, message, details);
  }

  static void warn(String category, String message, {String? details}) {
    _add(LogLevel.warn, category, message, details);
  }

  static void error(String category, String message, {String? details}) {
    _add(LogLevel.error, category, message, details);
  }

  static void _add(
    LogLevel level,
    String category,
    String message,
    String? details,
  ) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: message,
      details: details,
    );

    // 写入内存环形缓冲
    if (_entries.length >= _maxEntries) {
      _entries.removeFirst();
    }
    _entries.addLast(entry);

    // 输出到 debugPrint
    debugPrint(entry.toString());
  }
}

