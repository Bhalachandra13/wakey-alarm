# Register AlarmService + add FGS / VIBRATE / BOOT_COMPLETED permissions

- **Date:** 2026-07-11 13:05
- **Iteration:** 1
- **Commit:** <pending>

## What changed

`AndroidManifest.xml`:

**New permissions** (all required for the alarm pipeline to work
end-to-end on modern Android):

- `android.permission.VIBRATE` — required by `Vibrator.vibrate()` /
  `VibratorManager.defaultVibrator.vibrate()` in `AlarmService`.
- `android.permission.RECEIVE_BOOT_COMPLETED` — required by
  `BootReceiver` to fire on `BOOT_COMPLETED`. The receiver itself
  ships in a follow-up commit; the permission has to be in place
  by then or the receiver will never be invoked.
- `android.permission.FOREGROUND_SERVICE` — required (API 28+) for
  any foreground service.
- `android.permission.FOREGROUND_SERVICE_SPECIAL_USE` — required
  (API 34+) when the service is `foregroundServiceType="specialUse"`.
  Android has no dedicated "alarm" FGS type, so `specialUse` is
  the right call for an alarm clock (per the Android docs:
  https://developer.android.com/about/versions/14/changes/fgs-types-required#special-use).

**New component**: `<service android:name=".AlarmService"
android:foregroundServiceType="specialUse">` with the
mandatory `<property
android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
android:value="Alarm clock: plays ringtone and vibrates while the
user dismisses or snoozes."/>` child.

This is the single most-important change in this commit. Until
now, `AlarmReceiver.onReceive` would have called
`context.startForegroundService(...)` against an **unregistered**
service — Android would have thrown `IllegalStateException` at
runtime and no alarm could ever ring. The whole `AlarmService`
class was effectively dead code in any installed APK.

## Why

Without a registered `<service>` element, `startForegroundService`
fails on API 26+ (when foreground-service start restrictions were
introduced). Without the `VIBRATE` permission, `vibrate()` is a
silent no-op. Without `RECEIVE_BOOT_COMPLETED`, the (about-to-be-
added) `BootReceiver` is never invoked after a device reboot —
meaning the only way an alarm can fire after a reboot is if the
user opens the app, which is exactly the failure mode an alarm
clock is supposed to prevent.

## Files touched

- `android/app/src/main/AndroidManifest.xml` — permissions + service.

## Verification

- [x] `gradle :app:processDebugMainManifest` — BUILD SUCCESSFUL
- [x] Inspected the merged manifest at
  `build/app/intermediates/merged_manifest/debug/processDebugMainManifest/AndroidManifest.xml`
  to confirm all 4 new permissions and the new `<service>` element
  are present, and that the `PROPERTY_SPECIAL_USE_FGS_SUBTYPE`
  child is in the merged output.
- [ ] `flutter test` — N/A, manifest-only change
- [ ] Manual on-device check needed? Yes — confirming the
  service starts at runtime. Deferred to the Iter1 verification
  commit.
