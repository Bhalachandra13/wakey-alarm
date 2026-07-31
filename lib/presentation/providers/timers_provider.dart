import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakey_alarm/data/timer_dao.dart';
import 'package:wakey_alarm/domain/timer_record.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';

/// DAO provider for the timers table.
final timerDaoProvider = Provider<TimerDao>((ref) {
  return TimerDao(ref.watch(databaseProvider));
});

/// Owns the list of active [TimerRecord]s and brokers scheduling to
/// the native AlarmManager.
///
/// The notifier holds an additional **live remaining-time** field
/// ([liveRemainingSeconds]) that is computed from [clock] on each
/// tick, not from the DB. The DB is only the source of truth for the
/// *next* time the user opens the app — the live UI is fed by the
/// ticker so it updates smoothly without hitting sqflite.
class TimersNotifier extends AsyncNotifier<List<TimerRecord>> {
  Timer? _ticker;
  int? _lastTickedTimerId;
  DateTime? _lastTickedAt;

  /// Latest computed remaining seconds for the currently-active
  /// timer, or null if no timer is active. Mirrors the DB value for
  /// pause; for running it counts down each tick.
  int? _liveRemainingForActive;

  @override
  Future<List<TimerRecord>> build() async {
    // The alarmEventsProvider is the source of truth for the native
    // ringing UI; we mirror its outcomes into the timers list, same
    // way AlarmsNotifier does. See the comment there for the
    // "native is source of truth" rationale.
    ref.listen<AsyncValue<AlarmEvent>>(alarmEventsProvider, (prev, next) async {
      final event = next.value;
      if (event == null) return;
      // `fired` events include a triggerType, but `snoozed` and
      // `dismissed` events from RingingActivity do not (the alarm
      // has finished ringing, so the trigger type is no longer
      // relevant). We therefore route fired events only when they
      // are explicitly for a timer. For snoozed/dismissed events
      // we honor an explicit non-timer triggerType if present
      // (defensive), otherwise we look the alarmId up in the timers
      // table and only act when there is a matching timer row.
      final isTimerFire =
          event.type == AlarmEventType.fired && event.triggerType == 'timer';
      if (!isTimerFire) {
        if (event.triggerType != null && event.triggerType != 'timer') {
          return;
        }
        final dao = ref.read(timerDaoProvider);
        final timer = await dao.read(event.alarmId);
        if (timer == null) return;
      }
      switch (event.type) {
        case AlarmEventType.fired:
          // RingingActivity already shows the timer UI. Stop the
          // live ticker so the UI doesn't keep counting past 0
          // while the ringing UI is up. The native side is now the
          // source of truth for when the next fire will be (snooze
          // or natural completion). The next dismiss/snooze event
          // will update or remove the row.
          if (_lastTickedTimerId == event.alarmId) _stopTicker();
          ref.invalidateSelf();
        case AlarmEventType.snoozed:
          // The native side re-scheduled a follow-up fire. The DB
          // row stays as RUNNING; the next fired event will fire
          // when the snooze elapses. We don't update startedAt
          // because the DB is just a record of "we have an active
          // timer" — the live countdown is now driven by the
          // native schedule.
          if (_lastTickedTimerId == event.alarmId) _stopTicker();
          ref.invalidateSelf();
        case AlarmEventType.dismissed:
          // The user dismissed; delete the DB row.
          await _onTimerDismissed(event.alarmId);
      }
    });
    ref.onDispose(_stopTicker);
    return _loadActive();
  }

  Future<List<TimerRecord>> _loadActive() async {
    final dao = ref.read(timerDaoProvider);
    return dao.getActive();
  }

