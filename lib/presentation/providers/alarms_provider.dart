import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakey_alarm/data/alarm_dao.dart';
import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/domain/alarm_scheduler.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';

/// Provides access to the [WakeyDatabase] singleton.
final databaseProvider = Provider<WakeyDatabase>((ref) {
  return WakeyDatabase();
});

/// Provides access to the [AlarmDao] singleton.
final alarmDaoProvider = Provider<AlarmDao>((ref) {
  final database = ref.watch(databaseProvider);
  return AlarmDao(database);
});

/// Provides the [AlarmBridge] singleton (MethodChannel + EventChannel wrappers).
final alarmBridgeProvider = Provider<AlarmBridge>((ref) {
  return const AlarmBridge();
});

/// Provides the [AlarmScheduler] that converts [Alarm] objects into native
/// AlarmManager scheduling calls via [AlarmBridge].
final alarmSchedulerProvider = Provider<AlarmScheduler>((ref) {
  final bridge = ref.watch(alarmBridgeProvider);
  return AlarmScheduler(bridge);
});

/// Stream of alarm lifecycle events coming from native (fired /
/// snoozed / dismissed), exposed as a Riverpod `StreamProvider` so
/// notifiers and widgets can `ref.listen` for state changes.
///
/// Distinct from [ringingAlarmIdProvider] (which folds the same
/// stream into a single nullable id for the ringing banner).
/// [alarmEventsProvider] preserves the full event so callers can
/// react to dismiss/snooze with their own side effects.
final alarmEventsProvider = StreamProvider<AlarmEvent>((ref) {
  final bridge = ref.watch(alarmBridgeProvider);
  return bridge.alarmEvents;
});

/// AsyncNotifier for managing the list of alarms.
class AlarmsNotifier extends AsyncNotifier<List<Alarm>> {
  late AlarmDao _alarmDao;
  late AlarmScheduler _scheduler;

  @override
  Future<List<Alarm>> build() async {
    _alarmDao = ref.watch(alarmDaoProvider);
    _scheduler = ref.watch(alarmSchedulerProvider);
    // Subscribe to native dismiss/snooze events so the sqflite
    // mirror stays in sync with the native SharedPreferences copy.
    // The native side is the source of truth for the running
    // alarm (it cleans up the PendingIntent); the Dart side has
    // to mirror that decision or the UI will show stale rows
    // after the next re-open. See RingingActivity.dismissAlarm.
    ref.listen<AsyncValue<AlarmEvent>>(alarmEventsProvider, (prev, next) {
      final event = next.value;
      if (event == null) return;
      switch (event.type) {
        case AlarmEventType.fired:
          // RingingActivity already showed the UI; nothing to
          // do here. The ringing banner is driven by
          // `ringingAlarmIdProvider` directly.
          break;
        case AlarmEventType.snoozed:
          // The native side already re-scheduled the alarm.
          // We don't need to touch the sqflite row because the
          // Alarm object's `time` field is the natural fire
          // time, not the snooze fire time. The UI is correct
          // as-is; just refresh so any listeners re-read.
          ref.invalidateSelf();
        case AlarmEventType.dismissed:
          _onNativeDismiss(event.alarmId);
      }
    });
    return _alarmDao.getAll();
  }

  /// Mirror a native dismiss into the sqflite database.
  ///
  /// For a one-shot, the native side already cancelled the
  /// PendingIntent + removed the SharedPreferences row, so we
  /// delete the sqflite row too. For a repeating alarm, the
  /// native side already re-scheduled the next natural fire,
  /// so we just refresh — the row's time field doesn't change.
  /// If the row was already gone (e.g. user toggled it off
  /// before the ringing UI showed up), the delete is a safe
  /// no-op.
  Future<void> _onNativeDismiss(int alarmId) async {
    final alarm = await _alarmDao.read(alarmId);
    if (alarm == null) {
      // Already gone — nothing to do.
      ref.invalidateSelf();
      return;
    }
    if (alarm.repeatDays != null && alarm.repeatDays!.isNotEmpty) {
      // Native side re-scheduled; just refresh.
      ref.invalidateSelf();
      return;
    }
    await _alarmDao.delete(alarmId);
    ref.invalidateSelf();
  }

