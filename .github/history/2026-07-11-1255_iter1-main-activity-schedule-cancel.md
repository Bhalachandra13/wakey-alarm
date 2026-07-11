# Implement real scheduleAlarm / cancelAlarm in MainActivity

- **Date:** 2026-07-11 12:55
- **Iteration:** 1
- **Commit:** ca01d33

## What changed

Replaced the two `Log.d(...) + result.success(...)` stubs in
`MainActivity.kt` with real implementations that talk to
`AlarmManager`:

- **`scheduleAlarm`** — Validates the Dart payload (alarmId, hour,
  minute are required), computes the next fire time using
  `NextAlarmTime.compute()`, builds **two** PendingIntents keyed by
  `alarmId`:
  - **fire** (broadcast → `AlarmReceiver`) — carries the full alarm
    payload (label, soundUri, vibrate, snoozeDurationMin,
    maxSnoozeCount).
  - **show** (activity → `RingingActivity`) — what the system fires
    when the user taps the status-bar alarm icon.

  Both use `FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE`; calling
  `scheduleAlarm` twice for the same alarmId updates the existing
  PendingIntent rather than creating a duplicate.

  Then calls `AlarmManager.setAlarmClock(AlarmClockInfo, firePI)`.
  This is the only API that (a) shows the alarm in the system tray
  and (b) fires through Doze without requiring
  `SCHEDULE_EXACT_ALARM` on API 31+ — both of which an actual alarm
  app needs.

- **`cancelAlarm`** — Reconstructs the fire PendingIntent with
  `FLAG_NO_CREATE` and passes it to `AlarmManager.cancel()`. If no
  matching PendingIntent is registered, the call is a no-op (we
  don't *create* a PI just to cancel it).

Both handlers return the same map shape the Dart side already
expects: `{"scheduled": <bool>, "triggerAtMillis": <long>}` and
`{"cancelled": <bool>}` respectively. Genuine system errors
(e.g. AlarmManager service unavailable) raise
`result.error("alarm_manager_unavailable", ...)`.

## Why

`AlarmScheduler` (Dart) was wired to `AlarmsNotifier` and the
`AlarmBridge` had the correct `MethodChannel` shape, but the
Kotlin side was a stub — so creating an alarm from the UI
persisted to sqflite and *nothing* happened on the Android side.
This commit closes that gap and makes the native pipeline
end-to-end functional (UI → DB → AlarmManager → Receiver →
Service → Ringing).

## Files touched

- `android/app/src/main/kotlin/com/wakeywakey/app/MainActivity.kt` —
  Replaced the two stub branches in the `setMethodCallHandler`
  lambda; added `handleScheduleAlarm` and `handleCancelAlarm`
  private helpers (kept the inline-stub style, did not yet extract
  a separate `AlarmScheduler.kt` — that's deferred to the
  BootReceiver task where a third caller will exist).

## Verification

- [x] `dart analyze lib/native_bridge/alarm_bridge.dart
       lib/domain/alarm_scheduler.dart
       lib/presentation/providers/alarms_provider.dart`
       → "No issues found!"
- [x] `./gradlew :app:compileDebugKotlin` → BUILD SUCCESSFUL
       (no warnings, no errors)
- [ ] `flutter test` — not run; no Dart change in this commit
- [ ] Manual on-device check needed? Yes — the Iter1 DoD requires
  scheduling an alarm and confirming the device rings, dismisses
  cleanly, and snoozes correctly. Deferred to the Iter1
  verification commit after BootReceiver + manifest cleanup.

## Known gaps (deferred to follow-up tasks)

1. **Repeating alarms only fire once.** `setAlarmClock` is
   scheduled once; nothing re-schedules the next occurrence when
   the alarm fires. `AlarmReceiver.onReceive` will need to
   re-call `handleScheduleAlarm` (or an extracted helper) to
   schedule the next `repeatDays` match. Logged in
   `docs/workflow_plan.md` and flagged in the next "Snooze
   re-scheduling logic" commit.
2. **No `AlarmScheduler.kt` extraction yet.** Inlining the
   logic in `MainActivity` keeps this commit minimal; once
   `BootReceiver` lands (re-schedule all enabled alarms after
   reboot, without a running Flutter engine), the helper will
   be extracted at that time.
3. **`RingingActivity.scheduleSnooze` still hand-rolls its
   own PendingIntent.** The shape is intentionally compatible
   (same `requestCode=alarmId`, same `AlarmReceiver` component,
   `FLAG_UPDATE_CURRENT | FLAG_IMMUTABLE`) so a snooze will
   update the same PendingIntent the original schedule created.
   Refactoring both to share a helper is the "Snooze
   re-scheduling logic" follow-up.
