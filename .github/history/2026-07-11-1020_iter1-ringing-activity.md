# Native RingingActivity for full-screen dismiss/snooze UI

- **Date:** 2026-07-11 10:20
- **Iteration:** 1
- **Commit:** 2f25650

## What changed

Added the **full-screen alarm ringing UI** as a pure native
`Activity` (not a Flutter activity), so the dismiss/snooze buttons
work even when the Flutter engine is dead — e.g. the process was
cold-started by the `AlarmManager` broadcast after a force-kill.

New files:
- `android/app/src/main/res/layout/activity_ringing.xml` — black
  full-screen layout: alarm label at top, big yellow **Snooze** and
  red **Dismiss** buttons at the bottom.
- `android/app/src/main/kotlin/com/wakeywakey/app/RingingActivity.kt`
  — sets `setShowWhenLocked` / `setTurnScreenOn` (with pre-API-27
  fallback to `WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED`),
  reads alarm extras from the launching `Intent`, wires the buttons:
  - **Snooze** → re-schedules the same alarm via
    `AlarmManager.setAlarmClock()` at `now + snoozeDurationMin`,
    forwards the same extras to `AlarmReceiver`, then stops
    `AlarmService` and finishes.
  - **Dismiss** → stops `AlarmService` and finishes.
  - **Back button** is intentionally blocked (`moveTaskToBack(true)`)
    so the alarm can't be silently dismissed — the user must tap one
    of the two buttons.

Modified:
- `android/app/src/main/AndroidManifest.xml` — registered
  `RingingActivity` as a non-exported, single-instance, exclude-from-
  recents activity in its own task (`taskAffinity=""`).

## Why

`AlarmService` already builds a `PendingIntent` to `RingingActivity`
(in its `buildFullScreenIntent`), but until now the class didn't
exist — the project would not even compile. This commit closes that
gap and makes the fire → ring → dismiss/snooze path complete at the
native level.

Tying the ringing UI to Flutter would re-introduce the very failure
mode the native pipeline exists to prevent (Dart engine cold-start
time on a wakeup). Keeping it as a plain `Activity` means a force-
killed app still rings reliably.

Snooze re-schedules inline here on purpose — extracting a shared
`AlarmScheduler` helper between `MainActivity` and `RingingActivity`
is a separate workflow task ("Snooze re-scheduling logic") that
will land once the basic firing path is proven on-device.

## Files touched

- `android/app/src/main/res/layout/activity_ringing.xml` — New
- `android/app/src/main/kotlin/com/wakeywakey/app/RingingActivity.kt` — New
- `android/app/src/main/AndroidManifest.xml` — registered the new
  activity.

## Verification

- [x] `dart analyze` clean on Dart files
- [x] `./gradlew :app:compileDebugKotlin` — BUILD SUCCESSFUL
- [ ] `flutter analyze` (full project) — N/A, no Dart change
- [ ] `flutter test` — N/A, no Dart change
- [ ] Manual on-device check needed? Yes — see
  `docs/workflow_plan.md` Iteration 1 DoD:
  - Dismiss and snooze both work correctly from the lock screen
  - Schedule an alarm, force-kill the app, confirm it still rings
