# Iteration 1 — Bug Registry (Post On-Device Bugfix Review)

- **Date:** 2026-07-20
- **Iteration:** 1
- **Scope:** Normal alarm feature (time-based alarms)
- **Status:** 5 bugs fixed, 3 known gaps / open issues tracked

This document is a consolidated register of the bugs discovered during the
Iteration 1 implementation and on-device verification of the normal alarm
feature. It pulls together the individual bug-fix histories into one
reference and adds the remaining known gaps so the next iteration has a clear
list of what is and isn't yet solved.

---

## 1. Executive Summary

The Iteration 1 alarm pipeline went through an end-to-end on-device test pass
on 2026-07-19 against a release APK on a Pixel 8. The test surfaced five
correlated defects in the native `AlarmManager` → `BroadcastReceiver` →
foreground `Service` → full-screen `Activity` flow, plus the Dart-side mirror
used by the alarms list. All five were fixed before the iteration was
marked code-complete.

Two major non-blocking gaps remain for Iteration 2 / 3 follow-up, and a
third smaller gap is documented below. Iteration 1 is **not** fully closed
until the manual on-device checklist in
[docs/workflow_plan.md](../docs/workflow_plan.md) and
`.github/history/2026-07-11-1430_iter1-manual-checklist.md` is physically
run and signed off.

---

## 2. Fixed Bugs

### BUG A — Receiver cancelled one-shot alarm data before snooze could read it

| Field | Value |
|---|---|
| **Severity** | High (snooze silently broken on one-shots) |
| **Discovered** | 2026-07-19, on-device manual test |
| **Fixed in** | `2b8028c` |
| **Detailed history** | `.github/history/2026-07-19-1929_iter1-snooze-dismiss-cancel-bugfixes.md` |

**Symptom:** Tapping snooze on a one-shot alarm appeared to do nothing. The
ringing stopped, but no follow-up fire occurred.

**Root cause:** `AlarmReceiver.onReceive` was calling `AlarmScheduler.cancel`
for every one-shot natural fire, which removes the persisted
`SharedPreferences` row. The receiver runs before `RingingActivity` is
visible, so by the time the user tapped snooze, the data needed to compute
the snooze fire time (including `currentSnoozeCount`) was already gone.

**Fix:** `AlarmReceiver` no longer cleans up one-shots. The cleanup is now
deferred to `RingingActivity.dismissAlarm`, which runs only when the user
taps **Dismiss**. For a one-shot, that helper then calls
`AlarmScheduler.cancel`. The snooze path now has the full `AlarmData` object
available.

**Files touched:** `AlarmReceiver.kt`, `RingingActivity.kt`

**Verification:** `flutter test` (59 pass) + on-device T1 (basic fire) and
T3 (snooze) confirmed the fix.

---

### BUG B — Self-reschedule reset `currentSnoozeCount` on every fire

| Field | Value |
|---|---|
| **Severity** | Medium (snooze limit never enforced) |
| **Discovered** | 2026-07-19, on-device manual test |
| **Fixed in** | `2b8028c` |
| **Detailed history** | `.github/history/2026-07-19-1929_iter1-snooze-dismiss-cancel-bugfixes.md` |

**Symptom:** `maxSnoozeCount` had no effect. The user could snooze
indefinitely, even when a limit was configured.

**Root cause:** `AlarmReceiver.rescheduleOrCleanup` was unconditionally
resetting `currentSnoozeCount = 0` when re-arming a repeating alarm. Because
a snooze follow-up fire also went through `rescheduleOrCleanup`, the count
was reset to zero on every fire, including snooze fires.

**Fix:** Introduced a new `isSnoozeFire` flag:
- Added to `AlarmData` (non-persisted, defaults to `false`).
- Threaded through `AlarmScheduler.schedule(..., isSnoozeFire)`.
- Stored in the fire Intent as `EXTRA_IS_SNOOZE_FIRE`.
- `RingingActivity.scheduleSnooze` sets it to `true`.
- `AlarmReceiver.onReceive` now skips `rescheduleOrCleanup` entirely for
  snooze fires, leaving the persisted count untouched.

