# Iteration 3: Timer Implementation

- **Date:** 2026-07-21
- **Iteration:** 3
- **Commit:** `3a33da6` — `[Iter3] Implement Timer using shared AlarmManager pipeline + tests`

## What changed

Added a Timer feature that reuses the Iteration 1 `AlarmManager`
pipeline rather than introducing a parallel scheduling system.

The key design decision (per the brief): the timer is **not** a new
native pipeline. Instead, the Dart side forwards timer scheduling to
the existing `scheduleAlarm` MethodChannel with a `triggerType:
"TIMER"` and an absolute `triggerAtMillis`. The native
`AlarmScheduler` + `AlarmReceiver` + `AlarmService` + `RingingActivity`
pathways are unchanged, except that the ringing UI now prefixes the
label with `"Timer: "` when the trigger type is `TIMER` (so the user
sees "Timer: 5 minute eggs" instead of just "5 minute eggs").

- `lib/domain/timer_record.dart` — `TimerRecord` + `TimerState` enum
  (`running` / `paused` / `completed` / `cancelled`).
- `lib/data/timer_dao.dart` — full CRUD + `updateRemaining` /
  `updateState` / `deleteFinished` for live tick + cleanup.
- `lib/presentation/providers/timers_provider.dart` —
  `TimersNotifier` (create / cancel / pause / resume) with a 200 ms
  ticker for live countdown. Listens to `alarmEventsProvider` to
  mirror native dismissal into a `delete` of the timer row, **but only
  for events with `triggerType == "timer"`** so time-based alarm
  dismissals don't accidentally delete timer rows.
- `lib/presentation/screens/timer_screen.dart` — list view +
  `CreateTimerScreen` (HH:MM:SS steppers, 0–24h).
- Extended `lib/native_bridge/alarm_bridge.dart` with
  `scheduleTimer(payload)`, which forwards as `scheduleAlarm` with
  `triggerType: 'TIMER'`.
- Extended Kotlin:
  - `AlarmData` carries `triggerType` (default `"TIME"`).
  - `AlarmReceiver` emits the trigger type in the `fired` event.
  - `AlarmService` + `RingingActivity` carry the trigger type through
    to the UI.
  - `MainActivity.handleScheduleAlarm` accepts an optional
    `triggerAtMillis` for absolute-time fires.
- Updated `AlarmsNotifier` to skip events with
  `triggerType == "timer"` so dismissing a timer doesn't try to
  delete a row from the alarms table.

## Why

Iteration 3 of `workflow_plan.md`. Multiple concurrent timers are
supported (a primary use case — "boil eggs AND reply to the email in
20 min"). The decision to reuse the alarm pipeline keeps the
cold-start guarantee, reboot resilience, and lock-screen ringing
behavior consistent across alarms and timers.

## Files touched

### Dart
- `lib/domain/timer_record.dart` (new)
- `lib/data/timer_dao.dart` (new)
- `lib/presentation/providers/timers_provider.dart` (new)
- `lib/presentation/screens/timer_screen.dart` (new)
- `lib/native_bridge/alarm_bridge.dart` (added `scheduleTimer`)
- `lib/presentation/providers/alarms_provider.dart` (skip timer
  events; updated `ringingAlarmIdProvider`)

### Kotlin
- `android/app/src/main/kotlin/com/wakeywakey/app/AlarmScheduler.kt`
  (added `triggerType` to `AlarmData`)
- `android/app/src/main/kotlin/com/wakeywakey/app/AlarmReceiver.kt`
  (emits `triggerType` in fired event)
- `android/app/src/main/kotlin/com/wakeywakey/app/AlarmService.kt`
  (carries `triggerType` extra)
- `android/app/src/main/kotlin/com/wakeywakey/app/RingingActivity.kt`
  (prefixes label with "Timer: " when `TIMER`)
- `android/app/src/main/kotlin/com/wakeywakey/app/MainActivity.kt`
  (accepts `triggerAtMillis` in `scheduleAlarm` payload)

### Tests
- `test/domain/timer_record_test.dart` (new)
- `test/data/timer_dao_test.dart` (new)
- `test/native_bridge/alarm_bridge_schedule_timer_test.dart` (new)
- `test/presentation/providers/timers_provider_test.dart` (new)
- `test/presentation/screens/timer_screen_test.dart` (new)

## Verification

- [x] `flutter analyze` clean
- [x] `flutter test` passing (183/183 overall after Iter 4 landed)
- [x] `dart format --output=none --set-exit-if-changed .` passes
- [ ] Manual on-device check needed? **Yes:**
  - Set a short timer, background the app, confirm it fires on time.
  - Force-kill the app mid-countdown, confirm the timer still fires.
  - Cancel a timer before it fires, confirm no stray notification
    appears.
  - Pending human verification per `workflow_plan.md` Iter 3 DoD.

## Test isolation note

`:memory:` databases in `sqflite_common_ffi` are **shared across
opens** in the same process, so the timer DAO tests use unique temp
file paths for each test instead. Teardown ordering is
`container.dispose()` BEFORE `StreamController.close()` — reversing
the order causes "Cannot close sink while adding stream" errors in
the timer notifier tests.
