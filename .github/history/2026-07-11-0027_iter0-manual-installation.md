# Iteration 0: Manual Installation & Device Checklist

- **Date:** 2026-07-11 00:27
- **Iteration:** 0 (manual verification)
- **Related APK:** `build/app/outputs/flutter-apk/app-release.apk`

## How to install the release APK

1. Ensure your device is connected and visible to adb (WSL):
   - On Windows, attach the device with `usbipd attach --busid <busid>` if needed.
   - In WSL/Ubuntu: `adb devices` should list your device.

2. Install the APK (replace with device-specific flags if needed):

```bash
# From WSL in project root
adb install -r build/app/outputs/flutter-apk/app-release.apk
# If already installed, use -r to replace; use -d to allow version downgrade if necessary
```

3. Launch the app from the launcher or via adb:

```bash
adb shell monkey -p com.wakeywakey.app -c android.intent.category.LAUNCHER 1
```

## Manual Device Checklist (run after installing the APK)

### 1) Permission Prompts (POST_NOTIFICATIONS)
- Launch the app and trigger the notification permission flow (create a dummy alarm or use UI that prompts notifications).
- Verify the system permission dialog appears.
- Test two flows:
  - Grant: app continues, Settings → Apps → wakey-wakey → Notifications shows enabled.
  - Deny: app handles denial gracefully (no crash).

### 2) Exact Alarm Permission Routing (API 31/33+ differences)
- On API 33+ (Android 13+): the app should route you to the system Settings page to grant the exact alarm permission. Follow the app's prompt and grant it.
- On API 31–32: the permission may be requested via a dialog. Grant and confirm app behavior.
- Verify permission state in Settings → Apps → wakey-wakey.

### 3) MethodChannel Round-Trip
- Open logcat to monitor native logs: `adb logcat --regex "WakeyAlarmBridge|WakeyAlarm"` or use Android Studio logcat filter.
- From the app, trigger the MethodChannel test stub (if UI exists) or use a temporary debug button added earlier.
- Expect to see a native log indicating the call was received and a Dart console print showing the response.

## Reporting Results

For each check, report:
- Device model and Android API level
- Whether the step passed or failed
- Any logs or stack traces for failures

Example report snippet:

```
Device: Pixel 5 (API 33)
Check 1 (POST_NOTIFICATIONS): PASS
Check 2 (Exact Alarm permission): PASS - routed to Settings, permission granted
Check 3 (MethodChannel): PASS - Kotlin log 'Received scheduleAlarm stub call', Dart printed response
```

## Next Steps
- If all checks pass, commit final verification and mark Iteration 0 as complete:
  - `git commit -m "[Iter0] Complete Iteration 0 Definition of Done (manual checks verified)"`
  - Add a `.github/history/` entry documenting manual verification results and device details.

If any check fails, capture logs and open an issue referencing the failure and the steps to reproduce.
