# Iteration 0: Manual On-Device Verification Checklist

**Date:** 2026-07-10  
**Iteration:** 0  
**Target:** Android device or emulator (minSdk 26)

---

## Overview

The 3 items below complete Iteration 0's Definition of Done. They **cannot** be automatically tested and must be verified on a real or virtual Android device.

Once you complete all 3 checks below, report the results so we can commit the final verification and move to Iteration 1.

---

## Check 1: Permission Prompts (POST_NOTIFICATIONS)

**What this tests:** The app's ability to request and handle the POST_NOTIFICATIONS permission, required to show alarm/timer notifications.

### Steps

1. **Fresh Install**
   ```bash
   # In WSL:
   cd /mnt/d/Hobby_Project/wakey-alarm
   flutter run
   ```
   This builds and installs the app on your connected device.

2. **Trigger POST_NOTIFICATIONS Request**
   - Once the app opens, look for a permission prompt for "Notifications"
   - If no prompt appears immediately, the app may defer this to first alarm/timer creation
   - If you don't see a prompt, create a dummy alarm/timer (UI scaffolding exists) to trigger it

3. **Test Grant Path**
   - Tap "Allow" (or equivalent "Grant" button) on the permission prompt
   - Verify the app continues normally (no crash)
   - In device Settings → Apps → wakey-wakey → Notifications, verify notifications are enabled

4. **Test Deny Path** (if possible, on a second run or using adb to reset permissions)
   ```bash
   adb shell pm revoke com.wakeywakey.app android.permission.POST_NOTIFICATIONS
   # Restart app and deny the prompt
   ```
   - Tap "Deny" on the permission prompt
   - Verify the app handles the denial gracefully (no crash)
   - Verify the app informs the user that notifications won't work (or silently continues — check implementation)

### Acceptance Criteria

- [x/☐] Grant path: Permission prompt appears, grant succeeds, no crash
- [x/☐] Deny path: Permission prompt appears, deny is handled gracefully, no crash

---

## Check 2: Exact Alarm Permission Routing (SCHEDULE_EXACT_ALARM / USE_EXACT_ALARM)

**What this tests:** On API 33+ devices, the `SCHEDULE_EXACT_ALARM` permission is granted via a Settings page (not a simple dialog). The app must route the user to the correct Settings location.

### Steps

1. **Check Device Android Version**
   ```bash
   adb shell getprop ro.build.version.sdk
   ```
   - If SDK < 31: Skip this check (exact alarm permission doesn't exist yet)
   - If SDK 31–32: Should be a simple dialog; no Settings redirect needed
   - If SDK ≥ 33: Must route to Settings

2. **On API 33+ Devices: Navigate to Settings**
   - Launch the app
   - Look for any UI that requests "Allow exact alarms" or similar
   - The app should either:
     a) Show an explanation screen, then open Settings automatically, or
     b) Provide a link to Settings
   - Follow the app's guidance to Settings → Alarms and Reminders → [wakey-wakey]
   - Grant the permission

3. **On API 31–32 Devices: Expect a Dialog**
   - Launch the app
   - Permission should be requested via a standard Android dialog
   - Grant it and verify the app continues

4. **Verify Permission Granted**
   ```bash
   adb shell pm list permissions -d | grep SCHEDULE_EXACT_ALARM
   # Or check in Settings → Apps → wakey-wakey → Permissions
   ```

### Acceptance Criteria

- [x/☐] API 33+: App routes to Settings correctly (no crash, UI is clear)
- [x/☐] API 31–32: App requests permission via dialog (no crash)
- [x/☐] All paths: Permission is granted without errors

**Note:** If using an emulator, simulate API 33 by creating an AVD with API 33 target.

---

## Check 3: MethodChannel Round-Trip (Native Bridge Wiring)

**What this tests:** The `MethodChannel` communication between Dart and Kotlin is correctly wired. A call from Dart to Kotlin should successfully reach the native side and return a response.

### Steps

1. **Enable Native Logging** (Optional but helpful)
   - Open `android/app/src/main/kotlin/com/wakeywakey/app/MainActivity.kt`
   - Verify it has a `MethodChannel` setup (should already be there from Iteration 0)
   - Look for a method handler (e.g., `scheduleAlarmStub()`)