  /// Create a timer and schedule it with the native AlarmManager.
  ///
  /// Returns `true` if the timer was inserted **and** the native
  /// schedule succeeded. Returns `false` if the native side refused
  /// the schedule (typically because `SCHEDULE_EXACT_ALARM` is not
  /// granted on Android 12+). In the failure case the just-inserted
  /// timer row is rolled back, so the caller can surface the error
  /// and let the user retry after granting the permission.
  Future<bool> create({
    required String label,
    required int durationSeconds,
    String soundUri = '',
    bool vibrate = true,
    int snoozeDurationMin = TimerRecord.defaultSnoozeDurationMin,
    int? maxSnoozeCount,
  }) async {
    if (durationSeconds <= 0) {
      throw ArgumentError('durationSeconds must be > 0');
    }
    final now = clock.now();
    final fireAt = now.add(Duration(seconds: durationSeconds));
    final record = TimerRecord(
      label: label.isEmpty ? 'Timer' : label,
      durationSeconds: durationSeconds,
      remainingSeconds: durationSeconds,
      state: TimerState.running,
      startedAt: now.toIso8601String(),
      snoozeDurationMin: snoozeDurationMin,
    );
    final dao = ref.read(timerDaoProvider);
    final id = await dao.insert(record);
    final bridge = ref.read(alarmBridgeProvider);
    final scheduled = await bridge.scheduleTimer({
      'alarmId': id,
      'triggerAtMillis': fireAt.millisecondsSinceEpoch,
      'label': record.label,
      'soundUri': soundUri,
      'vibrate': vibrate,
      'snoozeDurationMin': snoozeDurationMin,
      'maxSnoozeCount': maxSnoozeCount ?? -1,
    });
    if (!scheduled) {
      // Roll back the DB row so the user isn't left with a timer
      // that can never fire. The UI will show an error pointing at
      // the exact-alarm permission banner.
      await dao.delete(id);
      ref.invalidateSelf();
      return false;
    }
    _startTickerFor(id);
    ref.invalidateSelf();
    return true;
  }

  /// Cancel a timer. Removes the row and the native schedule.
  Future<void> cancel(int id) async {
    final dao = ref.read(timerDaoProvider);
    final bridge = ref.read(alarmBridgeProvider);
    await bridge.cancelAlarm(id);
    await dao.delete(id);
    if (_lastTickedTimerId == id) _stopTicker();
    ref.invalidateSelf();
  }

  /// Pause a running timer. The remaining time is frozen; the native
  /// schedule is cancelled.
  Future<void> pause(int id) async {
    final dao = ref.read(timerDaoProvider);
    final current = await dao.read(id);
    if (current == null || current.state != TimerState.running) return;
    final bridge = ref.read(alarmBridgeProvider);
    await bridge.cancelAlarm(id);
    final frozen = current.copyWith(
      state: TimerState.paused,
      remainingSeconds: _liveRemainingForActive ?? current.remainingSeconds,
    );
    await dao.update(frozen);
    if (_lastTickedTimerId == id) _stopTicker();
    ref.invalidateSelf();
  }

  /// Resume a paused timer. Schedules a new fire at
  /// `now + remainingSeconds` and flips state back to RUNNING.
  ///
  /// Returns `true` if the timer is running again and the native
  /// schedule succeeded. Returns `false` if the native schedule
  /// failed (e.g. `SCHEDULE_EXACT_ALARM` was revoked); the timer
  /// stays paused in that case so the user can retry later.
  Future<bool> resume(int id) async {
    final dao = ref.read(timerDaoProvider);
    final current = await dao.read(id);
    if (current == null || current.state != TimerState.paused) return true;
    final remaining = current.remainingSeconds;
    if (remaining <= 0) {
      // Shouldn't happen for a paused timer (we never persist
      // remaining=0 for a non-COMPLETED state), but defensive.
      await dao.delete(id);
      ref.invalidateSelf();
      return true;
    }
    final now = clock.now();
    final fireAt = now.add(Duration(seconds: remaining));
    final bridge = ref.read(alarmBridgeProvider);
    final scheduled = await bridge.scheduleTimer({
      'alarmId': id,
      'triggerAtMillis': fireAt.millisecondsSinceEpoch,
      'label': current.label,
      'snoozeDurationMin': current.snoozeDurationMin,
    });
    if (!scheduled) {
      // Leave the timer paused. The UI will surface the permission
      // error; the user can retry after granting it.
      return false;
    }
    final resumed = current.copyWith(
      state: TimerState.running,
      startedAt: now.toIso8601String(),
    );
    await dao.update(resumed);
    _startTickerFor(id);
    ref.invalidateSelf();
    return true;
  }

