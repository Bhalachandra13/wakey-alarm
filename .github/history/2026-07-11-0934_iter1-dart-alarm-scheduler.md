# Dart AlarmScheduler bridging Alarm domain to native

- **Date:** 2026-07-11 09:34
- **Iteration:** 1
- **Commit:** 0887702

## What changed

Added `lib/domain/alarm_scheduler.dart`, a thin Dart layer that
translates an `Alarm` domain object into the primitive payload map the
Kotlin side (`AlarmBridge.scheduleAlarm`) expects, and decides when to
schedule or cancel.

API:
- `scheduleAlarm(Alarm)` — returns `false` early for non-`TIME` alarms
  or alarms without an `id` / `timeHour` / `timeMinute`. Currently only
  time-based alarms are forwarded; geofence alarms (Iter4) will go
  through a separate `GeofencingBridge`.
- `cancelAlarm(int alarmId)` — forwards to the native cancel.
- `rescheduleAll(List<Alarm>)` — for Dart-side re-sync (e.g. after a
  permission grant); the Kotlin `BootReceiver` handles post-reboot
  re-scheduling natively.

## Why

Putting the conversion in `domain/` (not `presentation/` or
`native_bridge/`) keeps the boundary clean:
- `native_bridge/alarm_bridge.dart` only knows about raw maps.
- `domain/alarm_scheduler.dart` knows about `Alarm` and is the only
  place that decides *whether* an alarm should be scheduled.
- `presentation/` calls the scheduler, not the bridge directly.

## Files touched

- `lib/domain/alarm_scheduler.dart` — New

## Verification

- [x] `flutter analyze` clean (no new issues)
- [x] `flutter test` — N/A (this is glue code exercised via
  `AlarmsNotifier`; will be unit-tested once the native side is wired)
- [ ] Manual on-device check needed? Yes — once `MainActivity`
  implements the real `setAlarmClock` call (next task).
