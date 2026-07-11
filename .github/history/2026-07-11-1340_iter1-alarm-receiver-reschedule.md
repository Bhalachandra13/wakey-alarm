# Self-reschedule repeating alarms + clean up one-shots in AlarmReceiver

- **Date:** 2026-07-11 13:40
- **Iteration:** 1
- **Commit:** <pending>

## What changed

`android/app/src/main/kotlin/com/wakeywakey/app/AlarmReceiver.kt` now
does more than just hand the alarm off to the foreground service.
After starting `AlarmService`, it self-reschedules the next
occurrence:

- **Repeating alarm** (`repeatDays` extra is non-blank) — rebuild
  an `AlarmScheduler.AlarmData` from the Intent extras, compute
  the next matching day-of-week via
  `NextAlarmTime.compute(data.timeHour, data.timeMinute, repeatDays)`,
  and re-call `AlarmScheduler.schedule(context, data, nextTrigger)`.
  A "MON,WED,FRI" alarm now keeps firing on every subsequent
  matching day without user action.

- **One-shot alarm** (`repeatDays` is null/blank) — call
  `AlarmScheduler.cancel(context, alarmId)`. Without this, the
  one-shot would remain in SharedPreferences and
  `BootReceiver` would resurrect it after the next reboot,
  which is the wrong behaviour for an alarm that the user
  expected to fire exactly once.

The data for the re-schedule comes from the Intent extras
populated by `AlarmScheduler.buildFireIntent` at schedule time
— no SharedPreferences lookup is required at fire time.

## Why

This was the last piece of the "alarm fires at the right time,
forever" puzzle for repeating alarms. Before this change, a
user who set a daily 7am alarm would only hear it once: the
second day's 7am would never come because nothing re-armed the
`AlarmManager` after the first fire. The fix is a one-time
re-arm in the receiver.

Equally important is the one-shot cleanup branch. Without it,
the receiver does the right thing (fire once) but the
persistence layer keeps the record around, so the next reboot
would fire the same one-shot *again*. That would be
user-hostile (an alarm they had to manually trigger as a
"surprise me once" type would re-fire every reboot until they
opened the app and disabled it).

## Files touched

- `android/app/src/main/kotlin/com/wakeywakey/app/AlarmReceiver.kt`
  — Added the `rescheduleOrCleanup` private helper. No new
  imports (only types already in the package or in `android.*`).

## Verification

- [x] `gradle :app:compileDebugKotlin` — BUILD SUCCESSFUL
- [ ] `dart analyze` — N/A, no Dart change
- [ ] `flutter test` — N/A, no Dart change
- [ ] Manual on-device check needed? Yes — the Iter1
  verification checklist now exercises:
  1. Schedule a one-shot alarm 2 minutes out → wait → verify
     it fires, then reboot and verify it does **not** fire
     again.
  2. Schedule a daily 7am alarm → temporarily set the
     device clock 1 minute before 7am → wait → verify it
     fires and that the next day's 7am is also armed (check
     `adb shell dumpsys alarm`).

## Edge cases handled

- **Missing alarmId** — if the intent's `EXTRA_ALARM_ID` is
  missing or negative, the receiver logs a warning and skips
  the re-schedule / cancel step. The service still starts
  (with `alarmId = -1` in its own extras) so the user can
  dismiss; we just don't pollute AlarmManager with a
  malformed entry.
- **Missing time fields** — the receiver falls back to
  `timeHour=0, timeMinute=0`, which would schedule the
  alarm for the next 00:00. This is a sensible
  last-resort default; it would only ever trigger if
  someone scheduled an alarm without populating these
  extras, which `AlarmScheduler` never does.

## Known gaps (still on the list)

1. `BootReceiver` is not yet implemented — the
   SharedPreferences persistence is in place but nothing
   reads it on `BOOT_COMPLETED`. Next commit.
2. No snooze max-count enforcement — `EXTRA_MAX_SNOOZE_COUNT`
   is propagated but not enforced; a persisted snooze
   counter is a follow-up.
3. The dismiss/snooze outcomes are not yet forwarded to
   Dart via the `EventChannel`. Next milestone.
