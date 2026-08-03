# 2026-08-03 22:01 — Iter5 — geofence addGeofence DEVELOPER_ERROR fix

- **Date:** 2026-08-03 22:01
- **Iteration:** 5 (bugfix from on-device testing)
- **Commit:** *(filled in after committing)*

## Symptom
On a fresh install of the release APK on a Pixel 8, arming a
geofence alarm failed with `Geofence setup failed (code 10)`.
The same APK on a second Pixel 8 (same permissions) worked
fine. The error code 10 is `CommonStatusCodes.DEVELOPER_ERROR`
from the Play Services Geofencing API.

## Root cause
The most common path to this state is:

1. The first arming on the affected device either partially
   succeeded or the disarm's `removeGeofences` silently failed
   (a known rare outcome when Play Services is mid-restart or
   the receiver component is in a transitional state).
2. The disarm path updates the DB unconditionally
   (`dao.updateArmed(alarmId, false)`) regardless of whether
   the native `removeGeofences` actually succeeded.
3. The DB-side `isArmed` flag is now `false`, but the
   `GeofencingClient` still has the requestId registered.
4. The next arm attempt sees `isArmed = false` and proceeds
   straight to `client.addGeofences(...)`. The GeofencingClient
   rejects with `DEVELOPER_ERROR` because the requestId is
   already registered.

The user's phone never hit this path because the very first
arm on it was clean (no prior failed arming/disarm cycle to
leave stale state).

## Fix
Two changes in
`android/app/src/main/kotlin/com/wakeywakey/app/GeofenceController.kt`:

1. In `addGeofence`, chain a defensive
   `client.removeGeofences(pendingIntent)` immediately before
   the existing `client.addGeofences(...)`. The two calls are
   linked with `.continueWithTask { ... }` so the listeners
   stay attached to the addGeofences result. `removeGeofences`
   is idempotent (no-op when nothing is registered) so this is
   safe to always run, and the extra round-trip is invisible
   to the user. A pre-remove failure is logged but does not
   block the addGeofences attempt (best-effort cleanup).

2. In `humanizeGeofenceError`, add a specific case for
   `CommonStatusCodes.DEVELOPER_ERROR` (code 10) with an
   actionable message: "Stale geofence state. Reboot the device
   and try again. If the problem persists, clear the app
   storage in Android Settings \u2192 Apps \u2192 Wakey-Wakey
   \u2192 Storage." This makes the error self-diagnosing without
   needing logcat, and tells the user exactly what to do if the
   defensive cleanup itself isn't enough.

## Why not also fix the disarm path
The disarm path's `await _bridge.removeGeofence(alarmId); dao.updateArmed(alarmId, false)`
sequence is technically incorrect: it should roll back the
DB update if the remove failed. However:

- The new defensive cleanup in `addGeofence` makes the
  disarm-side failure recoverable on the next arm, which is
  the actual user-visible bug. The disarm-side error is now a
  silent log line instead of a user-visible failure.
- A full disarm fix (check `removeResult.ok` before
  `updateArmed`) is a separate, larger change that should
  also update the disarm tests and the runbook. Out of scope
  for this hotfix.

## Verified
- `flutter analyze`: not re-run (Kotlin change only).
- `flutter test`: not re-run (Kotlin change only; no Dart
  surface change).
- `flutter build apk --release` and
  `flutter build appbundle --release`: rebuilt, AAB signature
  re-verified via keytool -printcert on META-INF/UPLOAD.RSA.

## Manual test plan (human)
1. Reinstall the new APK on the device that previously failed
   (over the existing install; same signing key, so an
   in-place update works).
2. Without rebooting, arm the geofence alarm. The defensive
   remove should clear the stale registration and arming
   should succeed.
3. If arming still fails, reboot the device and retry. The
   OS wipes all geofence registrations on reboot, so the
   stale state is guaranteed gone.
4. After the alarm fires (or is dismissed), disarm. The
   disarm should now also work normally.
