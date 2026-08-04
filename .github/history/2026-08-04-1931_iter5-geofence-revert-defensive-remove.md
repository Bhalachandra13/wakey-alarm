# 2026-08-04 19:31 — Iter5 — geofence: revert defensive removeGeofences

- **Date:** 2026-08-04 19:31
- **Iteration:** 5 (bugfix from on-device testing, third pass)
- **Commit:** *(filled in after committing)*

## Symptom
After deploying the previous fix (defensive
`removeGeofences` + the "stale geofence state" error
message), the user reported a regression: an APK that
worked on their phone yesterday now shows the "stale
geofence state" error on arming. The git log shows the
only Kotlin change between the working APK (cb87a3d,
"yesterday 9:20PM" build) and the failing APK (5b3f689)
is the defensive `removeGeofences` chain I added.

## Root cause
The defensive `removeGeofences` is supposed to be a
no-op on a clean device \u2014 nothing to remove, then
`addGeofences` adds a new one. In theory, transparent.

In practice, on some Pixel firmware revisions, calling
`removeGeofences(pendingIntent)` with a `PendingIntent`
that was never used to register a geofence returns
`CommonStatusCodes.DEVELOPER_ERROR` (code 10) instead
of a clean success. The code I wrote logs the
pre-remove failure and continues to `addGeofences`, so
the user-visible failure listener still attaches to the
*add* result. But the `continueWithTask` chain appears
to surface the pre-remove failure on the same listener
in some Play Services versions, masking the add
attempt entirely \u2014 or, more likely, the entire
geofence arming path is being rejected by Play Services
because the receiver is non-exported and the defensive
remove is provoking the check.

The actual original cause of code 10 is the receiver
export issue addressed in the previous commit
(59402ef): `GeofenceTransitionReceiver` was
`exported="false"` while the GeofencingClient needs to
deliver to an exported component on Android 12+. The
defensive `removeGeofences` did not address this and
appears to introduce a new failure path of its own.

## Fix
Revert the defensive `removeGeofences` chain in
`GeofenceController.addGeofence`. The
`client.addGeofences(request, pendingIntent)` call is
back to a direct chain to the success/failure
listeners, matching the cb87a3d state that worked on
the user's phone.

Kept from the previous commit (59402ef):
* `GeofenceTransitionReceiver` `android:exported="true"`
  in the manifest \u2014 the actual structural fix for
  the original code 10.
* The `humanizeGeofenceError` DEVELOPER_ERROR case with
  Status-message appending \u2014 a debugging improvement
  that makes any future addGeofences failure
  self-diagnosable in the UI.

The disarm-side `removeGeofences` silently-failing
problem is real but is no longer being papered over by
a defensive add-time cleanup. It is filed as a
follow-up for v1.0.1 in the previous history entry
(2026-08-03-2201).

## Verified
- `flutter analyze`: clean.
- `flutter test`: 329 tests pass.
- `flutter build apk --release` and
  `flutter build appbundle --release`: rebuilt, AAB
  signature re-verified.

## Manual test plan
1. Reinstall the new APK on the user's phone (which
   used to work with cb87a3d). The arming flow should
   succeed without any reboot.
2. Reinstall on the wife's phone. The arming flow
   should also succeed because the structural issue
   (receiver export) is now fixed.
3. If arming still fails, the new error message will
   end with `(Reason: <play-services-status>)` so the
   actual cause is visible in the UI.