  /// Insert a new alarm, schedule it if enabled, and refresh the list.
  Future<int> insertAlarm(Alarm alarm) async {
    final id = await _alarmDao.insert(alarm);
    // Schedule the alarm with the DB-assigned ID before refreshing the list.
    if (alarm.isEnabled) {
      final scheduled = alarm.copyWith(id: id);
      await _scheduler.scheduleAlarm(scheduled);
    }
    ref.invalidateSelf();
    return id;
  }

  /// Update an existing alarm, re-schedule or cancel as needed, and refresh.
  Future<void> updateAlarm(Alarm alarm) async {
    await _alarmDao.update(alarm);
    // Cancel any existing schedule then re-schedule if still enabled.
    // Always cancel first to avoid stale PendingIntents from the old time.
    if (alarm.id != null) {
      await _scheduler.cancelAlarm(alarm.id!);
      if (alarm.isEnabled) {
        await _scheduler.scheduleAlarm(alarm);
      }
    }
    ref.invalidateSelf();
  }

  /// Delete an alarm by ID, cancel its schedule, and refresh the list.
  Future<void> deleteAlarm(int id) async {
    await _scheduler.cancelAlarm(id);
    await _alarmDao.delete(id);
    ref.invalidateSelf();
  }

  /// Toggle the enabled state of an alarm and schedule/cancel accordingly.
  Future<void> toggleEnabled(int id, bool newState) async {
    await _alarmDao.updateEnabled(id, newState);
    if (newState) {
      // Re-read the full alarm to get all fields needed for scheduling.
      final alarm = await _alarmDao.read(id);
      if (alarm != null) {
        await _scheduler.scheduleAlarm(alarm);
      }
    } else {
      await _scheduler.cancelAlarm(id);
    }
    ref.invalidateSelf();
  }

  /// Toggle the armed state of an alarm (for location-based alarms).
  Future<void> toggleArmed(int id, bool newState) async {
    await _alarmDao.updateArmed(id, newState);
    // Arming/disarming of geofence alarms is handled by GeofencingClient
    // in Iteration 4; no AlarmManager scheduling needed here.
    ref.invalidateSelf();
  }

  /// Refresh the alarms list from the database.
  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

/// Provider for the alarms notifier, which manages the list of alarms
/// and provides CRUD operations.
final alarmsNotifierProvider =
    AsyncNotifierProvider<AlarmsNotifier, List<Alarm>>(AlarmsNotifier.new);

/// Convenience provider to access the current alarms list directly.
/// Use this when you only need to read the alarms, not modify them.
final alarmsProvider = Provider<AsyncValue<List<Alarm>>>((ref) {
  return ref.watch(alarmsNotifierProvider);
});

/// Get a single alarm by ID (derived from the alarms list).
final alarmByIdProvider = FutureProvider.family<Alarm?, int>((ref, id) async {
  final alarmDao = ref.watch(alarmDaoProvider);
  return alarmDao.read(id);
});

/// Get only enabled alarms.
final enabledAlarmsProvider = FutureProvider<List<Alarm>>((ref) async {
  final alarmDao = ref.watch(alarmDaoProvider);
  return alarmDao.getEnabledAlarms();
});

/// The id of the alarm currently ringing, or null if no alarm is ringing.
///
/// Subscribes to [AlarmBridge.alarmEvents] and folds the stream into a
/// single `int?` value:
///
/// * `fired(alarmId)` sets the state to `alarmId`.
/// * `dismissed(alarmId)` and `snoozed(alarmId)` set the state to null.
///
/// The provider yields `null` as the initial value (no alarm is ringing
/// when the app starts), so consumers can `await` its `future` without
/// having to special-case the pre-fire state.
///
/// Because the underlying event stream does not replay past events, this
/// provider reflects *only* events received while at least one listener
/// was active. If the user is not in the app when an alarm fires, the
/// "ringing" state will simply stay at null — which matches user
/// expectations (they can't see in-app state if the app is closed).
final ringingAlarmIdProvider = StreamProvider<int?>((ref) async* {
  final bridge = ref.watch(alarmBridgeProvider);
  yield null;
  await for (final event in bridge.alarmEvents) {
    switch (event.type) {
      case AlarmEventType.fired:
        yield event.alarmId;
      case AlarmEventType.snoozed:
      case AlarmEventType.dismissed:
        yield null;
    }
  }
});
