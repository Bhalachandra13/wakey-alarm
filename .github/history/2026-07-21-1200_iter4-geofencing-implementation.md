# Iteration 4: Geofencing Implementation

- **Date:** 2026-07-21
- **Iteration:** 4
- **Commit:** `53bc240` — `[Iter4] Implement Geofencing with native GeofencingClient + tests`

## What changed

Added the core differentiator feature: **location-triggered alarms**.
The implementation uses the Google Play Services `GeofencingClient`
(not the platform `LocationManager`) so it only works on devices with
Google Play Services — which is the entire Phase 1 target.

The one-shot auto-disarm is implemented in **Dart** rather than native
code, so the native side stays a thin "transitions → alarm pipeline"
forwarder and the state machine (when to disarm, when to refresh,
when to clear a "ringing" banner) lives in the easier-to-test layer.

### Domain
- `lib/domain/geofence_validator.dart` — `GeofenceValidator`:
  - `isRadiusInBounds` (200 m – 20 km; the Google Play
    `GeofencingClient` limit is 20 km).
  - `isAlarmValid` (combines radius + lat/long range + radius presence
    check).
  - `isPointInsideGeofence` (Haversine).
  - Constants: `minRadiusMeters`, `maxRadiusMeters`,
    `defaultRadiusMeters`.

### Native bridge
- `lib/native_bridge/geofence_bridge.dart` — `GeofenceBridge` with
  methods for permission status, foreground + background permission
  requests, one-shot location reads, geofence add/remove, and
  battery-optimization status + exemption request. Translates the
  native status string into a `LocationPermissionStatus` enum.
- `geofenceBridgeProvider` exposed for Riverpod overrides in tests.

### State / flow
- `lib/presentation/providers/geofence_arming_controller.dart` —
  `GeofenceArmingController` runs the full "Start Trip" arming flow:
  1. Permission check.
  2. One-shot current location read.
  3. "Already inside" pre-arm check (Haversine).
  4. Native geofence registration.
  5. Flip `is_armed` to `true` in sqflite.
  Returns an `ArmingResult` enum (`armed` / `alreadyInside` /
  `registrationFailed` / `permissionMissing` / `invalidAlarm`) so the
  UI can render the right message without exception-handling.

### UI
- `lib/presentation/screens/map_picker_screen.dart` — Google Maps
  picker with radius slider + manual lat/long fallback (so the
  feature works without a Maps API key in CI).
- `lib/presentation/screens/background_location_explanation_screen.dart`
  — pre-explanation screen for the "Allow all the time" background
  permission flow, with a `LocationPermissionFlow` helper class.
- `lib/presentation/screens/edit_alarm_screen.dart` — extended with
  a Time / Location `SegmentedButton`; the location branch shows the
  picker, radius slider, and validation.
- `lib/presentation/screens/alarms_screen.dart` — added:
  - `_GeofenceHealthBanner` (shown when an armed location alarm has
    missing permissions or battery-optimization is not exempt).
  - Arm/disarm `IconButton` for location alarms (replaces the
    enable/disable `Switch` for time-based alarms).
  - Arming flow integration: "armed" snackbar, "already inside"
    dialog, permission flow walkthrough, error snackbar.

### Native
- `android/app/src/main/kotlin/com/wakeywakey/app/GeofenceController.kt`
  — the native side of the `com.wakeywakey/geofence` MethodChannel.
  Routes requests to Play Services' `GeofencingClient` for
  add/remove, and to `FusedLocationProviderClient` for the
  pre-arm "already inside" location read. Defends against
  out-of-bounds radii (200 – 20 000 m) on the native side too.
- `android/app/src/main/kotlin/com/wakeywakey/app/GeofenceTransitionReceiver.kt`
  — `BroadcastReceiver` registered in the manifest. On
  `GEOFENCE_TRANSITION_ENTER`:
  1. Emits a `fired` event to Dart with `triggerType: "location"`.
  2. Reads the persisted `AlarmData` (label, sound, snooze, etc.).
  3. Starts `AlarmService` with `EXTRA_TRIGGER_TYPE = "LOCATION"`,
     so `RingingActivity` prefixes the label with `"Location: "`.
- `android/app/src/main/kotlin/com/wakeywakey/app/ActivityCompatExt.kt`
  — permission-request helpers (foreground location, background
  location).
