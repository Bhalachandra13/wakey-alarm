# Extract AlarmScheduler helper + persist alarm data to SharedPreferences

- **Date:** 2026-07-11 13:25
- **Iteration:** 1
- **Commit:** <pending>

## What changed

**New file** `android/app/src/main/kotlin/com/wakeywakey/app/AlarmScheduler.kt`:

A single Kotlin `object` that owns every alarm-scheduling concern:

- **`schedule(context, AlarmData, triggerAtMillis)`** — builds the
  fire PendingIntent (broadcast → `AlarmReceiver`, with the full
  alarm payload as extras) and the show PendingIntent (activity →
  `RingingActivity`), calls `AlarmManager.setAlarmClock(...)`, and
  persists the `AlarmData` to `SharedPreferences`.
- **`cancel(context, alarmId)`** — cancels the AlarmManager entry
  (with `FLAG_NO_CREATE` so we don't create a PI just to cancel)
  and removes the persisted record.
- **`reschedulePersisted(context, alarmId)`** and
  **`rescheduleAllPersisted(context)`** — re-schedule from the
  SharedPreferences snapshot. The first is for `AlarmReceiver`'s
  self-reschedule path; the second is for `BootReceiver` on
  `BOOT_COMPLETED`.
- **`readPersisted(context, alarmId)`** — exposes the persisted
  record so `RingingActivity.scheduleSnooze` can re-schedule the
  same alarm at "now + N min" without hand-rolling the full
  payload.

The `AlarmData` data class is the canonical record: `alarmId`,
`timeHour`, `timeMinute`, `repeatDays`, `label`, `soundUri`,
`vibrate`, `snoozeDurationMin`, `maxSnoozeCount`.

**New extras on `AlarmReceiver`**:
`EXTRA_TIME_HOUR`, `EXTRA_TIME_MINUTE`, `EXTRA_REPEAT_DAYS` — needed
by `AlarmReceiver.onReceive` (and the `AlarmScheduler` self-
reschedule logic added in the next commit) to re-schedule a
repeating alarm without re-reading from SharedPreferences.

**Refactored callers**:
- `MainActivity.handleScheduleAlarm` / `handleCancelAlarm` —
  payload validation stays in `MainActivity`; everything else
  delegates to `AlarmScheduler`. Net diff: ~80 lines removed
  from `MainActivity`.
- `RingingActivity.scheduleSnooze` — now reads the persisted
  `AlarmData` for the alarm and re-schedules via
  `AlarmScheduler.schedule(context, data, now + N*60s)` instead
  of hand-rolling its own `setAlarmClock` call. The 5-arg
  signature collapsed to `(alarmId, snoozeDurationMin)` since
  everything else is in the persisted record.

## Why

- **Boot survival** — `BootReceiver` (next commit) needs to know
  *which* alarms to re-schedule after a device reboot. The OS
  clears `AlarmManager` state on reboot, so without persistent
  metadata the user would have to open the app after every
  reboot. SharedPreferences is the right store: it is available
  synchronously in `BroadcastReceiver.onReceive` (which is when
  `BOOT_COMPLETED` fires), and the Dart-side sqflite database
  cannot be read without a live Flutter engine.
- **Single source of truth** — the schedule/cancel logic was
  about to be needed in three places: `MainActivity`,
  `AlarmReceiver` (self-reschedule), and `RingingActivity`
  (snooze). Inlining it in `MainActivity` was already a
  duplicate of `RingingActivity.scheduleSnooze`. With three
  callers imminent, an object is the right unit of code reuse.
- **Snooze re-schedule for free** — by routing snooze through
  `AlarmScheduler.schedule`, the snoozed alarm is now persisted
  to SharedPreferences. Before this change, a snooze would
  update the AlarmManager entry but not the persistence layer,
  so a reboot after a snooze would have re-scheduled the
  *original* time, not the snoozed time.

## Files touched

- `android/app/src/main/kotlin/com/wakeywakey/app/AlarmScheduler.kt`
  — New.
- `android/app/src/main/kotlin/com/wakeywakey/app/AlarmReceiver.kt`
  — Added `EXTRA_TIME_HOUR`, `EXTRA_TIME_MINUTE`,
  `EXTRA_REPEAT_DAYS` companion constants.
- `android/app/src/main/kotlin/com/wakeywakey/app/MainActivity.kt`
  — `handleScheduleAlarm` builds `AlarmData` and delegates;
  `handleCancelAlarm` delegates; removed unused imports of
  `AlarmManager` and `PendingIntent`.
- `android/app/src/main/kotlin/com/wakeywakey/app/RingingActivity.kt`
  — `scheduleSnooze` now uses `AlarmScheduler`; removed unused
  imports of `AlarmManager`, `PendingIntent`, and `Context`.

## Verification

- [x] `gradle :app:compileDebugKotlin` — BUILD SUCCESSFUL
  (after fixing a `this.data` shadowing bug in the `apply`
  block and a `String?.orEmpty()` typo).
- [x] `dart analyze lib/` — "No issues found!" (no Dart change,
  sanity check that the channel contract is unchanged).
- [ ] `flutter test` — N/A, no Dart change.
- [ ] Manual on-device check needed? Yes — verifying that
  SharedPreferences persistence survives an app force-kill is
  part of the Iter1 verification checklist. The cancellation
  code path (which uses `FLAG_NO_CREATE`) is the trickiest;
  it's covered by the receiver self-reschedule task in the
  next commit.

## Design notes

- The PendingIntent identity for each alarm is `(alarmId,
  AlarmReceiver component, "wakey://alarm/$alarmId" data URI,
  ACTION_FIRE_ALARM action)`. The data URI is unique per
  alarmId; the action and component are shared. FLAG_UPDATE_CURRENT
  on a re-schedule still updates the extras as expected.
- `writeAllInternal` uses `commit()` (synchronous) rather than
  `apply()` (async). The cost is one disk fsync; the benefit is
  that `BootReceiver` can read the latest state immediately.
  This is safe to do because we only ever touch this prefs
  file from the main thread / a single broadcast receiver at a
  time.
- `cancel()` is idempotent — calling it for an `alarmId` that
  is not scheduled still returns success. This is important
  for the `AlarmReceiver` self-reschedule path, where the
  one-shot branch will call `cancel()` for an alarmId that
  has just fired (and may or may not still be in
  AlarmManager's view).

## Known gaps (deferred to follow-up tasks)

1. **Repeating alarms still only fire once.** `AlarmReceiver`
   does not yet re-schedule after the alarm fires. Wired in
   the next commit.
2. **No `BootReceiver` yet.** The persistence layer is in
   place, but nothing reads it on `BOOT_COMPLETED`. Wired in
   the next commit.
3. **No snooze max-count enforcement.** `EXTRA_MAX_SNOOZE_COUNT`
   is read but ignored; a persisted snooze counter is the
   right next step.
