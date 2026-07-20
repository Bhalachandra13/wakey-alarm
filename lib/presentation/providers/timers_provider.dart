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
    ref.listen<AsyncValue<AlarmEvent>>(alarmEventsProvider, (prev, next) {
      final event = next.value;
      if (event == null) return;
      // Only act on timer-fired events; let the alarms notifier
      // handle alarm-fired events.
      if (event.triggerType != 'timer') return;
      switch (event.type) {
        case AlarmEventType.fired:
          // RingingActivity already shows the timer UI. Nothing to
          // do here for the DB — the next dismiss/snooze event
          // will update the row.
          break;
        case AlarmEventType.snoozed:
          // The native side re-scheduled a follow-up fire. The DB
          // row stays as RUNNING; the next fired event will fire
          // when the snooze elapses. We don't update startedAt
          // because the DB is just a record of "we have an active
          // timer" — the live countdown is now driven by the
          // native schedule.
          ref.invalidateSelf();
        case AlarmEventType.dismissed:
          // The user dismissed; delete the DB row.
          _onTimerDismissed(event.alarmId);
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
  /// Returns the inserted DB id. The timer is immediately
  /// RUNNING — there is no "draft" state.
  Future<int> create({
    required String label,
    required int durationSeconds,
    String soundUri = '',
    bool vibrate = true,
    int snoozeDurationMin = 5,
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
      // Best-effort cleanup: delete the DB row since the native
      // schedule did not take. Otherwise the user would see a
      // running timer that never fires — the worst kind of
      // silent-fail.
      await dao.delete(id);
    }
    _startTickerFor(id);
    ref.invalidateSelf();
    return id;
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
  Future<void> resume(int id) async {
    final dao = ref.read(timerDaoProvider);
    final current = await dao.read(id);
    if (current == null || current.state != TimerState.paused) return;
    final remaining = current.remainingSeconds;
    if (remaining <= 0) {
      // Shouldn't happen for a paused timer (we never persist
      // remaining=0 for a non-COMPLETED state), but defensive.
      await dao.delete(id);
      ref.invalidateSelf();
      return;
    }
    final now = clock.now();
    final fireAt = now.add(Duration(seconds: remaining));
    final resumed = current.copyWith(
      state: TimerState.running,
      startedAt: now.toIso8601String(),
    );
    await dao.update(resumed);
    final bridge = ref.read(alarmBridgeProvider);
    await bridge.scheduleTimer({
      'alarmId': id,
      'triggerAtMillis': fireAt.millisecondsSinceEpoch,
      'label': resumed.label,
      'snoozeDurationMin': resumed.snoozeDurationMinOrDefault,
    });
    _startTickerFor(id);
    ref.invalidateSelf();
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
    final dao = ref.read(timerDaoProvider);
    final record = await dao.read(id);
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
    final newRemaining = (record.durationSeconds - elapsed).clamp(0, 1 << 30);
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

/// Helper extension to give timers a sane snooze default. The AlarmData
/// pipeline requires an int; we hard-code 5 minutes as a sensible
/// default for timer snoozes (shorter than typical alarm snoozes
/// because timer fires are usually more intentional).
extension on TimerRecord {
  int get snoozeDurationMinOrDefault => 5;
}
