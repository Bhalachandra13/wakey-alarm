import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakey_alarm/domain/stopwatch.dart';

/// Provider for the in-memory stopwatch notifier. Pure Dart state, no
/// native side, no persistence (per requirements.md §5.3 — the
/// stopwatch is intentionally reset on app kill).
final stopwatchProvider = NotifierProvider<StopwatchNotifier, StopwatchState>(
  StopwatchNotifier.new,
);

/// Manages a single in-memory stopwatch.
///
/// Time tracking is based on [clock] (the `package:clock` injectable
/// clock) so the notifier can be exercised under `fakeAsync` in tests
/// without relying on real wall-clock time. Production code uses the
/// default `clock` (which delegates to the system clock and is
/// monotonic for `now()` time differences within a process).
///
/// A [Timer.periodic] fires every [tickInterval] (default 50 ms) while
/// the stopwatch is running; the notifier publishes the latest
/// `elapsed` value on each tick so the UI rebuilds smoothly. The tick
/// is purely a UI refresh mechanism — actual elapsed time is computed
/// from `clock.now()` deltas, never by counting ticks, so dropped or
/// coalesced ticks never affect accuracy.
///
/// The notifier is intentionally stateful via [Ref]: it is created
/// lazily by Riverpod on first read and torn down with the provider
/// container. Per requirements, the state is not persisted anywhere.
class StopwatchNotifier extends Notifier<StopwatchState> {
  /// Default tick cadence: 20 fps is plenty for a stopwatch display
  /// (50 ms ≈ 1/20 s of UI latency) and keeps wakeups minimal.
  static const Duration _defaultTickInterval = Duration(milliseconds: 50);

  /// Wall-clock time captured by [start]. Null when stopped.
  DateTime? _startedAt;

  /// Elapsed time accumulated across previous run intervals. When the
  /// stopwatch is paused, this is what shows in [state.elapsed].
  Duration _accumulated = Duration.zero;

  Timer? _ticker;
  Duration _tickInterval = _defaultTickInterval;

  /// Override the tick interval. Exposed for tests; production code
  /// should use the default cadence.
  @visibleForTesting
  void debugSetTickInterval(Duration interval) {
    _tickInterval = interval;
    if (_ticker != null) {
      _restartTicker();
    }
  }

  @override
  StopwatchState build() {
    ref.onDispose(_disposeTicker);
    return const StopwatchState.initial();
  }

  /// The currently-measured elapsed time, including the active run
  /// interval if any. Reads [clock.now()] for the active interval
  /// when running; returns the cached [state.elapsed] when paused
  /// (so the display freezes exactly on pause).
  Duration _currentElapsed() {
    final startedAt = _startedAt;
    if (startedAt == null) return _accumulated;
    return _accumulated + clock.now().difference(startedAt);
  }

  /// Start the stopwatch from idle or resumed-after-pause. No-op if
  /// already running.
  void start() {
    if (state.isRunning) return;
    _startedAt = clock.now();
    _restartTicker();
    state = state.copyWith(isRunning: true, elapsed: _currentElapsed());
  }

  /// Pause the stopwatch, preserving the elapsed value. No-op if
  /// already paused/idle.
  void pause() {
    if (!state.isRunning) return;
    final startedAt = _startedAt;
    if (startedAt != null) {
      _accumulated += clock.now().difference(startedAt);
    }
    _startedAt = null;
    _cancelTicker();
    // Publish a final synchronous elapsed so the UI shows the exact
    // pause time (the ticker may have last fired up to 50 ms ago).
    state = state.copyWith(elapsed: _accumulated, isRunning: false);
  }

  /// Reset to zero and clear all laps. Does not require the stopwatch
  /// to be paused — works whether running or paused.
  void reset() {
    _startedAt = null;
    _accumulated = Duration.zero;
    _cancelTicker();
    state = const StopwatchState.initial();
  }

  /// Capture a lap at the current elapsed time. No-op if the
  /// stopwatch has never been started (recording a lap on a fresh,
  /// never-started stopwatch would be a confusing UX — it would just
  /// show "Lap 1: 00:00.00").
  void recordLap() {
    if (state.isIdle) return;
    final current = _currentElapsed();
    final previousTotal = state.laps.isEmpty
        ? Duration.zero
        : state.laps.last.totalTime;
    final lapTime = current - previousTotal;
    final lap = StopwatchLap(
      number: state.laps.length + 1,
      lapTime: lapTime,
      totalTime: current,
    );
    state = state.copyWith(elapsed: current, laps: [...state.laps, lap]);
  }

  void _restartTicker() {
    _cancelTicker();
    _ticker = Timer.periodic(_tickInterval, (_) {
      if (!state.isRunning) return;
      final current = _currentElapsed();
      // Skip the rebuild if the value hasn't actually changed (e.g.
      // two ticks with sub-tick elapsed) — keeps the UI quiet when
      // the stopwatch is at 0.
      if (current == state.elapsed) return;
      state = state.copyWith(elapsed: current);
    });
  }

  void _cancelTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _disposeTicker() {
    _cancelTicker();
  }
}
