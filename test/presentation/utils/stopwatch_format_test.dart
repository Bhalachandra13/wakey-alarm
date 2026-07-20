import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/presentation/utils/stopwatch_format.dart';

void main() {
  group('formatStopwatch', () {
    test('zero is 00:00.00', () {
      expect(formatStopwatch(Duration.zero), '00:00.00');
    });

    test('formats seconds and hundredths', () {
      expect(
        formatStopwatch(const Duration(seconds: 1, milliseconds: 234)),
        '00:01.23',
      );
    });

    test('formats minutes, seconds, and hundredths', () {
      expect(
        formatStopwatch(
          const Duration(minutes: 2, seconds: 3, milliseconds: 456),
        ),
        '02:03.45',
      );
    });

    test('zero-pads hundredths below 10', () {
      expect(formatStopwatch(const Duration(milliseconds: 1050)), '00:01.05');
    });

    test('caps at MM:SS.hh even past an hour', () {
      // 1h 5m 4.56s = 3904.56s = 390456 hundredths; minutes = 65.
      expect(
        formatStopwatch(
          const Duration(hours: 1, minutes: 5, seconds: 4, milliseconds: 560),
        ),
        '65:04.56',
      );
    });

    test('handles negative durations by clamping to zero', () {
      expect(formatStopwatch(const Duration(seconds: -5)), '00:00.00');
    });
  });

  group('formatStopwatchWithHours', () {
    test('zero is 0:00:00.00', () {
      expect(formatStopwatchWithHours(Duration.zero), '0:00:00.00');
    });

    test('formats sub-hour durations with a leading 0 hours', () {
      expect(
        formatStopwatchWithHours(
          const Duration(minutes: 2, seconds: 3, milliseconds: 456),
        ),
        '0:02:03.45',
      );
    });

    test('formats multi-hour durations with non-zero hours', () {
      expect(
        formatStopwatchWithHours(
          const Duration(hours: 1, minutes: 5, seconds: 4, milliseconds: 560),
        ),
        '1:05:04.56',
      );
    });
  });
}