- `android/app/src/main/AndroidManifest.xml` — added
  `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`,
  `ACCESS_BACKGROUND_LOCATION`, the Google Maps API key meta-data
  (placeholder `${MAPS_API_KEY}`), and the
  `GeofenceTransitionReceiver` `<receiver>` declaration.

### Dart side reuses the alarm pipeline
- Extended `RingingActivity.kt` to add a `"Location: "` prefix when
  `triggerType == "LOCATION"`.
- `AlarmsNotifier._onNativeDismiss` now handles the
  `triggerType == "location"` case on both `dismissed` and `snoozed`
  events: removes the native geofence + flips `is_armed` to `false`
  (one-shot auto-disarm).

## Why

Iteration 4 of `workflow_plan.md`. This is the core differentiator
of the app and the largest iteration. Architectural decisions:

- **Native `GeofencingClient` over a third-party Flutter plugin**
  (per `requirements.md` §2 — explicit decision).
- **One-shot auto-disarm in Dart** rather than in the native
  receiver — the state machine is in the easier-to-test layer.
- **Map picker degrades without an API key** (manual lat/long
  inputs always work) so CI can test the picker without burning
  API quota.
- **Pre-explanation screen before the system Settings page** — the
  grant rate for "Allow all the time" is dramatically lower
  without an in-app explanation, per `requirements.md` §4.

## Files touched

### Dart (new)
- `lib/domain/geofence_validator.dart`
- `lib/native_bridge/geofence_bridge.dart`
- `lib/presentation/providers/geofence_arming_controller.dart`
- `lib/presentation/screens/background_location_explanation_screen.dart`
- `lib/presentation/screens/map_picker_screen.dart`
- `test/domain/geofence_validator_test.dart` (22 tests)
- `test/native_bridge/geofence_bridge_test.dart` (11 tests)
- `test/presentation/providers/geofence_arming_controller_test.dart`
  (10 tests)
- `test/presentation/screens/edit_alarm_location_test.dart` (4 tests)

### Dart (modified)
- `lib/presentation/screens/edit_alarm_screen.dart` (added
  `SegmentedButton` for Time/Location, plus the location branch)
- `lib/presentation/screens/alarms_screen.dart` (added
  `_GeofenceHealthBanner`, arm/disarm button, arming flow)
- `lib/presentation/providers/alarms_provider.dart` (added
  location-trigger handling in `_onNativeDismiss`)
- `pubspec.yaml` (added `google_maps_flutter`; removed unused
  `geolocator` and `permission_handler`)

### Kotlin (new)
- `android/app/src/main/kotlin/com/wakeywakey/app/GeofenceController.kt`
- `android/app/src/main/kotlin/com/wakeywakey/app/GeofenceTransitionReceiver.kt`
- `android/app/src/main/kotlin/com/wakeywakey/app/ActivityCompatExt.kt`

### Kotlin (modified)
- `android/app/src/main/kotlin/com/wakeywakey/app/MainActivity.kt`
  (registered the geofence `MethodChannel`)
- `android/app/src/main/kotlin/com/wakeywakey/app/RingingActivity.kt`
  (added `"Location: "` prefix for `LOCATION` trigger type)
- `android/app/src/main/AndroidManifest.xml` (location perms,
  Maps API key placeholder, GeofenceTransitionReceiver)

## Verification

- [x] `flutter analyze` clean
- [x] `flutter test` passing (183/183)
- [x] `dart format --output=none --set-exit-if-changed .` passes
- [ ] Manual on-device check needed? **Yes:**
  - Create a geofence alarm at a real nearby location, arm it,
    physically travel into the radius, confirm it fires.
  - Attempt to arm while already inside the radius, confirm the
    warning is shown and geofence is not registered.
  - Force-kill the app after arming, confirm the geofence still
    triggers (native `GeofencingClient` survives app death).
  - After firing and dismissing, confirm the alarm auto-disarms
    and does not refire on GPS jitter near the boundary.
  - Deny background location permission, confirm the app clearly
    communicates the feature won't work reliably.
  - Test on at least one OEM device known for aggressive battery
    optimization (Xiaomi/MIUI) with the optimization exemption
    granted vs. not granted.
  - Pending human verification per `workflow_plan.md` Iter 4 DoD.
- [ ] APK build: **`flutter build apk --release --no-shrink`** to
  be run when a Gradle-cache-warm environment is available. The
  previous build attempt timed out during first-time Gradle
  dependency download (≈685 s, exceeded the local WSL timeout).
  Once the cache is warm the build should complete in ~3 minutes
  per the existing Iter 1 history baseline.
