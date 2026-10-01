import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:xxread/book_sources/services/book_download_cancellation.dart';
import 'package:xxread/book_sources/services/source_task_pool.dart';

void main() {
  test('185 tasks respect the global and same-host budgets', () async {
    final pool = SourceTaskPool();
    var active = 0;
    var peak = 0;
    final hosts = <String, int>{};
    final completed = await Future.wait(
      List.generate(185, (i) {
        final host = 'host${i % 9}';
        return pool.run(host, () async {
          active++;
          if (active > peak) peak = active;
          hosts[host] = (hosts[host] ?? 0) + 1;
          expect(active, lessThanOrEqualTo(12));
          expect(hosts[host], lessThanOrEqualTo(2));
          await Future<void>.delayed(const Duration(milliseconds: 1));
          active--;
          hosts[host] = hosts[host]! - 1;
          return i;
        });
      }),
    );
    expect(completed.toSet(), hasLength(185));
    expect(peak, 12);
  });

  test(
    'cancelled queued tasks never start; later jobs keep their own context',
    () async {
      final pool = SourceTaskPool(limit: 1);
      final gate = Completer<void>();
      final first = pool.run('a', () => gate.future);
      final cancelled = BookDownloadCancellation();
      final next = BookDownloadCancellation();
      var started = false;
      final queued = pool.run('b', () async {
        started = true;
      }, cancellation: cancelled);
      final cancelledCheck = expectLater(
        queued,
        throwsA(isA<BookDownloadCancelledException>()),
      );
      final later = SourceTaskContext.run(
        next,
        () => pool.run('c', () async {
          expect(SourceTaskContext.cancellation, same(next));
          return 42;
        }),
      );
      cancelled.cancel();
      gate.complete();
      await first;
      await cancelledCheck;
      expect(started, isFalse);
      expect(await later, 42);
    },
  );

  test('one failed source does not hold a worker slot', () async {
    final pool = SourceTaskPool(limit: 1);
    final failed = pool.run('a', () async => throw StateError('failed'));
    final failureCheck = expectLater(failed, throwsStateError);
    final successful = pool.run('a', () async => 'ok');
    await failureCheck;
    expect(await successful, 'ok');
  });
}
