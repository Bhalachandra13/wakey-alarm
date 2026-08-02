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
/// The notifier holds an additional **live remaining-time** map
/// ([_liveRemainingById]) keyed by timer id. The values are
/// computed from [clock] on each tick, not from the DB. While a
/// timer is RUNNING its DB row is *never* rewritten — the row's
/// `remaining_seconds` stays at the value captured when the current
/// run started (at create/resume), so the live countdown is a pure
/// function of the row: `remaining_seconds - (now - started_at)`.
/// That makes cold starts correct for free: [build] re-seeds the
/// in-memory base from the same two columns and the countdown
/// resumes from the right value with no DB writes in between.
///
/// The tick publishes updates by bumping [timerTickProvider] — a
/// lightweight counter — instead of invalidating this provider.
/// Invalidating 5x/second used to re-query sqflite on every tick
/// and put the whole list through reload transitions; the counter
/// rebuilds only the widgets that show a countdown.
///
/// Multiple timers can be active at once, so the live map is keyed
/// by id rather than a single scalar; this lets every timer card
/// (and the detail screen) show a per-timer countdown that ticks
/// down second by second without each card running its own ticker.
class TimersNotifier extends AsyncNotifier<List<TimerRecord>> {
  Timer? _ticker;
  final Set<int> _trackedTimerIds = <int>{};

  /// Latest computed remaining seconds for each running timer,
  /// keyed by timer id. Paused timers are not in this map (their
  /// remaining is fixed and read straight from the DB). Removed
  /// when a timer is cancelled / dismissed / fired.
  final Map<int, int> _liveRemainingById = <int, int>{};

  /// Per-timer countdown base: the remaining seconds at the moment
  /// the current run started, and that start timestamp. Seeded at
  /// create / resume / cold-start load and kept in sync with the DB
  /// row's `remaining_seconds` + `started_at` (which are immutable
  /// while RUNNING). The tick computes
  /// `base - (now - runStartedAt)` — subtracting elapsed from the
  /// *persisted live value* is a bug (the base itself shrinks every
  /// second, so the countdown double-counts and races to zero).
  final Map<int, int> _baseRemainingById = <int, int>{};
  final Map<int, DateTime> _runStartedAtById = <int, DateTime>{};

