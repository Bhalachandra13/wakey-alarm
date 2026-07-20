import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/domain/stopwatch.dart';

void main() {
  group('StopwatchState', () {
    test('initial state is idle, zero elapsed, no laps', () {
      const s = StopwatchState.initial();
      expect(s.elapsed, Duration.zero);
      expect(s.isRunning, isFalse);
      expect(s.laps, isEmpty);
      expect(s.isIdle, isTrue);
    });

    test('isIdle is false when running with zero elapsed', () {
      const s = StopwatchState(
        elapsed: Duration.zero,
        isRunning: true,
        laps: <StopwatchLap>[],
      );
      expect(s.isIdle, isFalse);
    });

    test('isIdle is false when paused with non-zero elapsed', () {
      const s = StopwatchState(
        elapsed: Duration(seconds: 5),
        isRunning: false,
        laps: <StopwatchLap>[],
      );
      expect(s.isIdle, isFalse);
    });

    test('copyWith updates only the named fields', () {
      const original = StopwatchState(
        elapsed: Duration(seconds: 10),
        isRunning: true,
        laps: <StopwatchLap>[
          StopwatchLap(
            number: 1,
            lapTime: Duration(seconds: 10),
            totalTime: Duration(seconds: 10),
          ),
        ],
      );
      final updated = original.copyWith(isRunning: false);
      expect(updated.isRunning, isFalse);
      expect(updated.elapsed, original.elapsed);
      expect(updated.laps, original.laps);
    });

    test('equality is value-based', () {
      const a = StopwatchState(
        elapsed: Duration(seconds: 1),
        isRunning: false,
        laps: <StopwatchLap>[],
      );
      const b = StopwatchState(
        elapsed: Duration(seconds: 1),
        isRunning: false,
        laps: <StopwatchLap>[],
      );
      const c = StopwatchState(
        elapsed: Duration(seconds: 2),
        isRunning: false,
        laps: <StopwatchLap>[],
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('StopwatchLap', () {
    test('copyWith updates only the named fields', () {
      const lap = StopwatchLap(
        number: 1,
        lapTime: Duration(seconds: 5),
        totalTime: Duration(seconds: 5),
      );
      final updated = lap.copyWith(lapTime: Duration(seconds: 7));
      expect(updated.lapTime, Duration(seconds: 7));
      expect(updated.totalTime, Duration(seconds: 5));
      expect(updated.number, 1);
    });

    test('equality is value-based', () {
      const a = StopwatchLap(
        number: 1,
        lapTime: Duration(seconds: 5),
        totalTime: Duration(seconds: 10),
      );
      const b = StopwatchLap(
        number: 1,
        lapTime: Duration(seconds: 5),
        totalTime: Duration(seconds: 10),
      );
      const c = StopwatchLap(
        number: 2,
        lapTime: Duration(seconds: 5),
        totalTime: Duration(seconds: 10),
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
