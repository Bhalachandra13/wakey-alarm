# Implement BootReceiver to re-schedule alarms after device reboot

- **Date:** 2026-07-11 13:55
- **Iteration:** 1
- **Commit:** <pending>

## What changed

**New file** `android/app/src/main/kotlin/com/wakeywakey/app/BootReceiver.kt`:
a `BroadcastReceiver` that on `BOOT_COMPLETED` (and a couple of
related actions) re-schedules every alarm persisted by
`AlarmScheduler`. It is a one-liner of substance:

```kotlin
val count = AlarmScheduler.rescheduleAllPersisted(context)
```

The work itself lives in `AlarmScheduler.rescheduleAllPersisted` —
it reads the JSON-encoded list from SharedPreferences, computes
the next fire time for each entry with `NextAlarmTime.compute`,
and re-arms `AlarmManager.setAlarmClock` for each.

**Manifest registration** in `AndroidManifest.xml`:
a new `<receiver android:name=".BootReceiver" android:exported="true">`
element with three intent filters:

- `android.intent.action.BOOT_COMPLETED` — the standard
  "device finished booting" broadcast.
- `android.intent.action.QUICKBOOT_POWERON` — sent by some
  OEMs (notably HTC) on a hard reboot.
- `android.intent.action.MY_PACKAGE_REPLACED` — fires when the
  app is upgraded, so re-scheduling after a Play Store update
  is also handled.

`exported="true"` is required for the system to be able to
deliver the broadcast.

## Why

Android clears all `AlarmManager` state when the device shuts
down. Without this receiver, every alarm the user had set
would silently disappear after a reboot — which is the exact
failure mode an alarm clock is supposed to prevent.

The `RECEIVE_BOOT_COMPLETED` permission was added in the
earlier manifest commit, so the receiver is already authorised
to receive the system broadcast; it just wasn't there to
receive it.

The reason `BootReceiver` reads from SharedPreferences (not
the Dart-side sqflite database) is that the Flutter engine is
*not* running when `BOOT_COMPLETED` fires — the device has
only just finished booting — so the database file may not be
unlocked, and the Dart isolate certainly isn't alive to
interpret it. SharedPreferences is available synchronously in
a `BroadcastReceiver.onReceive` and survives reboot, which is
exactly the storage profile we need.

## Files touched

- `android/app/src/main/kotlin/com/wakeywakey/app/BootReceiver.kt`
  — New.
- `android/app/src/main/AndroidManifest.xml` — registered the
  receiver with three intent filters.

## Verification

- [x] `gradle :app:processDebugMainManifest :app:compileDebugKotlin`
  — BUILD SUCCESSFUL.
- [x] Inspected the merged manifest to confirm the receiver is
  present with all three intent filters.
- [ ] Manual on-device check needed? Yes — reboot-with-alarms-
  set is the canonical test. Steps for the Iter1 verification
  checklist:
  1. Schedule a daily 7am alarm and a one-shot alarm 10 min
     from now.
  2. Wait for the one-shot to fire and dismiss/snooze it.
  3. Reboot the device.
  4. Verify the one-shot does **not** fire (it was removed by
     the `AlarmReceiver` self-reschedule path).
  5. Verify the daily 7am is still armed — easiest check is
     `adb shell dumpsys alarm | grep wakey`.

## Edge cases handled

- **OEM reboot variants** — `QUICKBOOT_POWERON` is filtered
  through and treated as equivalent to `BOOT_COMPLETED`. Some
  HTC devices (and a few others) use this action name on a
  hard reboot.
- **App upgrades** — `MY_PACKAGE_REPLACED` triggers the
  same re-schedule path. After a Play Store update, the
  user's alarms are restored even though the process was
  killed mid-install.
- **Empty persistence** — if SharedPreferences is empty
  (e.g. fresh install after a wipe), `rescheduleAllPersisted`
  returns 0 and the receiver exits cleanly without touching
  `AlarmManager`.
- **One-shot alarms** — these were already removed by
  `AlarmReceiver.rescheduleOrCleanup` when they fired, so
  `BootReceiver` won't see them. Repeating alarms are
  re-armed with `NextAlarmTime.compute(...)`, which finds
  the next matching day-of-week.

## Known gaps (still on the list)

1. **Dismiss/snooze outcomes are not yet forwarded to Dart**
   via the `EventChannel`. Next milestone.
2. **No snooze max-count enforcement.** `EXTRA_MAX_SNOOZE_COUNT`
   is propagated but not enforced.
3. **No `LOCKED_BOOT_COMPLETED` handling.** The standard
   `BOOT_COMPLETED` fires after the user has unlocked the
   device for the first time after boot, so we never need to
   worry about the credential-encrypted storage not being
   available; but it does mean alarms don't fire during the
   brief window between the system finishing boot and the
   user unlocking. This is acceptable for an alarm clock
   (the user can't be expected to act on an alarm before
   unlocking) but worth noting.