The flag is intentionally **not** persisted so that a reboot mid-snooze
re-arms the alarm at its natural time with a fresh snooze budget.

**Files touched:** `AlarmScheduler.kt`, `AlarmReceiver.kt`, `RingingActivity.kt`

**Verification:** `flutter test` + on-device snooze test.

---

### BUG C — Dismiss button did not cancel the AlarmManager PendingIntent

| Field | Value |
|---|---|
| **Severity** | High (dismissed alarms silently re-fired) |
| **Discovered** | 2026-07-19, on-device manual test |
| **Fixed in** | `2b8028c` |
| **Detailed history** | `.github/history/2026-07-19-1929_iter1-snooze-dismiss-cancel-bugfixes.md` |

**Symptom:** Tapping dismiss on a one-shot alarm stopped the ringing, but the
alarm would fire again the next time the app was re-scheduled or the device
rebooted, because the `PendingIntent` was still registered with
`AlarmManager`.

**Root cause:** `RingingActivity`'s dismiss button only called
`stopAlarmService()`. It did not cancel the AlarmManager `PendingIntent`,
remove the persisted `SharedPreferences` row, or re-schedule the next natural
fire for repeating alarms.

**Fix:** Added a private `dismissAlarm(alarmId)` helper in
`RingingActivity` that is called before the service is stopped:
- **One-shot:** calls `AlarmScheduler.cancel(context, alarmId)`, which both
  cancels the `PendingIntent` and removes the persisted data.
- **Repeating:** re-schedules the next natural fire using
  `NextAlarmTime.compute` and resets `currentSnoozeCount = 0`.
- **Defensive:** if no persisted data exists, it logs and no-ops.

**Files touched:** `RingingActivity.kt`, `AlarmScheduler.kt`

**Verification:** `flutter test` + on-device dismiss test.

---

### BUG D — `AlarmScheduler.cancel()` did not match the scheduled PendingIntent

| Field | Value |
|---|---|
| **Severity** | High (toggle-off / delete left stale alarms in `AlarmManager`) |
| **Discovered** | 2026-07-19, while testing BUG C toggle-off path |
| **Fixed in** | `2b8028c` |
| **Detailed history** | `.github/history/2026-07-19-1929_iter1-snooze-dismiss-cancel-bugfixes.md` |

**Symptom:** Toggling an alarm off or deleting it still showed the alarm in
`dumpsys alarm`. Logcat reported
`No PendingIntent to cancel for id=... (not scheduled?)` even though the
alarm was scheduled.

**Root cause:** `PendingIntent.filterEquals` compares the action and data
URI, not just the component class. `AlarmScheduler.schedule` builds the fire
Intent with `action = ACTION_FIRE_ALARM` and `data = wakey://alarm/<id>`.
The original `cancel()` implementation constructed an Intent with only the
component class, so `filterEquals` did not match the scheduled one.

**Fix:** `AlarmScheduler.cancel()` now reconstructs the cancel Intent with the
same action and per-alarm data URI used at schedule time:

```kotlin
Intent(context, AlarmReceiver::class.java).apply {
    action = ACTION_FIRE_ALARM
    data = Uri.parse("wakey://alarm/$alarmId")
}
```

After the fix, `dumpsys alarm` no longer shows the alarm after a toggle-off.

**Files touched:** `AlarmScheduler.kt`

**Verification:** `dumpsys alarm | grep wakeywakey.app` before/after
fix + automated test.

---

### BUG E — Native dismiss did not update the Dart sqflite mirror

| Field | Value |
|---|---|
| **Severity** | High (UI drift after dismiss; alarm resurrected on re-open) |
| **Discovered** | 2026-07-19, while re-testing dismiss after fixing BUG D |
| **Fixed in** | `550ae30` |
| **Detailed history** | `.github/history/2026-07-19-1939_iter1-buge-native-dismiss-mirror.md` |

