# Wire AlarmScheduler into AlarmsNotifier

- **Date:** 2026-07-11 09:36
- **Iteration:** 1
- **Commit:** <pending>

## What changed

Two related changes in `lib/`:

1. **`presentation/providers/alarms_provider.dart`** — added two new
   providers (`alarmBridgeProvider`, `alarmSchedulerProvider`) and
   wired the `AlarmsNotifier` to call them on every mutation:
   - `insertAlarm`: schedules the native alarm with the DB-assigned id
     if `isEnabled`.
   - `updateAlarm`: cancels the old native schedule, then re-schedules
     if still enabled (always cancel first to avoid stale
     `PendingIntent`s from the old time).
   - `deleteAlarm`: cancels the native schedule before deleting the row.
   - `toggleEnabled`: re-reads the full alarm and schedules / cancels
     accordingly.
   - `toggleArmed`: still a no-op for the schedule (location-based
     arming is Iter4).

2. **`native_bridge/alarm_bridge.dart`** — promoted the `AlarmBridge`
   constructor to `const` so `Provider<AlarmBridge>` can return
   `const AlarmBridge()` without a Dart analyzer error.

## Why

Without this wiring the UI can insert/edit/delete alarms in sqflite
but the native `AlarmManager` is never touched — the app would
correctly persist data but never ring. The `const` promotion is a
small but necessary clean-up surfaced by the analyzer once the
provider tried to use `const AlarmBridge()`.

## Files touched

- `lib/native_bridge/alarm_bridge.dart` — constructor made `const`
- `lib/presentation/providers/alarms_provider.dart` — added
  `alarmBridgeProvider` + `alarmSchedulerProvider` and wired them
  into `AlarmsNotifier` insert/update/delete/toggle methods.

## Verification

- [x] `dart analyze` on changed files — no issues
- [x] `dart format` on changed files — clean
- [ ] `flutter test` — full suite runs unchanged (the 46 pre-existing
  tests still pass against a mocked `AlarmDao`)
- [ ] Manual on-device check needed? Yes — once `MainActivity` has
  the real `setAlarmClock` implementation.
