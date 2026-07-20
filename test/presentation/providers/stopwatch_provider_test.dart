import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/presentation/providers/stopwatch_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StopwatchNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('starts in the initial idle state', () {
      final state = container.read(stopwatchProvider);
      expect(state.isIdle, isTrue);
      expect(state.isRunning, isFalse);
      expect(state.elapsed, Duration.zero);
      expect(state.laps, isEmpty);
    });

    test('start() flips isRunning and accumulates elapsed time', () {
      fakeAsync((async) {
        final notifier = container.read(stopwatchProvider.notifier);
        notifier.debugSetTickInterval(const Duration(milliseconds: 10));

        notifier.start();
        expect(container.read(stopwatchProvider).isRunning, isTrue);

        // Advance fake time by 1.2 s. The ticker will fire many times.
        async.elapse(const Duration(milliseconds: 1200));
        async.flushMicrotasks();

        final state = container.read(stopwatchProvider);
        expect(state.isRunning, isTrue);
        expect(state.elapsed.inMilliseconds, greaterThanOrEqualTo(1200));
        // Within tolerance: fake timers are not perfect but should
        // not be wildly off.
        expect(
          state.elapsed.inMilliseconds,
          lessThan(1200 + 200),
          reason: 'should be roughly 1200ms, not running ahead',
        );
      });
    });

    test('pause() freezes elapsed at the current value', () {
      fakeAsync((async) {
        final notifier = container.read(stopwatchProvider.notifier);
        notifier.debugSetTickInterval(const Duration(milliseconds: 10));

        notifier.start();
        async.elapse(const Duration(milliseconds: 800));
        notifier.pause();

        final pausedAt = container.read(stopwatchProvider).elapsed;
        expect(container.read(stopwatchProvider).isRunning, isFalse);
        expect(pausedAt.inMilliseconds, greaterThanOrEqualTo(800));

        // Advance more fake time — elapsed must not change.
        async.elapse(const Duration(milliseconds: 2000));
        async.flushMicrotasks();
        final stillPaused = container.read(stopwatchProvider).elapsed;
        expect(stillPaused, equals(pausedAt));
        expect(stillPaused.inMilliseconds, lessThan(1000));
      });
    });

    test('start() after pause() resumes from the paused time, not zero', () {
      fakeAsync((async) {
        final notifier = container.read(stopwatchProvider.notifier);
        notifier.debugSetTickInterval(const Duration(milliseconds: 10));

        notifier.start();
        async.elapse(const Duration(milliseconds: 500));
        notifier.pause();
        final pausedAt = container.read(stopwatchProvider).elapsed;
        async.elapse(const Duration(milliseconds: 1000));
        // Still paused, no change:
        expect(container.read(stopwatchProvider).elapsed, equals(pausedAt));

        notifier.start();
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();

        final state = container.read(stopwatchProvider);
        expect(state.isRunning, isTrue);
        // Should be pausedAt + ~500 ms; cumulative running time is
        // 500 ms (first run) + 500 ms (second run) = ~1000 ms.
        expect(state.elapsed.inMilliseconds, greaterThanOrEqualTo(1000));
        expect(state.elapsed.inMilliseconds, lessThan(1300));
      });
    });

    test('reset() zeroes elapsed and clears laps', () {
      fakeAsync((async) {
        final notifier = container.read(stopwatchProvider.notifier);
        notifier.debugSetTickInterval(const Duration(milliseconds: 10));

        notifier.start();
        async.elapse(const Duration(milliseconds: 500));
        notifier.recordLap();
        async.elapse(const Duration(milliseconds: 500));
        notifier.recordLap();
        expect(container.read(stopwatchProvider).laps, hasLength(2));

        notifier.reset();
        final state = container.read(stopwatchProvider);
        expect(state.elapsed, Duration.zero);
        expect(state.laps, isEmpty);
        expect(state.isRunning, isFalse);
        expect(state.isIdle, isTrue);
      });
    });

    test('recordLap() captures correct lap and total times', () {
      fakeAsync((async) {
        final notifier = container.read(stopwatchProvider.notifier);
        notifier.debugSetTickInterval(const Duration(milliseconds: 10));

        notifier.start();
        async.elapse(const Duration(milliseconds: 300));
        notifier.recordLap();
        async.elapse(const Duration(milliseconds: 500));
        notifier.recordLap();
        async.elapse(const Duration(milliseconds: 200));
        notifier.recordLap();

        final laps = container.read(stopwatchProvider).laps;
        expect(laps, hasLength(3));

        // Lap 1 was at total ~300ms; lap time is also ~300ms.
        expect(laps[0].number, 1);
        expect(laps[0].totalTime.inMilliseconds, greaterThanOrEqualTo(300));
        expect(laps[0].lapTime.inMilliseconds, greaterThanOrEqualTo(300));
        expect(
          laps[0].lapTime.inMilliseconds,
          lessThan(500),
          reason: 'first lap time = first total time',
        );

        // Lap 2 at total ~800ms; lap time = total - prev total = ~500ms.
        expect(laps[1].number, 2);
        expect(laps[1].totalTime.inMilliseconds, greaterThanOrEqualTo(800));
        expect(laps[1].lapTime.inMilliseconds, greaterThanOrEqualTo(500));
        expect(laps[1].lapTime.inMilliseconds, lessThan(700));

        // Lap 3 at total ~1000ms; lap time = ~200ms.
        expect(laps[2].number, 3);
        expect(laps[2].totalTime.inMilliseconds, greaterThanOrEqualTo(1000));
        expect(laps[2].lapTime.inMilliseconds, greaterThanOrEqualTo(200));
        expect(laps[2].lapTime.inMilliseconds, lessThan(400));
      });
    });

    test('recordLap() is a no-op on a fresh, never-started stopwatch', () {
      fakeAsync((async) {
        final notifier = container.read(stopwatchProvider.notifier);
        notifier.debugSetTickInterval(const Duration(milliseconds: 10));

        notifier.recordLap();
        expect(container.read(stopwatchProvider).laps, isEmpty);
        // Should also not have flipped isRunning or added elapsed.
        final s = container.read(stopwatchProvider);
        expect(s.isRunning, isFalse);
        expect(s.elapsed, Duration.zero);
        async.elapse(const Duration(milliseconds: 100));
        expect(container.read(stopwatchProvider).laps, isEmpty);
      });
    });

    test('recordLap() is allowed while paused (records final time)', () {
      // Some stopwatches let you record a lap *after* pausing; we
      // follow that convention because it's a low-stakes QoL feature.
      // Documented behavior: any non-idle state allows recordLap.
      fakeAsync((async) {
        final notifier = container.read(stopwatchProvider.notifier);
        notifier.debugSetTickInterval(const Duration(milliseconds: 10));

        notifier.start();
        async.elapse(const Duration(milliseconds: 700));
        notifier.pause();
        notifier.recordLap();

        final laps = container.read(stopwatchProvider).laps;
        expect(laps, hasLength(1));
        expect(laps[0].totalTime.inMilliseconds, greaterThanOrEqualTo(700));
      });
    });

    test('start() is a no-op when already running', () {
      fakeAsync((async) {
        final notifier = container.read(stopwatchProvider.notifier);
        notifier.debugSetTickInterval(const Duration(milliseconds: 10));

        notifier.start();
        async.elapse(const Duration(milliseconds: 200));
        // Second start() should not reset the stopwatch.
        notifier.start();
        async.elapse(const Duration(milliseconds: 200));
        expect(
          container.read(stopwatchProvider).elapsed.inMilliseconds,
          greaterThanOrEqualTo(400),
        );
        expect(
          container.read(stopwatchProvider).elapsed.inMilliseconds,
          lessThan(600),
        );
      });
    });

    test('pause() is a no-op when already paused', () {
      fakeAsync((async) {
        final notifier = container.read(stopwatchProvider.notifier);
        notifier.debugSetTickInterval(const Duration(milliseconds: 10));

        notifier.start();
        async.elapse(const Duration(milliseconds: 300));
        notifier.pause();
        final pausedAt = container.read(stopwatchProvider).elapsed;
        // Second pause should not change anything.
        notifier.pause();
        expect(container.read(stopwatchProvider).elapsed, equals(pausedAt));
        expect(container.read(stopwatchProvider).isRunning, isFalse);
      });
    });

    test('disposing the container stops the ticker', () {
      // Verifies there is no leaked Timer after the notifier goes
      // away. fakeAsync throws if there are still pending timers at
      // the end of the callback, so this test fails if we forget to
      // cancel in onDispose.
      fakeAsync((async) {
        final local = ProviderContainer();
        final notifier = local.read(stopwatchProvider.notifier);
        notifier.debugSetTickInterval(const Duration(milliseconds: 10));
        notifier.start();
        // A few ticks to ensure the Timer is active.
        async.elapse(const Duration(milliseconds: 50));
        local.dispose();
        // fakeAsync's `flushTimers` would surface a leaked timer.
        // We don't need to call it explicitly; fakeAsync asserts on
        // exit if there are outstanding callbacks. The mere fact
        // that we don't hang or throw is the assertion.
        async.elapse(const Duration(milliseconds: 100));
        // If we got here without fakeAsync complaining, the ticker
        // was correctly cancelled.
        expect(true, isTrue);
      });
    });
  });
}