  /// Ids whose countdown is currently owned by the native
  /// ringing/snooze flow (a `fired` or `snoozed` event arrived but
  /// the row still exists). [_reseedTracking] must not re-track
  /// these: the Dart countdown for them stops at 0 until the row
  /// is dismissed or deleted. Session-scoped on purpose — a cold
  /// start finds an empty set, so a timer that fired while the app
  /// was dead still gets seeded (and clamps to 0).
  final Set<int> _nativeOwnedTimerIds = <int>{};

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
          // live ticker for this timer so the UI doesn't keep
          // counting past 0 while the ringing UI is up. The
          // native side is now the source of truth for when the
          // next fire will be (snooze or natural completion).
          // The next dismiss/snooze event will update or remove
          // the row.
          await _deferToNative(event.alarmId);
        case AlarmEventType.snoozed:
          // The native side re-scheduled a follow-up fire. The DB
          // row stays as RUNNING; the next fired event will fire
          // when the snooze elapses. We don't update startedAt
          // because the DB is just a record of "we have an active
          // timer" — the live countdown is now driven by the
          // native schedule.
          await _deferToNative(event.alarmId);
        case AlarmEventType.dismissed:
          // The user dismissed; delete the DB row.
          await _onTimerDismissed(event.alarmId);
      }
    });
    ref.onDispose(_stopTicker);
    final timers = await _loadActive();
    _reseedTracking(timers);
    return timers;
  }

  /// Reconciles the live-tracking state with the freshly loaded
  /// list. This is what makes the countdown work after a cold
  /// start (or any rebuild): RUNNING rows loaded from the DB get
  /// their countdown base seeded and the ticker started, while ids
  /// that are no longer RUNNING (paused / cancelled / fired
  /// elsewhere) are dropped. Without this the ticker only ever ran
  /// for timers created or resumed in *this* session, so a timer
  /// that outlived the process showed a frozen persisted value.
  void _reseedTracking(List<TimerRecord> timers) {
    final runningIds = <int>{
      for (final t in timers)
        if (t.state == TimerState.running && t.id != null) t.id!,
    };
    for (final id in _trackedTimerIds.toList()) {
      if (!runningIds.contains(id)) _untrackTimer(id);
    }
    for (final t in timers) {
      if (t.state != TimerState.running || t.id == null) continue;
      // Owned by the native ringing/snooze flow — leave its
      // countdown stopped at the zeroed row value.
      if (_nativeOwnedTimerIds.contains(t.id)) continue;
      final startedAt = t.startedAt;
      if (startedAt == null) {
        // A running row without a start timestamp can't be
        // counted down (there is no elapsed baseline). Expose the
        // persisted value as a static live value so the UI still
        // shows it, but don't tick it.
        _liveRemainingById[t.id!] = t.remainingSeconds;
        continue;
      }
      _trackTimer(
        t.id!,
        baseRemaining: t.remainingSeconds,
        runStartedAt: DateTime.parse(startedAt),
      );
    }
    _ensureTickerRunning();
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
    _trackTimer(id, baseRemaining: durationSeconds, runStartedAt: now);
    _ensureTickerRunning();
    ref.invalidateSelf();
    return true;
  }

  /// Cancel a timer. Removes the row and the native schedule.
  Future<void> cancel(int id) async {
    final dao = ref.read(timerDaoProvider);
    final bridge = ref.read(alarmBridgeProvider);
    await bridge.cancelAlarm(id);
    await dao.delete(id);
    _nativeOwnedTimerIds.remove(id);
    _untrackTimer(id);
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
    // Prefer the ticker's latest value; if the first tick hasn't
    // fired yet (pause within ~200ms of start/resume), derive the
    // frozen value from the seeded base — same formula the tick
    // uses — and only then fall back to the raw persisted value.
    final live = _liveRemainingById[id];
    final base = _baseRemainingById[id];
    final runStartedAt = _runStartedAtById[id];
    final int frozenRemaining;
    if (live != null) {
      frozenRemaining = live;
    } else if (base != null && runStartedAt != null) {
      final elapsed = clock.now().difference(runStartedAt).inSeconds;
      frozenRemaining = (base - elapsed).clamp(0, base);
    } else {
      frozenRemaining = current.remainingSeconds;
    }
    final frozen = current.copyWith(
      state: TimerState.paused,
      remainingSeconds: frozenRemaining,
    );
    await dao.update(frozen);
    // Paused timers don't need a live count; freeze the value and
    // drop the id from the live map. If no other timers are
    // running the ticker can stop entirely.
    _untrackTimer(id);
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
    _trackTimer(id, baseRemaining: remaining, runStartedAt: now);
    _ensureTickerRunning();
    ref.invalidateSelf();
    return true;
  }

  /// The live remaining-seconds for the timer with [id], or `null`
  /// if no live value has been computed yet (the first tick hasn't
  /// fired) or if the timer is paused/cancelled. While a timer is
  /// RUNNING, the value decreases each tick.
  int? liveRemainingFor(int id) => _liveRemainingById[id];

  /// Convenience: live remaining for the first tracked (running)
  /// timer, or null. Kept for callers that only need *any* active
  /// timer's countdown (e.g. legacy single-timer UI elements).
  int? get liveRemainingForActive {
    if (_liveRemainingById.isEmpty) return null;
    return _liveRemainingById.values.first;
  }

  // -------------------------------------------------------------------------
  // Native mirror
  // -------------------------------------------------------------------------

  /// Hands a timer's countdown over to the native ringing/snooze
  /// flow: stops tracking it, pins its persisted remaining at 0
  /// (so the list/detail fallback shows 00:00 rather than the
  /// run's base value while the row lives on), and marks it so
  /// [_reseedTracking] doesn't resurrect the countdown on the
  /// rebuild that follows.
  Future<void> _deferToNative(int timerId) async {
    final wasTracked = _trackedTimerIds.contains(timerId);
    _untrackTimer(timerId);
    if (wasTracked) _nativeOwnedTimerIds.add(timerId);
    final dao = ref.read(timerDaoProvider);
    await dao.updateRemaining(timerId, 0);
    if (!ref.mounted) return;
    ref.invalidateSelf();
  }

  Future<void> _onTimerDismissed(int timerId) async {
    final dao = ref.read(timerDaoProvider);
    await dao.delete(timerId);
    _nativeOwnedTimerIds.remove(timerId);
    _untrackTimer(timerId);
    ref.invalidateSelf();
  }

  // -------------------------------------------------------------------------
  // Live ticker
  // -------------------------------------------------------------------------

  /// Adds [id] to the set of timers whose remaining time should be
  /// tracked in [_liveRemainingById], capturing the countdown base
  /// ([baseRemaining] seconds remaining as of [runStartedAt]). If
  /// the ticker is not yet running, [_ensureTickerRunning] starts
  /// it.
  void _trackTimer(
    int id, {
    required int baseRemaining,
    required DateTime runStartedAt,
  }) {
    _trackedTimerIds.add(id);
    _baseRemainingById[id] = baseRemaining;
    _runStartedAtById[id] = runStartedAt;
    // Explicit (re)starts always take the countdown back from the
    // native flow — ids can be recycled by sqlite after a delete.
    _nativeOwnedTimerIds.remove(id);
  }

  /// Removes [id] from the tracked set. Stops the ticker entirely
  /// if the tracked set becomes empty — there's nothing left to
  /// count down.
  void _untrackTimer(int id) {
    _trackedTimerIds.remove(id);
    _liveRemainingById.remove(id);
    _baseRemainingById.remove(id);
    _runStartedAtById.remove(id);
    if (_trackedTimerIds.isEmpty) _stopTicker();
  }

  /// Starts the periodic ticker if it isn't already running. The
  /// ticker is a single `Timer.periodic` that walks every tracked
  /// timer; this is cheaper than spinning up one timer per running
  /// timer and keeps the in-process state in one place.
  void _ensureTickerRunning() {
    if (_ticker != null) return;
    if (_trackedTimerIds.isEmpty) return;
    // 200 ms cadence: the displayed value has 1-second granularity,
    // so a sub-second tick just aligns the visible flip to the real
    // second boundary (max 200 ms late) without busy-waking.
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _tick();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    _liveRemainingById.clear();
    _trackedTimerIds.clear();
    _baseRemainingById.clear();
    _runStartedAtById.clear();
    // NB: `_nativeOwnedTimerIds` is deliberately NOT cleared here.
    // It is session state, not ticker state — it must survive the
    // ticker stopping (e.g. the last tracked timer firing while a
    // deferred one is still waiting for its dismiss event).
  }

  void _tick() {
    if (_trackedTimerIds.isEmpty) return;
    // The ticker is a real `Timer.periodic` and may fire after the
    // notifier has been disposed (e.g. the test container is torn
    // down, or the app process is shutting down). Guard against
    // using a disposed `ref` to avoid an exception that would
    // otherwise surface as a teardown error or a crash.
    if (!ref.mounted) {
      _stopTicker();
      return;
    }
    final now = clock.now();
    var changed = false;
    // Pure in-memory recompute — no DB reads here. The base maps
    // are seeded from the DB at create/resume/build time, and the
    // list reload (triggered by any state change) reconciles
    // membership via [_reseedTracking], so a tick never needs to
    // touch sqflite.
    for (final id in _trackedTimerIds) {
      final base = _baseRemainingById[id];
      final runStartedAt = _runStartedAtById[id];
      if (base == null || runStartedAt == null) continue;
      final elapsed = now.difference(runStartedAt).inSeconds;
      // Clamp both ends: elapsed can be negative right after a
      // resume (clock skew) and can overshoot the base when the
      // process was suspended past the fire time — the native
      // alarm owns actual firing, the display just pins at 0.
      final newRemaining = (base - elapsed).clamp(0, base);
      if (_liveRemainingById[id] != newRemaining) {
        _liveRemainingById[id] = newRemaining;
        changed = true;
      }
    }
    // Only notify when a displayed second actually flipped, so the
    // UI rebuilds once per second rather than five times.
    if (changed && ref.mounted) {
      ref.read(timerTickProvider.notifier).bump();
    }
  }
}

