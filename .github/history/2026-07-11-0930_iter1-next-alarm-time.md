# Native next-fire-time utility for time-based alarms

- **Date:** 2026-07-11 09:30
- **Iteration:** 1
- **Commit:** f1873e2

## What changed

Added `android/app/src/main/kotlin/com/wakeywakey/app/NextAlarmTime.kt`,
a small Kotlin `object` that computes the next epoch-millisecond fire
time for a given `hour:minute` plus an optional comma-separated set of
weekday abbreviations (`"MON,WED,FRI"`).

The logic:
- **One-shot** (`repeatDays` null/blank): if `hour:minute` is already in
  the past today, roll forward to tomorrow at the same time.
- **Repeating**: walk forward up to 7 days, returning the first day-of-week
  in the configured set whose `hour:minute` is still in the future.
- Defaults to today if the configured time is still later today.

## Why

Both `MainActivity.scheduleAlarm()` (Dart → native) and the upcoming
`BootReceiver` (device reboot reschedule) need to compute the next fire
time. Keeping this logic in one place ensures they agree, and is
testable in isolation without spinning up a Flutter engine or an
`AlarmManager` mock.

## Files touched

- `android/app/src/main/kotlin/com/wakeywakey/app/NextAlarmTime.kt` — New

## Verification

- [ ] `flutter analyze` clean
- [x] `flutter test` (existing) — N/A, no Dart change
- [ ] Manual on-device check needed? No — pure utility, exercised
  transitively once `MainActivity.scheduleAlarm()` and `BootReceiver` use it.