  /// The live remaining-seconds for the currently-ticking timer.
  /// `null` when no timer is active.
  int? get liveRemainingForActive => _liveRemainingForActive;

  // -------------------------------------------------------------------------
  // Native mirror
  // -------------------------------------------------------------------------

  Future<void> _onTimerDismissed(int timerId) async {
    final dao = ref.read(timerDaoProvider);
    await dao.delete(timerId);
    if (_lastTickedTimerId == timerId) _stopTicker();
    ref.invalidateSelf();
  }

  // -------------------------------------------------------------------------
  // Live ticker
  // -------------------------------------------------------------------------

  void _startTickerFor(int id) {
    _stopTicker();
    _lastTickedTimerId = id;
    _lastTickedAt = clock.now();
    _liveRemainingForActive = null;
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      await _tick();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _lastTickedTimerId = null;
    _lastTickedAt = null;
    _liveRemainingForActive = null;
  }

  Future<void> _tick() async {
    final id = _lastTickedTimerId;
    if (id == null) return;
    // The ticker is a real `Timer.periodic` and may fire after the
    // notifier has been disposed (e.g. the test container is torn
    // down, or the app process is shutting down). Guard against
    // using a disposed `ref` to avoid an exception that would
    // otherwise surface as a teardown error or a crash.
    if (!ref.mounted) {
      _stopTicker();
      return;
    }
    final dao = ref.read(timerDaoProvider);
    final record = await dao.read(id);
    // The `await` above is an async gap; the notifier may have been
    // disposed while we were reading from the DB. Re-check.
    if (!ref.mounted) {
      _stopTicker();
      return;
    }
    if (record == null || record.state != TimerState.running) {
      _stopTicker();
      ref.invalidateSelf();
      return;
    }
    final now = clock.now();
    final startedAt = record.startedAt;
    if (startedAt == null) {
      _liveRemainingForActive = record.remainingSeconds;
      ref.invalidateSelf();
      return;
    }
    final start = DateTime.parse(startedAt);
    final elapsed = now.difference(start).inSeconds;
    // Use the *remaining* time at the start of the current run as the
    // base, not the original full `durationSeconds`. This matters
    // after a pause/resume cycle: the DB still has the original
    // `durationSeconds`, but the timer should keep counting down from
    // the frozen `remainingSeconds` value, not reset to the full
    // duration. The upper bound is also `remainingSeconds` so that
    // negative elapsed (e.g. clock skew right after resume) cannot
    // bump the remaining above the value it had at resume.
    final newRemaining =
        (record.remainingSeconds - elapsed).clamp(0, record.remainingSeconds);
    _liveRemainingForActive = newRemaining;
    // Persist at most once a second to keep DB IO light.
    if (_lastTickedAt == null ||
        now.difference(_lastTickedAt!) >= const Duration(seconds: 1)) {
      _lastTickedAt = now;
      await dao.updateRemaining(id, newRemaining);
    }
    // Notify listeners so the UI can re-render.
    ref.invalidateSelf();
  }
}

/// Convenience provider exposing the live remaining-seconds to widgets.
final liveTimerRemainingProvider = Provider<int?>((ref) {
  // Watch the notifier itself so we get notified on each tick.
  ref.watch(timersProvider);
  return ref.read(timersProvider.notifier).liveRemainingForActive;
});

/// Riverpod entry point for the timers list.
final timersProvider = AsyncNotifierProvider<TimersNotifier, List<TimerRecord>>(
  TimersNotifier.new,
);
