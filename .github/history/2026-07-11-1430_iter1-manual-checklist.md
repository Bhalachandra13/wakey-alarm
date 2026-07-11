# Iteration 1: Manual On-Device Verification Checklist (Normal Alarm)

**Date:** 2026-07-11
**Iteration:** 1
**Target:** Android device or emulator (minSdk 26, recommended API 30+)
**APK:** `build/app/outputs/flutter-apk/app-release.apk` (51.1 MB, built
2026-07-11 14:04 — see `.github/history/2026-07-11-1404_iter1-apk-built.md`)

---

## Overview

These checks cover everything the native alarm pipeline (Iter 1) is
responsible for: `AlarmManager.setAlarmClock()` scheduling,
`AlarmReceiver` broadcast handling, `AlarmService` foreground service
for sound + vibration, full-screen `RingingActivity`, snooze/dismiss
outcomes, **and** the cross-process survival guarantees
(force-kill, reboot, lock screen) that an alarm app *must* get right.

Each check has explicit `adb` commands to inspect system state
before/after — please run them and include the output in your
report. **These cannot be automated** because they depend on real
device hardware, wall-clock time, and user interaction.

Once all checks pass, report the results and we close Iteration 1.

---

## Pre-flight (one-time)

```bash
# In WSL:
cd /mnt/d/Hobby_Project/wakey-alarm
adb devices                          # confirm device is attached
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell pm grant com.wakeywakey.app android.permission.POST_NOTIFICATIONS
adb shell pm grant com.wakeywakey.app android.permission.SCHEDULE_EXACT_ALARM
adb shell pm grant com.wakeywakey.app android.permission.VIBRATE
```

> If `SCHEDULE_EXACT_ALARM` grant fails, open
> **Settings → Apps → Special access → Alarms & reminders → wakey-wakey**
> and toggle it on. This is normal on API 31+ devices.

```bash
# Tail logs while testing:
adb logcat -c                       # clear ring buffer
adb logcat | grep -E "WakeyAlarm|AlarmReceiver|AlarmService|RingingActivity|AlarmScheduler|BootReceiver"
```

Keep the `adb logcat` tail running in a separate terminal throughout
the session.

---

## Check 1: Schedule + Fire (one-shot alarm)

**What this tests:** The full happy path for a single-fire alarm —
Dart → MethodChannel → AlarmScheduler → AlarmManager.setAlarmClock
→ AlarmReceiver → AlarmService → RingingActivity.

### Steps

1. **Schedule an alarm 2 minutes in the future**
   - Open the app → Alarms tab → "Add alarm"
   - Set time to current time + 2 minutes
   - Label: `Iter1 one-shot`
   - Repeat: **none** (weekdays/MWF/etc. all unchecked)
   - Snooze duration: 5 minutes (default)
   - Save the alarm

2. **Verify the alarm is registered with AlarmManager**
   ```bash
   adb shell dumpsys alarm | grep -A 2 "wakeywakey"
   ```
   You should see an entry with `tag=*walarm*:com.wakeywakey.app/.AlarmReceiver`
   and a `when=` field ≈ your scheduled time.

3. **Verify the alarm is persisted to SharedPreferences**
   ```bash
   adb shell run-as com.wakeywakey.app cat shared_prefs/wakey_alarms.xml
   ```
   You should see a `<string name="alarms">[...]</string>` entry
   containing the alarm's id, time, label, and a non-empty `repeatDays` array.

4. **Wait for the alarm to fire**
   - At the scheduled time, the device should:
     - Play the default alarm sound
     - Vibrate (if `vibrate: true` is the default)
     - Show a foreground service notification
       (swipe down from top — should see "Wakey Alarm" with a stop action)
     - Launch `RingingActivity` full-screen showing the label
       and Snooze/Dismiss buttons

5. **In logcat, confirm the chain ran**
   You should see, in order:
   ```
   AlarmReceiver: Received broadcast for alarm id=N
   AlarmService: Starting foreground for alarm id=N
   RingingActivity: Showing ringing UI for alarm id=N
   ```

