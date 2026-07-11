# Native AlarmService foreground service for sound + vibration

- **Date:** 2026-07-11 09:33
- **Iteration:** 1
- **Commit:** <pending>

## What changed

Added `android/app/src/main/kotlin/com/wakeywakey/app/AlarmService.kt`,
the foreground `Service` that owns the *runtime* state of an alarm
that is currently ringing (the `AlarmReceiver` is the entry point; the
service outlives the receiver).

Responsibilities:
- Promote itself to a foreground service with a high-priority
  notification (`NotificationCompat.PRIORITY_MAX`,
  `CATEGORY_ALARM`, `VISIBILITY_PUBLIC`) whose
  `fullScreenIntent` opens `RingingActivity` so the alarm shows on the
  lock screen.
- Play the configured ringtone via `RingtoneManager` (with
  `USAGE_ALARM` audio attributes on API 28+) on a loop, falling back
  to the system default alarm sound if the configured `soundUri` is
  blank or unparseable.
- Vibrate on a long-short-long pattern (using `VibratorManager` on
  API 31+ and the deprecated `Vibrator` below).
- Stop itself cleanly when it receives `ACTION_STOP_ALARM`
  (sent by `RingingActivity` on dismiss or snooze).

## Why

A `BroadcastReceiver` is the only way to be cold-started by
`AlarmManager.setAlarmClock()`, but the OS may kill a long-running
receiver. A foreground service is the only process-level construct
that survives for the duration of the ringing and is allowed to play
audio / vibrate / keep the screen on / show a notification without
background-execution restrictions.

## Files touched

- `android/app/src/main/kotlin/com/wakeywakey/app/AlarmService.kt` —
  New (was created mid-session by an earlier subagent, never
  committed; landing here as part of the cleanup pass).

## Verification

- [x] `dart analyze` clean (Dart-side, no change)
- [x] `./gradlew :app:compileDebugKotlin` — BUILD SUCCESSFUL
  (RingingActivity now exists, so the `RingingActivity::class.java`
  reference compiles)
- [ ] Manual on-device check needed? Yes — this is the heart of the
  Iter1 manual checklist. Once `MainActivity.scheduleAlarm()` and
  `BootReceiver` are wired, force-kill + reboot scenarios can be
  verified against `docs/workflow_plan.md` §Iteration 1 DoD.