**Symptom:** After dismissing a one-shot alarm, the AlarmsScreen still
showed the alarm with the switch on. On a cold re-open, the alarm
resurrected because `rescheduleAllPersisted` re-read it from sqflite.

**Root cause:** The native side is the source of truth for the *running*
alarm (PendingIntent, sound, foreground service, ringing UI), while the
Dart side owns the sqflite mirror used to render the AlarmsScreen. The
EventChannel was wired to a `ringingAlarmIdProvider` for the ringing banner,
but the data provider (`AlarmsNotifier`) was never told that a dismiss had
occurred, so the sqflite row drifted.

**Fix:** `AlarmsNotifier` now subscribes to `alarmEventsProvider` and mirrors
the native decision:
- `AlarmEventType.snoozed` → `ref.invalidateSelf()` (native already
  re-scheduled; the row's natural time is still correct).
- `AlarmEventType.dismissed` → `_onNativeDismiss(alarmId)`:
  - If the row is already gone, no-op.
  - If the alarm is repeating, just refresh (native already re-armed the
    next natural fire).
  - Otherwise, delete the row from sqflite and refresh.

**Files touched:** `lib/presentation/providers/alarms_provider.dart`

**Verification:** On-device dismiss test — after tap, alarm is removed from
AlarmsScreen and does not resurrect after force-stop + re-open.

---

## 3. Critical Non-Code Issues Found During Bugfix Work

Two non-code problems were discovered alongside the functional bugs and are
documented here because they are prerequisites for any further on-device
verification.

### Manifest: AlarmReceiver was undeclared

**Severity:** Critical. Without the receiver, the entire native pipeline is
inert.

`AlarmReceiver` is the entry point for `AlarmManager.setAlarmClock()` fires.
The original manifest did not contain a `<receiver>` declaration for it, so
`AlarmManager` could never dispatch the alarm. This was added in `2b8028c`:

```xml
<receiver android:name=".AlarmReceiver" android:enabled="true" android:exported="true" />
```

### AlarmService: full-screen Intent dropped on Android 12+ when app is foreground

**Severity:** High. The ringing activity could not appear reliably.

On Android 12+ (API 31+), the system strips the `fullScreenIntent` from a
notification if the app is already in the foreground. `AlarmService` now
also calls `startActivity(intent)` directly to surface `RingingActivity`.

---

## 4. Known Gaps / Open Issues (Not Blockers for Iteration 1)

These are tracked but intentionally out of scope for Iteration 1 unless the
manual verification checklist reveals them as blockers.

### GAP 1 — `maxSnoozeCount` is only enforced on a per-fire cycle basis

**Status:** Open (deferred to Iteration 2)

The native side now reads and enforces `maxSnoozeCount` correctly:
- `RingingActivity.scheduleSnooze` checks
  `data.currentSnoozeCount >= maxSnoozeCount`.
- A snooze that hits the limit is treated as a dismiss.

However, the value is currently hard-coded / read from the alarm payload but
there is no UI to configure it in `EditAlarmScreen`. The UI only exposes
`snoozeDurationMin`. This is aligned with the current deferral in
[docs/workflow_plan.md](../docs/workflow_plan.md), which notes that the max
snooze count is "read from extras but not yet enforced." The enforcement is
now done; the UI control remains deferred.

### GAP 2 — No alarm sound picker UI

**Status:** Open (deferred to Iteration 2)

The native `AlarmService` falls back to `RingtoneManager.getDefaultUri(TYPE_ALARM)`
when no `soundUri` is provided. The sqflite schema and `AlarmData` model both
support a custom sound URI, and the native `AlarmService` accepts one, but
`EditAlarmScreen` does not provide a way to pick it. The ringtone picker
MethodChannel method `pickRingtone` exists on the Dart side and is tested in
`test/native_bridge/alarm_bridge_pick_ringtone_test.dart`, but it is not yet
wired into the UI.

### GAP 3 — workflow_plan.md still lists "no Dart-side consumer of alarmEvents" as a gap

**Status:** Documentation stale

[docs/workflow_plan.md](../docs/workflow_plan.md) §Iteration 1 Known Gaps
lists: "No Dart-side consumer of the `alarmEvents` stream." This is now
incorrect — both `ringingAlarmIdProvider` and `AlarmsNotifier` consume the
stream. The file should be updated to remove or rephrase this item.

### GAP 4 — Seven pre-existing test warnings/failures

**Status:** Open (explicitly out of scope per AGENTS.md)

- `test/presentation/providers/alarms_provider_test.dart` has analyzer
  warnings and is missing `TestWidgetsFlutterBinding.ensureInitialized()`.
- 7 pre-existing `flutter test` failures/warnings are noted as out of scope.

These do not block the alarm feature, but they should be cleaned up before
Iteration 2 starts so the automated DoD is truly green.

---

## 5. Test and Verification Status

| Check | Status | Notes |
|---|---|---|
| `flutter analyze` | Clean (only the 3 pre-existing `test/` warnings) | |
| `dart format` | Clean | |
| `flutter test` | 59 pass, 7 pre-existing failures | Same as before the bugfixes |
| On-device T1 (basic fire) | Pass | |
| On-device T1-DISMISS | Pass after BUG E | |
| On-device T3 (snooze) | Pass after BUG B | |
| Manual checklist checks T2, T4, T5, T6, T7 | Pending | See `.github/history/2026-07-11-1430_iter1-manual-checklist.md` |

---

## 6. File Map

### Native (Kotlin)
- `android/app/src/main/kotlin/com/wakeywakey/app/AlarmReceiver.kt` — BUG A, B
- `android/app/src/main/kotlin/com/wakeywakey/app/AlarmScheduler.kt` — BUG B, D
- `android/app/src/main/kotlin/com/wakeywakey/app/RingingActivity.kt` — BUG A, C
- `android/app/src/main/kotlin/com/wakeywakey/app/AlarmService.kt` — direct launch fix
- `android/app/src/main/kotlin/com/wakeywakey/app/MainActivity.kt` — EventChannel binding
- `android/app/src/main/kotlin/com/wakeywakey/app/NextAlarmTime.kt` — next-fire computation
- `android/app/src/main/AndroidManifest.xml` — receiver declaration

### Dart
- `lib/native_bridge/alarm_bridge.dart` — `alarmEvents` stream
- `lib/presentation/providers/alarms_provider.dart` — BUG E
- `lib/presentation/screens/alarms_screen.dart` — ringing banner
- `lib/presentation/screens/edit_alarm_screen.dart` — ringtone pick ground work

### Tests
- `test/native_bridge/alarm_event_test.dart`
- `test/native_bridge/alarm_bridge_pick_ringtone_test.dart`
- `test/presentation/providers/ringing_alarm_provider_test.dart`
- `test/presentation/screens/alarms_screen_test.dart`
- `test/presentation/screens/edit_alarm_screen_test.dart`

---

## 7. Recommendations for Iteration 2

1. **Fix the 7 pre-existing test warnings/failures** before adding new code.
2. **Update [docs/workflow_plan.md](../docs/workflow_plan.md)** to mark the
   `alarmEvents` consumer gap as resolved and update the Iteration 1 DoD
   status after manual verification is complete.
3. **Add the sound picker UI** and wire it to the existing `pickRingtone`
   MethodChannel so the custom `soundUri` field is actually used.
4. **Add UI for `maxSnoozeCount`** so the now-enforced native limit is
   user-configurable.
5. **Re-run the full Iteration 1 manual checklist** before moving to
   Iteration 2, especially the force-kill, reboot, and lock-screen tests.
