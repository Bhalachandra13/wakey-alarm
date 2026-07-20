/// Formats a [Duration] as `MM:SS.hh` for stopwatch display, where
/// `hh` is hundredths of a second.
///
/// * Hours wrap: a 1 h 23 m 4.56 s duration is rendered as
///   `83:04.56` rather than `1:23:04.56` to keep the display compact
///   (matches stock-clock stopwatch behavior on Android). Callers
///   that need an hours field should use [formatStopwatchWithHours].
/// * Milliseconds < 10 are zero-padded so the display shows
///   `01.05` rather than `01.5` (consistent with stock Android/iOS
///   stopwatches).
String formatStopwatch(Duration d) {
  final clamped = d.isNegative ? Duration.zero : d;
  final totalHundredths = clamped.inMicroseconds ~/ 10_000;
  final hundredths = totalHundredths % 100;
  final totalSeconds = totalHundredths ~/ 100;
  final seconds = totalSeconds % 60;
  final minutes = totalSeconds ~/ 60;
  return '${_two(minutes)}:${_two(seconds)}.${_two(hundredths)}';
}

/// Like [formatStopwatch] but with an explicit hours field, e.g.
/// `1:23:04.56` (used by the lap list when total time exceeds an
/// hour).
String formatStopwatchWithHours(Duration d) {
  final clamped = d.isNegative ? Duration.zero : d;
  final totalHundredths = clamped.inMicroseconds ~/ 10_000;
  final hundredths = totalHundredths % 100;
  final totalSeconds = totalHundredths ~/ 100;
  final seconds = totalSeconds % 60;
  final totalMinutes = totalSeconds ~/ 60;
  final minutes = totalMinutes % 60;
  final hours = totalMinutes ~/ 60;
  return '$hours:${_two(minutes)}:${_two(seconds)}.${_two(hundredths)}';
}

String _two(int n) => n.toString().padLeft(2, '0');
