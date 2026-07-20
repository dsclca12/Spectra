import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

import 'package:spectra/core/concurrency.dart';

void main() {
  group('Semaphore', () {
    test('allows up to max concurrency', () async {
      final sem = Semaphore(2);
      final m1 = sem.acquire();
      final m2 = sem.acquire();
      final m3 = sem.acquire();

      // First two should resolve immediately
      await expectLater(m1, completes);
      await expectLater(m2, completes);

      // Third should not be resolved yet
      expect(m3, isA<Future<void Function()>>());

      // Release one, third should resolve
      final release1 = await m1;
      release1();
      await expectLater(m3, completes);
    });

    test('release decreases count', () async {
      final sem = Semaphore(1);
      final release = await sem.acquire();
      release();
      // Should be able to acquire again immediately
      await expectLater(sem.acquire(), completes);
    });

    test('can be acquired sequentially', () async {
      final sem = Semaphore(1);
      final release1 = await sem.acquire();
      final future2 = sem.acquire();
      release1();
      final release2 = await future2;
      release2();
      // After both releases, should acquire immediately
      await expectLater(sem.acquire(), completes);
    });
  });
}