6. **Tap Dismiss**
   - Sound and vibration stop
   - RingingActivity closes
   - AlarmService notification disappears (swipe down — gone)
   - `adb shell dumpsys alarm | grep wakeywakey` → no entry
   - `adb shell run-as com.wakeywakey.app cat shared_prefs/wakey_alarms.xml` →
     the alarm is no longer in the JSON array (one-shot was cleaned up)

### Acceptance Criteria

- [x/☐] Alarm fires within ±2 seconds of scheduled time
- [x/☐] Sound plays, vibrates, full-screen activity appears
- [x/☐] Dismiss button stops everything and removes the alarm
- [x/☐] No crash, no ANR, no duplicate fires

---

## Check 2: Schedule + Fire (repeating alarm)

**What this tests:** `AlarmReceiver.onReceive` correctly
re-schedules the *next* occurrence for a repeating alarm and
does **not** clean it up from persistence.

### Steps

1. **Schedule a repeating alarm for 1 minute from now**
   - Add alarm: time = now + 1 minute
   - Label: `Iter1 repeat`
   - Repeat: **Mon, Tue, Wed, Thu, Fri** (weekdays)
   - Save

2. **Verify it's in AlarmManager**
   ```bash
   adb shell dumpsys alarm | grep -A 2 "wakeywakey"
   ```
   `when=` should be ≈ now + 60s.

3. **Let it fire**
   - RingingActivity appears, sound + vibration
   - Tap **Dismiss** (NOT snooze)

4. **Verify the next occurrence is scheduled**
   ```bash
   adb shell dumpsys alarm | grep -A 2 "wakeywakey"
   ```
   `when=` should now be ≈ next weekday 7:00 AM (or whatever HH:MM
   you set), **not** the original fire time. The alarm was
   self-rescheduled by `AlarmReceiver` before completing.

5. **Verify the alarm is still persisted**
   ```bash
   adb shell run-as com.wakeywakey.app cat shared_prefs/wakey_alarms.xml
   ```
   The `Iter1 repeat` entry should still be present (with the
   same id, time, repeatDays). One-shots are cleaned; repeats
   are not.

6. **Cleanup:** Delete the alarm from the UI, verify
   `dumpsys alarm` and `shared_prefs` are both empty for the
   alarm entry.

### Acceptance Criteria

- [x/☐] Repeating alarm re-schedules itself after firing
- [x/☐] Dismissing a repeating alarm does **not** delete it
  from persistence
- [x/☐] `dumpsys alarm` shows the next occurrence (not the past one)
- [x/☐] Manually deleting the alarm cleans up both AlarmManager
  and SharedPreferences

---

## Check 3: Snooze

**What this tests:** Snooze stops the current ring, reschedules
the same alarm for `now + snoozeDuration`, and the snoozed alarm
correctly fires again.

### Steps

1. **Schedule an alarm 1 minute from now**
   - Label: `Iter1 snooze`
   - Repeat: **none**
   - Snooze duration: **1 minute** (so the test runs quickly)

2. **When it fires, tap Snooze**
   - Sound + vibration stop
   - RingingActivity closes
   - AlarmService notification disappears

3. **Verify the snoozed alarm is scheduled**
   ```bash
   adb shell dumpsys alarm | grep -A 2 "wakeywakey"
   ```
   `when=` should be ≈ now + 60s (snooze duration).

4. **Wait for the snoozed fire**
   - RingingActivity reappears, sound + vibration
   - This time tap **Dismiss**

5. **Verify one-shot is now cleaned up**
   ```bash
   adb shell dumpsys alarm | grep wakeywakey
   adb shell run-as com.wakeywakey.app cat shared_prefs/wakey_alarms.xml
   ```
   Both should be empty for the `Iter1 snooze` id.

### Acceptance Criteria

- [x/☐] Snooze stops current ring immediately
- [x/☐] Snoozed alarm fires after the snooze interval
- [x/☐] Dismissing the snoozed fire cleans up the one-shot
- [x/☐] No duplicate fires during the snooze window

### Known gap

There is **no max-snooze-count enforcement** in Iter 1. If you
snooze 10 times in a row, all 10 will fire. This is on the
follow-up list and explicitly out of scope for Iter 1 — but
worth knowing if you observe it.

---

## Check 4: Survive force-kill

**What this tests:** Because the alarm is registered with the
*system* `AlarmManager` (not the app process), force-killing
the app must not prevent the alarm from firing.

