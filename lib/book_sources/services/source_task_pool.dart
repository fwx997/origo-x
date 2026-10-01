import 'dart:async';

import 'book_download_cancellation.dart';

/// Bounded work queue shared by book-source requests, with per-host fairness.
class SourceTaskPool {
  SourceTaskPool({this.limit = 12, this.perHost = 2})
    : assert(limit > 0),
      assert(perHost > 0);

  static final network = SourceTaskPool();
  static final scripts = SourceTaskPool(limit: 2, perHost: 1);
  final int limit;
  final int perHost;
  final List<_QueuedSourceTask> _queue = [];
  final Map<String, int> _hosts = {};
  int _active = 0;

  Future<T> run<T>(
    String host,
    Future<T> Function() work, {
    BookDownloadCancellation? cancellation,
  }) {
    final result = Completer<T>();
    final zone = Zone.current;
    final task = _QueuedSourceTask(host, () async {
      try {
        cancellation?.throwIfCancelled();
        result.complete(await zone.run(work));
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    void cancelQueued() {
      if (!_queue.remove(task)) return;
      result.completeError(const BookDownloadCancelledException());
    }

    _queue.add(task);
    cancellation?.addListener(cancelQueued);
    _drain();
    return result.future.whenComplete(
      () => cancellation?.removeListener(cancelQueued),
    );
  }

  void _drain() {
    while (_active < limit) {
      final index = _queue.indexWhere((t) => (_hosts[t.host] ?? 0) < perHost);
      if (index < 0) return;
      final task = _queue.removeAt(index);
      _active++;
      _hosts[task.host] = (_hosts[task.host] ?? 0) + 1;
      unawaited(
        task.work().whenComplete(() {
          _active--;
          _hosts[task.host] = _hosts[task.host]! - 1;
          _drain();
        }),
      );
    }
  }
}

class _QueuedSourceTask {
  const _QueuedSourceTask(this.host, this.work);
  final String host;
  final Future<void> Function() work;
}

/// Cancellation follows the complete request/parse chain without changing
/// every public client signature (including third-party client subclasses).
class SourceTaskContext {
  static final _key = Object();
  static BookDownloadCancellation? get cancellation =>
      Zone.current[_key] as BookDownloadCancellation?;

  static Future<T> run<T>(
    BookDownloadCancellation token,
    Future<T> Function() work,
  ) => runZoned(work, zoneValues: {_key: token});
}
