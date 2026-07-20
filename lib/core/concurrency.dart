import 'dart:async';

/// A simple Semaphore to limit concurrent background tasks and prevent memory spikes.
///
/// 注意：当前实现不包含超时机制。如果某个 acquire 的 release 未被调用
///（例如调用方 crash），信号量会永久减少一个槽位，最终可能死锁。
/// 调用方必须确保 release() 在 finally 块中被调用。
///
/// 若需要超时保护，可考虑使用 `async_timeout` 包或在 acquire 中加
/// `Future.timeout()` 包装。
class Semaphore {
  final int _maxConcurrency;
  int _current = 0;
  final _waitQueue = <Completer<void Function()>>[];

  Semaphore(this._maxConcurrency);

  /// Acquire a permit, returning a release callback.
  ///
  /// 调用方必须在 finally 中调用 release()，否则信号量永久泄漏：
  /// ```dart
  /// final release = await semaphore.acquire();
  /// try {
  ///   // ... work ...
  /// } finally {
  ///   release();
  /// }
  /// ```
  Future<void Function()> acquire() {
    if (_current < _maxConcurrency) {
      _current++;
      return Future.value(_release);
    }
    final completer = Completer<void Function()>();
    _waitQueue.add(completer);
    return completer.future;
  }

  void _release() {
    if (_waitQueue.isNotEmpty) {
      final next = _waitQueue.removeAt(0);
      next.complete(_release);
    } else {
      _current--;
    }
  }
}