### Steps

1. **Schedule an alarm 1 minute from now** (one-shot, any label)

2. **Immediately force-kill the app**
   ```bash
   adb shell am force-stop com.wakeywakey.app
   adb shell ps -A | grep wakeywakey   # should be empty
   ```

3. **Wait for the scheduled fire time**
   - RingingActivity should still appear
   - Sound + vibration should still play
   - In logcat, the first line should be:
     ```
     AlarmReceiver: Process restarted, alarm id=N
     ```
     This confirms the app process was cold-started by the
     broadcast.

4. **Tap Dismiss to clean up**

### Acceptance Criteria

- [x/☐] Alarm fires despite the app being force-killed
- [x/☐] Cold-start path (process restart) works
- [x/☐] No "app not responding" or "alarm missed" error

---

## Check 5: Survive reboot

**What this tests:** `BootReceiver` correctly re-arms all
persisted alarms after the device boots.

### Steps

1. **Schedule 2 alarms**
   - Alarm A: 8:00 AM, weekdays, label `Iter1 reboot-A`
   - Alarm B: 9:00 PM, daily (every day), label `Iter1 reboot-B`

2. **Verify both are registered before reboot**
   ```bash
   adb shell dumpsys alarm | grep -c wakeywakey
   # Should print 2
   ```

3. **Reboot the device**
   ```bash
   adb reboot
   ```
   Wait for the device to fully boot (watch the lock screen appear).

4. **Confirm BootReceiver ran**
   ```bash
   adb logcat -d | grep BootReceiver
   ```
   You should see:
   ```
   BootReceiver: BOOT_COMPLETED received, re-arming N persisted alarms
   ```
   (or similar — exact log line depends on the BootReceiver impl)

5. **Verify both alarms are re-armed**
   ```bash
   adb shell dumpsys alarm | grep -c wakeywakey
   # Should print 2
   ```
   Each entry's `when=` should be the next valid fire time for
   that alarm's repeat rule (e.g. next weekday 8:00 AM for A).

6. **Cleanup:** Delete both alarms from the UI.

### Acceptance Criteria

- [x/☐] `BootReceiver` logs show it ran on boot
- [x/☐] Both alarms are re-armed with correct next-fire times
- [x/☐] One-shots scheduled in the past relative to boot time
  are **not** re-armed (they were already fired or expired)

### Variants to try

- **QUICKBOOT_POWERON:** Only relevant on HTC devices. If you
  don't have one, skip this — covered indirectly by the
  BOOT_COMPLETED test.
- **MY_PACKAGE_REPLACED:** Install an updated APK over the
  current one (`adb install -r ...`) and check that alarms
  persist. They should — this is the same code path as
  BOOT_COMPLETED.

---

## Check 6: Lock screen / screen-off

**What this tests:** `RingingActivity` is set up to appear
full-screen on top of the lock screen, and the alarm fires
even when the device is locked and the screen is off.

### Steps

1. **Schedule an alarm 1 minute from now** (one-shot)

2. **Lock the device and turn off the screen**
   ```bash
   adb shell input keyevent KEYCODE_POWER   # turn off screen
   ```
   (Or just press the power button.)

3. **Wait for the fire time**
   - Screen should turn on automatically
   - Lock screen should be bypassed
   - RingingActivity should appear in front of the lock screen
   - On API 27+ this uses `setShowWhenLocked(true)` and
     `setTurnScreenOn(true)`. On API 26, it uses
     `WindowManager.LayoutParams` flags.

4. **Tap Dismiss to clean up**

### Acceptance Criteria

- [x/☐] Alarm fires when screen is off and device is locked
- [x/☐] RingingActivity appears in front of lock screen
- [x/☐] No "press power button to see alarm" extra step
- [x/☐] Sound + vibration play (the audio stream is not muted
  by the lock screen)

### Note