2. **Connect Device and Monitor Logs**
   ```bash
   adb logcat -s "WakeyAlarm:*" &  # Filter for our app's logs
   # In another terminal, run the app
   flutter run
   ```

3. **Trigger MethodChannel Call from Dart**
   - The app UI currently has placeholder tabs
   - Look for any button or action that might call a native method
   - If none exists visually, you may need to trigger it programmatically
   - Alternatively, modify the code to add a test button that calls the bridge

   **Quick Test:** Add a temporary button to the app shell or a test screen:
   ```dart
   ElevatedButton(
     onPressed: () async {
       try {
         final result = await const MethodChannel('com.wakeywakey/alarm_bridge')
           .invokeMethod('testStubMethod');
         print('Native response: $result');
       } catch (e) {
         print('Error: $e');
       }
     },
     child: const Text('Test Native Call'),
   )
   ```

4. **Check Kotlin Side Received Call**
   - In the Kotlin logs (`adb logcat`), you should see a message like:
     ```
     WakeyAlarm: Received MethodChannel call: testStubMethod
     ```
   - If the log appears, native side received it ✅

5. **Verify Dart Side Received Response**
   - In the Flutter console, you should see:
     ```
     Native response: {...response data...}
     ```
   - If this prints, the round-trip succeeded ✅

### Acceptance Criteria

- [x/☐] Dart calls native method without throwing an exception
- [x/☐] Kotlin logs show method was received
- [x/☐] Dart receives response (can be dummy/stub data)
- [x/☐] No crashes on either side

**Note:** If the test button approach is used, remove it before final commit (don't leave test code in production).

---

## How to Report Results

After completing all 3 checks:

1. **For each check:** Note whether it passed (✅) or failed (❌) with details
2. **If any checks fail:** Describe the error or unexpected behavior
3. **Device info to include:**
   - Android version (e.g., Android 14, API 34)
   - Device model (e.g., Pixel 6, MIUI, Samsung Galaxy)
   - Whether real device or emulator

### Example Report

```
✅ Check 1 (Permissions): PASS
   - Grant path: Notification permission prompt appeared, granted successfully, app continued
   - Deny path: Permission denied, app handled gracefully (no crash)

✅ Check 2 (Exact Alarm Permission): PASS
   - Device: Pixel 6 (API 34, Android 14)
   - Exact alarm permission request routed to Settings correctly
   - Permission granted, app continued

✅ Check 3 (MethodChannel): PASS
   - Added test button, clicked it
   - Kotlin logcat showed: "Received MethodChannel call: testStubMethod"
   - Dart console printed: "Native response: {success: true}"
   - No exceptions or crashes

All 3 checks passed. Ready to move to Iteration 1.
```

---

## Next Steps

Once all checks pass:

1. **Commit the verification**
   ```bash
   git add .
   git commit -m "[Iter0] Complete Iteration 0 Definition of Done (manual checks verified)"
   ```

2. **Create a final history entry** (or I can do this automatically once you confirm)

3. **Move to Iteration 1: Normal Alarm**
   - Alarm creation UI (time picker, repeat days)
   - Native `AlarmManager.setAlarmClock()` scheduling
   - `BroadcastReceiver` + foreground `Service`
   - Full-screen ringing activity

---

## Troubleshooting

| Problem | Solution |
|---|---|
| App crashes on launch | Check `flutter run` output for errors; may be a manifest issue or missing permission declaration |
| Permission prompt never appears | Permission may already be granted; check Settings → Apps → wakey-wakey → Permissions to reset and try again |
| MethodChannel call throws `MissingPluginException` | Ensure `MainActivity.kt` has the correct channel name (`com.wakeywakey/alarm_bridge`) matching the Dart side |
| Kotlin logs don't show anything | Verify `adb logcat` filter is correct; try `adb logcat \| grep "WakeyAlarm"` without the filter |
| Device not connecting via `adb` | Ensure USB debugging is enabled on device; run `adb devices` to see connected devices; may need `usbipd attach` on Windows side first |

