# Iter 1 — Snooze / Dismiss / Cancel bugfixes from on-device test

During the 19:20 manual on-device verification pass on the Pixel 8
device, three correlated bugs surfaced in the native alarm
pipeline. All three are now fixed; the full Iter 1 manual checklist
remains in `docs/workflow_plan.md` for re-execution on the next
APK.

## Bugs found and fixed

### BUG A — Receiver cancelled one-shots before RingingActivity could read them

`AlarmReceiver.onReceive` was unconditionally removing the
persisted data for a one-shot on natural fire. The receiver runs
before the Flutter engine exists, so it just removed the row, then
handed off to `AlarmService` which launched `RingingActivity`. By
the time `RingingActivity` called `readPersisted(id)`, the row
was gone — so the first snooze tap on a one-shot became a silent
no-op (the data wasn't there to recompute the snooze fire time).

Fix: `AlarmReceiver` no longer calls `cancel` for one-shots. The
cleanup is now the sole responsibility of
`RingingActivity.dismissAlarm` (see BUG C).

### BUG B — Self-reschedule reset `currentSnoozeCount` on every fire

`AlarmReceiver.rescheduleOrCleanup` always set
`currentSnoozeCount = 0` when re-arming a repeating alarm. The
snooze follow-up fire went through the same path, so a snooze tap
also reset the count — making `maxSnoozeCount` effectively
unreachable (every fire, including snooze fires, started at 0).

Fix: the receiver now skips `rescheduleOrCleanup` entirely on
snooze fires. The discriminator is a new
`isSnoozeFire: Boolean` field on `AlarmData` (non-persisted) and a
new `EXTRA_IS_SNOOZE_FIRE` Intent extra. `RingingActivity.scheduleSnooze`
passes `isSnoozeFire = true`; every other call site (Dart
schedule, BootReceiver, receiver natural fire) defaults to false.

`isSnoozeFire` is intentionally **not** persisted: if the device
reboots mid-snooze, BootReceiver re-arms the alarm at its natural
time, which is the correct behavior.

### BUG C — Dismiss button didn't cancel the PendingIntent

`RingingActivity`'s dismiss button only called
`stopAlarmService()`. It did not cancel the AlarmManager
PendingIntent, did not remove the persisted data, and did not
re-schedule the next fire for repeating alarms. So a dismissed
alarm would silently ring again the next day.

Fix: new private `RingingActivity.dismissAlarm(alarmId)` helper
called from the dismiss button **before** `stopAlarmService`:
- One-shot: `AlarmScheduler.cancel(this, alarmId)` (removes
  data + PendingIntent)
- Repeating: re-schedules the next natural fire with
  `currentSnoozeCount = 0` via `NextAlarmTime.compute`
- If data is already missing (defensive): logs and no-ops

### BUG D — `cancel()` did not match the scheduled PendingIntent's identity

While testing the toggle-off path I noticed
`AlarmScheduler.cancel` logged "No PendingIntent to cancel for
id=… (not scheduled?)" even though the alarm was still in
`dumpsys alarm`. The cancel-side Intent was constructed with only
the component — no action, no data URI — so
`PendingIntent.filterEquals` returned null.

`buildFireIntent` sets both `action = ACTION_FIRE_ALARM` and
`data = Uri.parse("wakey://alarm/<id>")` per alarm. The cancel
Intent now mirrors both. After the fix, the next manual toggle-off
removed the alarm from `dumpsys alarm` as expected.

## Other Iter-1 wrap-up changes

- `AndroidManifest.xml`: declared `<receiver android:name=".AlarmReceiver" android:enabled="true" android:exported="true" />`
  (this is the receiver AlarmManager dispatches to; without it the
  native side is dead). This was the missing piece that made
  on-device testing possible.
- `AlarmService.onStartCommand`: now also calls
  `startActivity(intent)` directly, in addition to setting
  `fullScreenIntent` on the notification. Required because
  Android 12+ silently strips `fullScreenIntent` from notifications
  when the app is already in the foreground; the direct launch
  is the only reliable way to surface the ringing UI.
- `MainActivity`: `EventChannel.onListen` now wires the native
  `AlarmEventBus` singleton into Dart, so dismiss / snooze
  outcomes (via the new `dismissAlarm` helper) propagate back to
  the `ringingAlarmIdProvider` on `AlarmsScreen`.
- New Dart unit tests:
  `test/native_bridge/alarm_bridge_pick_ringtone_test.dart`,
  `test/presentation/providers/ringing_alarm_provider_test.dart`.
- Extended `alarms_screen_test.dart` and `edit_alarm_screen_test.dart`
  with ringing-banner + ringtone-picker coverage.

## Verification

- `flutter analyze` — clean (only the 3 pre-existing
  `test/` warnings that are explicitly out of scope).
- `dart format` — clean.
- `flutter test` — 59 pass, 7 pre-existing failures (same as
  before this commit).
- Manual on-device: T1 (basic fire), T1-dismiss, T3 (snooze)
  all pass against a release APK built from these changes. T2
  (force-kill survival), T4 (boot survival), T5 (repeating),
  T6 (lock-screen), T7 (debug commands) are deferred to the
  post-Iter-1 verification window.

## Files changed

- `android/app/src/main/AndroidManifest.xml` — receiver declaration
- `android/app/src/main/kotlin/com/wakeywakey/app/AlarmReceiver.kt` — EXTRA_IS_SNOOZE_FIRE, skip cleanup for snooze fires
- `android/app/src/main/kotlin/com/wakeywakey/app/AlarmScheduler.kt` — isSnoozeFire field + parameter, cancel identity fix
- `android/app/src/main/kotlin/com/wakeywakey/app/AlarmService.kt` — direct startActivity in addition to fullScreenIntent
- `android/app/src/main/kotlin/com/wakeywakey/app/RingingActivity.kt` — dismissAlarm helper, snooze passes isSnoozeFire=true
- `android/app/src/main/kotlin/com/wakeywakey/app/MainActivity.kt` — EventChannel binding
- `lib/native_bridge/alarm_bridge.dart` — alarmEvents stream
- `lib/presentation/providers/alarms_provider.dart` — ringingAlarmIdProvider
- `lib/presentation/screens/alarms_screen.dart` — ringing banner
- `lib/presentation/screens/edit_alarm_screen.dart` — pickRingtone
- `test/native_bridge/alarm_bridge_pick_ringtone_test.dart` — new
- `test/presentation/providers/ringing_alarm_provider_test.dart` — new
- `test/presentation/screens/alarms_screen_test.dart` — extended
- `test/presentation/screens/edit_alarm_screen_test.dart` — extended
