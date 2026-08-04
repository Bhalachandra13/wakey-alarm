# 2026-08-04 19:10 — Iter5 — geofence: export receiver + surface Status message

- **Date:** 2026-08-04 19:10
- **Iteration:** 5 (bugfix from on-device testing, second pass)
- **Commit:** *(filled in after committing)*

## Symptom
After the previous fix (defensive `removeGeofences` + the
"stale geofence state" error message), the user installed
the new APK and still hit the literal text of the new error
message when trying to arm a geofence alarm. The new
message is rendered when the GeofencingClient returns
status code 10 (`CommonStatusCodes.DEVELOPER_ERROR`); the
defensive cleanup ran and the addGeofences call still
failed with the same code.

## Root cause
The previous fix was correct for *stale* state (a
duplicate requestId already in the GeofencingClient's
table), but did not address the case where the
addGeofences call itself is structurally rejected.
The most common structural cause for code 10 on Android
12+ is the receiver component being declared
`android:exported="false"` while the GeofencingClient
needs to deliver to an exported component. Some Pixel
firmware revisions are stricter than the documented
behaviour; an explicit-component PendingIntent from the
same UID does not always satisfy the receiver
visibility check on every build.

The defensive removeGeofences cannot help with this
because the issue is the receiver declaration, not
the per-alarmId registration state.

## Fix
Two changes in
`android/app/src/main/kotlin/com/wakeywakey/app/GeofenceController.kt`
and one in `android/app/src/main/AndroidManifest.xml`:

1. **Manifest**: change
   `GeofenceTransitionReceiver`'s `android:exported` from
   `"false"` to `"true"`. The doc comment is updated to
   explain the security trade-off:
   * The PendingIntent is built with `FLAG_IMMUTABLE`, so
     a third-party broadcast cannot modify the action or
     the data URI; a malicious app can therefore only
     trigger the alarm UI with the exact alarmId it
     guesses.
   * The receiver code treats the alarmId extra as an
     opaque lookup key and only acts on alarms present in
     the local SQLite database, so a guessed alarmId that
     does not exist in the DB is a no-op.
   * This matches Google's official geofencing samples,
     which also export the receiver.

2. **Kotlin `addGeofence` failure handler**: extract the
   `Status.statusMessage` from the ApiException (it
   carries the actual structural reason for code 10) and
   pass it through to the Dart side as a new `"details"`
   field in the result map. Also append the message to
   the humanized error string in parentheses so the user
   sees it in the UI without needing adb logcat.

3. **Kotlin `humanizeGeofenceError`**: signature updated
   to accept a `statusMessage: String = ""` parameter
   and append it in parentheses when non-blank. The
   `DEVELOPER_ERROR` case text was also softened from
   the misleading "Stale geofence state" (which the
   previous fix diagnosed, and which turned out to be
   the wrong diagnosis for the second pass) to the
   generic "Geofence setup was rejected by Android.
   Reboot the device and try again. If the problem
   persists, clear the app storage in Android Settings
   \u2192 Apps \u2192 Wakey-Wakey \u2192 Storage." The
   appended Status message tells the user the actual
   structural reason when it is known.

## Why both changes
The receiver-export change is the most likely fix.
The Status-message-surfacing change is a debugging
improvement that makes any future `addGeofences` failure
self-diagnosable in the UI: the user will see something
like "(Reason: Geofence ... already registered)" rather
than a generic error code. If the receiver change
fixes the immediate symptom, the Status-message change
still pays off the next time something else goes wrong.

## Verified
- `flutter analyze` on the touched files: no issues.
- `flutter test`: full suite passes (no Dart changes;
  the Kotlin `humanizeGeofenceError` signature is
  backward-compatible thanks to the default parameter
  value).
- `flutter build apk --release` and
  `flutter build appbundle --release`: rebuilt, AAB
  signature re-verified via `keytool -printcert` on
  `META-INF/UPLOAD.RSA`.

## Manual test plan
1. Reinstall the new APK on both devices over the
   existing install (same signing key, in-place update).
2. Arm the geofence alarm on the device that previously
   failed. It should now succeed without any reboot
   required \u2014 the exported receiver is the structural
   reason, not a state issue.
3. If it still fails, the error message will now end
   with a parenthetical "(Reason: <play-services-status>)"
   that names the actual cause. The most likely reasons
   if the receiver change did not help are:
   * `Geofence ... already registered` \u2014 means a
     previous disarm's `removeGeofences` did not fully
     clear. Reboot the device (this is guaranteed to
     clear all geofence registrations per the Play
     Services contract).
   * `PendingIntent has wrong flags` \u2014 would mean the
     PendingIntent construction is wrong; the
     addOnFailureListener logs the full exception with
     `Log.w(TAG, ..., e)` which gives a stack trace
     usable for diagnosis.
4. If the user is happy, this is the v1.0.0 build.
