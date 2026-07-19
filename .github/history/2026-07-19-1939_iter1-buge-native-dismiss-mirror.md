# Iter 1 BUG E: native dismiss doesn't notify Dart

## Bug

After fixing BUG D (cancel PendingIntent identity), a 19:45 alarm was created
and its dismiss button was tapped. The native side correctly:

- logged `RingingActivity: Dismissing alarm id=3`
- stopped the foreground service (`AlarmService` gone from `dumpsys activity services`)
- removed the row from SharedPreferences
- removed the PendingIntent (`dumpsys alarm | grep wakeywakey.app` → 0 matches)

But the Dart UI (AlarmsScreen) still showed `19:45` with the switch **on**.
After the user re-opens the app cold, the row would resurrect on the next
`rescheduleAllPersisted` pass (because it was never deleted from sqflite).

## Root cause

Native side is the source of truth for the **running** alarm
(PendingIntent, sound, vibration, full-screen activity). The Dart side
owns the sqflite mirror used to render the AlarmsScreen.

The previous fix (BUGS A–D) wired the EventChannel to `ringingAlarmIdProvider`
for the ringing banner, but the **data** side of the UI was never told
that the underlying alarm had been dismissed. Result: native cleanup
vs. UI drift.

## Fix

`AlarmsNotifier` now subscribes to the EventChannel and reacts:

- `AlarmEventType.snoozed` → `ref.invalidateSelf()`. Native already
  re-scheduled. The sqflite row's `timeHour`/`timeMinute` is the
  natural fire time, not the snooze fire time, so the row is correct
  as-is; we just need to re-emit so listeners re-read.
- `AlarmEventType.dismissed` → new `_onNativeDismiss(alarmId)`:
  - If the row is already gone (user toggled off first), no-op.
  - If the alarm is repeating, the native side already re-armed
    the next fire, so we just refresh.
  - Otherwise, delete the row from sqflite and refresh.

## Files

- `lib/presentation/providers/alarms_provider.dart` — added
  `alarmEventsProvider` (StreamProvider) + `ref.listen` in
  `AlarmsNotifier.build()` + `_onNativeDismiss` helper.

## Test

After rebuild + install, retest T1-DISMISS end-to-end. Expect:

1. RingingActivity appears.
2. Tap dismiss.
3. `dumpsys alarm | grep -c wakeywakey.app` → 0.
4. MainActivity resumes with the alarm **gone** from the list.
5. Force-stop + re-open: alarm does not resurrect.

## Pre-existing note

`flutter test` was hanging on `Running build hooks…` for unrelated
test files (`test/domain/alarm_test.dart` even). Out of scope — same
symptom before the BUG E fix landed. Verification was done on device.
