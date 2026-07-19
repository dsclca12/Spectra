import 'dart:async';

/// A simple Semaphore to limit concurrent background tasks and prevent memory spikes.
class Semaphore {
  final int _maxConcurrency;
  int _current = 0;
  final _waitQueue = <Completer<void Function()>>[];

  Semaphore(this._maxConcurrency);

  /// Acquire a permit, returning a release callback.
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