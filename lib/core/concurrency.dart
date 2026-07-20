import 'dart:async';

/// 简单的信号量实现 — 限制并发后台任务数量，防止内存激增。
///
/// 特性：
/// - 支持超时机制：acquire(timeout) 超时后抛出 TimeoutException，
///   不会永久阻塞等待队列。
/// - 如果某个 acquire 的 release() 未被调用（例如调用方异常退出），
///   信号量会永久减少一个槽位，最终可能死锁。
///   调用方必须确保 release() 在 finally 块中被调用。
/// - 超时场景：导入时如果某张照片的 EXIF 读取卡死（损坏文件等），
///   超时后自动放弃该任务，释放信号量槽位给后续任务。
class Semaphore {
  final int _maxConcurrency;
  int _current = 0;
  final _waitQueue = <_QueuedRequest>[];

  Semaphore(this._maxConcurrency);

  /// 获取一个信号量许可，返回 release 回调函数。
  ///
  /// [timeout] 可选超时时间。超时后抛出 [TimeoutException]，
  /// 调用方应捕获并处理（跳过该任务，不重试）。
  ///
  /// ⚠️ 调用方必须在 finally 中调用 release()，否则信号量永久泄漏：
  /// ```dart
  /// final release = await semaphore.acquire();
  /// try {
  ///   // ... work ...
  /// } finally {
  ///   release();
  /// }
  /// ```
  Future<void Function()> acquire({Duration? timeout}) {
    if (_current < _maxConcurrency) {
      _current++;
      return Future.value(_release);
    }

    if (timeout != null && timeout.inMicroseconds <= 0) {
      throw TimeoutException('Semaphore acquire timed out', timeout);
    }

    final completer = Completer<void Function()>();
    final request = _QueuedRequest(completer);
    _waitQueue.add(request);

    if (timeout != null) {
      request.timer = Timer(timeout, () {
        // 超时：从等待队列中移除并完成 completer（抛出异常）
        _waitQueue.remove(request);
        if (!completer.isCompleted) {
          completer.completeError(
            TimeoutException('Semaphore acquire timed out', timeout),
          );
        }
      });
    }

    return completer.future;
  }

  void _release() {
    if (_waitQueue.isNotEmpty) {
      final next = _waitQueue.removeAt(0);
      next.timer?.cancel();
      if (!next.completer.isCompleted) {
        next.completer.complete(_release);
      }
    } else {
      _current--;
    }
  }
}

/// 等待队列中的请求项 — 关联 Completer 和 超时 Timer。
class _QueuedRequest {
  final Completer<void Function()> completer;
  Timer? timer;

  _QueuedRequest(this.completer);

  void _release() {
    if (_waitQueue.isNotEmpty) {
      final next = _waitQueue.removeAt(0);
      next.complete(_release);
    } else {
      _current--;
    }
  }
}