On some OEM ROMs (Xiaomi MIUI, Huawei EMUI) the
"auto-unlock on alarm" behavior is gated by a separate
permission (e.g. "Display pop-up window" / "Show on
lock screen"). If the activity does not appear, check
**Settings → Apps → wakey-wakey → Other permissions** and
enable "Display pop-up window" / "Show on lock screen".

---

## Check 7: Permission denial / missing SCHEDULE_EXACT_ALARM

**What this tests:** Graceful handling when the user has not
granted `SCHEDULE_EXACT_ALARM` (or has revoked it).

### Steps

1. **Revoke the permission**
   ```bash
   adb shell pm revoke com.wakeywakey.app android.permission.SCHEDULE_EXACT_ALARM
   ```

2. **Try to schedule a new alarm in the app**
   - The app should display a clear message: "Wakey-Wakey needs
     the Alarms & reminders permission to schedule alarms."
     (or similar — exact copy depends on UI implementation)
   - Tapping the message should open
     **Settings → Apps → Special access → Alarms & reminders**

3. **Grant the permission, return to the app, retry**
   - Alarm should schedule successfully
   - No crash at any point

4. **Test USE_EXACT_ALARM (API 33+ fallback)**
   - `USE_EXACT_ALARM` is granted automatically at install
     on API 33+ (it's a normal permission there, not a
     special-access one). The app should fall back to
     `USE_EXACT_ALARM` if `SCHEDULE_EXACT_ALARM` is denied
     and the device is API 33+.

### Acceptance Criteria

- [x/☐] Missing permission → clear UI message, no crash
- [x/☐] Settings deep link works
- [x/☐] Grant → retry → alarm schedules
- [x/☐] API 33+ path uses `USE_EXACT_ALARM` automatically

---

## Check 8: Disable / enable / delete from UI

**What this tests:** All CRUD operations on the alarm
correctly propagate to AlarmManager and SharedPreferences.

### Steps

1. **Schedule an alarm 5 minutes in the future**

2. **Disable it** (toggle in UI)
   ```bash
   adb shell dumpsys alarm | grep wakeywakey
   # Should be empty — disabled alarms are removed from AlarmManager
   ```
   ```bash
   adb shell run-as com.wakeywakey.app cat shared_prefs/wakey_alarms.xml
   # Should still contain the alarm (so it can be re-enabled)
   ```

3. **Re-enable it**
   ```bash
   adb shell dumpsys alarm | grep wakeywakey
   # Should show the alarm again
   ```

4. **Delete it**
   ```bash
   adb shell dumpsys alarm | grep wakeywakey
   adb shell run-as com.wakeywakey.app cat shared_prefs/wakey_alarms.xml
   # Both empty for this id
   ```

### Acceptance Criteria

- [x/☐] Disable removes from AlarmManager but keeps in persistence
- [x/☐] Re-enable re-registers with AlarmManager
- [x/☐] Delete removes from both

---

## Check 9: Sound + vibration

**What this tests:** `vibrate: true/false` and the system
ringtone choice are honored.

### Steps

1. **Schedule an alarm 1 minute from now, `vibrate: true`**
   - Confirm vibration fires (you should feel the device buzz)

2. **Schedule an alarm 1 minute from now, `vibrate: false`**
   - Confirm no vibration fires
   - Sound should still play

3. **Sound selection**
   - If the UI exposes a sound picker, choose a custom sound
     and verify it plays
   - If not, the default alarm sound is acceptable (system
     default) — flag this for Iter 2

### Acceptance Criteria

- [x/☐] `vibrate: true` → device vibrates
- [x/☐] `vibrate: false` → no vibration
- [x/☐] Default sound plays correctly

---

## Check 10: `adb` debug commands reference

Quick reference for digging into issues during testing:

```bash
# All currently scheduled alarms for the app
adb shell dumpsys alarm | grep -B 1 -A 5 wakeywakey

# All SharedPreferences (incl. alarm persistence)
adb shell run-as com.wakeywakey.app ls shared_prefs/
adb shell run-as com.wakeywakey.app cat shared_prefs/wakey_alarms.xml

# Live logs (filter to our app)
adb logcat -c
adb logcat | grep -E "WakeyAlarm|AlarmReceiver|AlarmService|RingingActivity|AlarmScheduler|BootReceiver|AlarmManager"

# Force-stop the app (to test cold-start path)
adb shell am force-stop com.wakeywakey.app

# Reset all permissions (to test grant flows)
adb shell pm reset-permissions com.wakeywakey.app

# Reinstall the APK cleanly
adb uninstall com.wakeywakey.app
adb install build/app/outputs/flutter-apk/app-release.apk

# Inspect FGS state (foreground service notification)
adb shell dumpsys activity services com.wakeywakey.app | head -40
```

---

## How to Report Results

For each check, note pass (✅) or fail (❌) with details.
If a check fails, attach:

- Device info: Android version (`adb shell getprop ro.build.version.release`),
  API level (`adb shell getprop ro.build.version.sdk`),
  device model, real vs emulator.
- The relevant `adb logcat` snippet (last 30 lines before the failure).
- The relevant `adb shell dumpsys alarm | grep wakeywakey` output.
- Steps to reproduce.

### Example Report

```
✅ Check 1 (Schedule + Fire one-shot): PASS
   - Device: Pixel 6 (API 33, Android 13)
   - Alarm scheduled for 14:30, fired at 14:30:01 (±1s)
   - RingingActivity appeared full-screen with "Iter1 one-shot" label
   - Sound + vibration played, dismiss cleaned up AlarmManager + prefs
   - logcat snippet: [attach last 30 lines]

✅ Check 2 (Repeating): PASS
   - Weekday alarm fired once, next fire time re-registered for tomorrow
   - shared_prefs still contains the alarm entry after dismiss

❌ Check 5 (Reboot): FAIL
   - BootReceiver did not re-arm Alarm B
   - logcat: [attach snippet]
   - dumpsys alarm: [empty]
   - shared_prefs: [contains both alarms]
   - Steps: scheduled both, rebooted, only A was re-armed

(etc.)
```

---

## Next Steps After All Checks Pass

1. Update `docs/workflow_plan.md` to mark all Iter 1 tasks done
   (the assistant will do this in a follow-up commit).
2. The `[Iter1] Complete Iteration 1 Definition of Done`
   commit closes the iteration.
3. Iteration 2 (Stopwatch) becomes the next open iteration.

If any check fails, the relevant code path is the first place to
look — none of these checks are checking *new* behavior beyond
what was already committed in Iter 1, so a failure indicates a
real bug in the recently-added native code.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| Alarm doesn't fire on time | Check `dumpsys alarm` shows the entry; check logcat for `AlarmReceiver`; OEM battery optimization may be delaying — see `Check 6` note |
| RingingActivity doesn't appear on lock screen | OEM permission (MIUI "Display pop-up window", EMUI "Show on lock screen") — see `Check 6` |
| `run-as` returns "package not debuggable" | The release APK is signed with the debug keystore but not declared `android:debuggable="true"`. Use `adb shell run-as` only if your release build has `debuggable=true`, or fall back to `adb shell` and use `cat` with the file directly (may need root). |
| `dumpsys alarm` output is huge | Pipe to `grep -B 1 -A 5 wakeywakey` to filter to our entries only |
| SharedPreferences file doesn't exist | The app has not yet saved any alarm — create one and try again |
| Alarm fires but sound is silent | Media volume is 0, or device is in Do Not Disturb mode that mutes alarms. Check `Settings → Sound → Do Not Disturb` |
| App crashes on launch after install | Check `adb logcat -d | grep AndroidRuntime` for the stack trace; the most common cause is a manifest/permission mismatch |
| `BootReceiver` doesn't run on reboot | Some OEMs (Xiaomi, Huawei, OPPO) delay or block BOOT_COMPLETED broadcasts to background apps. The user may need to enable "Auto-start" for the app in the OEM settings. |

---

## Known Iter 1 Gaps (Not Blocking)

These are explicitly out of scope for Iter 1 and should NOT be
reported as failures. They are on the follow-up list:

1. **No snooze max-count enforcement** (Check 3 note)
2. **No custom sound picker UI** — the default system ringtone
   is used unless a sound URI is hardcoded (Check 9)
3. **No Dart-side consumer of the `alarmEvents` stream** — the
   bus is wired up but the `AlarmsNotifier` does not yet
   subscribe. UI does not show "alarm is currently ringing"
   state. (Infrastructure is in place for Iter 1.5 / 2.)
4. **No `LOCKED_BOOT_COMPLETED` handling** — alarms are
   re-armed after user unlock, not before. This is acceptable
   for an alarm clock (no one expects an alarm to fire while
   the device is still in the direct-boot phase), but worth
   knowing.
