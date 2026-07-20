import 'package:flutter/foundation.dart';

/// A single lap record captured during a stopwatch run.
///
/// [number] is 1-indexed (the first lap is "Lap 1", not "Lap 0").
/// [lapTime] is the time elapsed *since the previous lap* (or since
/// start for the first lap). [totalTime] is the cumulative elapsed
/// time of the stopwatch at the moment the lap was recorded, so the
/// UI can show both "00:01:23" (lap) and "00:05:42" (total) without
/// recomputing either.
@immutable
class StopwatchLap {
  const StopwatchLap({
    required this.number,
    required this.lapTime,
    required this.totalTime,
  });

  final int number;
  final Duration lapTime;
  final Duration totalTime;

  StopwatchLap copyWith({int? number, Duration? lapTime, Duration? totalTime}) {
    return StopwatchLap(
      number: number ?? this.number,
      lapTime: lapTime ?? this.lapTime,
      totalTime: totalTime ?? this.totalTime,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StopwatchLap &&
          runtimeType == other.runtimeType &&
          number == other.number &&
          lapTime == other.lapTime &&
          totalTime == other.totalTime;

  @override
  int get hashCode => Object.hash(number, lapTime, totalTime);

  @override
  String toString() => 'StopwatchLap($number: lap=$lapTime total=$totalTime)';
}

/// Immutable snapshot of the stopwatch's state at a single point in
/// time. The notifier publishes a new instance on every tick so widgets
/// listening via Riverpod rebuild automatically.
///
/// [elapsed] is the cumulative measured time, *not* wall-clock time.
/// It is the sum of all *running* intervals — paused time is not
/// counted. This is what users expect from a stopwatch and matches
/// the behavior of `dart:core` `Stopwatch`.
@immutable
class StopwatchState {
  const StopwatchState({
    required this.elapsed,
    required this.isRunning,
    required this.laps,
  });

  const StopwatchState.initial()
    : elapsed = Duration.zero,
      isRunning = false,
      laps = const <StopwatchLap>[];

  /// Total measured time (excludes paused time).
  final Duration elapsed;

  /// True while the underlying `Stopwatch` is running. False while
  /// idle, paused, or after a reset.
  final bool isRunning;

  /// Laps captured so far, in order of recording. Lap 1 is the first
  /// element; the most recent lap is the last element. Empty when no
  /// laps have been recorded.
  final List<StopwatchLap> laps;

  /// True if the stopwatch has never been started, or was reset.
  bool get isIdle => !isRunning && elapsed == Duration.zero;

  StopwatchState copyWith({
    Duration? elapsed,
    bool? isRunning,
    List<StopwatchLap>? laps,
  }) {
    return StopwatchState(
      elapsed: elapsed ?? this.elapsed,
      isRunning: isRunning ?? this.isRunning,
      laps: laps ?? this.laps,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StopwatchState &&
          runtimeType == other.runtimeType &&
          elapsed == other.elapsed &&
          isRunning == other.isRunning &&
          listEquals(laps, other.laps);

  @override
  int get hashCode => Object.hash(elapsed, isRunning, Object.hashAll(laps));

  @override
  String toString() =>
      'StopwatchState(elapsed=$elapsed, isRunning=$isRunning, laps=${laps.length})';
}