/// A monotonically increasing counter bumped by [TimersNotifier]
/// each time a tracked timer's remaining-seconds value flips.
/// Watching this (instead of [timersProvider]) is what lets the
/// countdown UI re-render every second without re-querying the
/// database or re-running the async notifier's build on every tick.
final timerTickProvider = NotifierProvider<TimerTickNotifier, int>(
  TimerTickNotifier.new,
);

/// See [timerTickProvider].
class TimerTickNotifier extends Notifier<int> {
  @override
  int build() => 0;

  /// Advance the counter. Any increment notifies watchers; the
  /// absolute value is meaningless.
  void bump() {
    state = state + 1;
  }
}

/// Convenience provider exposing the live remaining-seconds for a
/// specific timer id. Returns `null` when the timer has never been
/// ticked (first tick hasn't fired yet) or when it is paused /
/// cancelled. Watching [timerTickProvider] rebuilds the widget on
/// every second-flip of any running timer; watching
/// [timersProvider] additionally rebuilds it when the list itself
/// changes (pause/resume/cancel) so the fallback to the persisted
/// value is re-evaluated.
final liveTimerRemainingForIdProvider = Provider.family<int?, int>((ref, id) {
  ref.watch(timerTickProvider);
  ref.watch(timersProvider);
  return ref.read(timersProvider.notifier).liveRemainingFor(id);
});

/// Legacy single-timer convenience provider. Returns the live
/// remaining of the first tracked timer, or `null`. Prefer
/// [liveTimerRemainingForIdProvider] in new code — multiple
/// timers can run concurrently and a single scalar can't
/// represent them all.
final liveTimerRemainingProvider = Provider<int?>((ref) {
  ref.watch(timerTickProvider);
  ref.watch(timersProvider);
  return ref.read(timersProvider.notifier).liveRemainingForActive;
});

/// Riverpod entry point for the timers list.
final timersProvider = AsyncNotifierProvider<TimersNotifier, List<TimerRecord>>(
  TimersNotifier.new,
);
