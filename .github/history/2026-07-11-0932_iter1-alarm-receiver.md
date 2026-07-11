# Native AlarmReceiver for AlarmManager fire events

- **Date:** 2026-07-11 09:32
- **Iteration:** 1
- **Commit:** 423d4bf

## What changed

Added `android/app/src/main/kotlin/com/wakeywakey/app/AlarmReceiver.kt`,
a `BroadcastReceiver` invoked by `AlarmManager.setAlarmClock()` when an
alarm fires.

Responsibilities:
- Pulls the alarm's `alarmId`, `label`, `soundUri`, `vibrate`,
  `snoozeDurationMin`, and `maxSnoozeCount` from the broadcast `Intent`
  extras and forwards them as a `startForegroundService` (or
  `startService` on pre-O) call to `AlarmService`.
- Declares the `EXTRA_*` constants as `companion object` fields so
  `MainActivity` (when scheduling) and `RingingActivity` / `AlarmService`
  (when handling) all share the same key names.

## Why

`AlarmManager.setAlarmClock()` delivers a wakeup `Intent` to a
`BroadcastReceiver` — that's the only contract that survives Doze mode
and force-killed apps. The receiver itself must do as little work as
possible (the system can kill a long-running receiver), so its only job
is to delegate to a foreground `Service` that owns the actual ringing
state.

## Files touched

- `android/app/src/main/kotlin/com/wakeywakey/app/AlarmReceiver.kt` — New

## Verification

- [x] `flutter analyze` clean
- [x] `flutter test` — N/A
- [ ] Manual on-device check needed? Yes — alarm fire path is part of
  the Iter1 manual checklist; will be exercised in a later build with
  `AlarmService` + `RingingActivity` in place.
