# feat: structured GeofenceResult errors + rearm geofences on reboot

- **Date:** 2026-08-02 17:15
- **Iteration:** 4
- **Commit:** 1f19608

## What changed

Two coupled geofence-hardening changes that share a single
Motivation — the geofence feature must not silently fail. They
are committed together because they share `humanizeGeofenceError`
in the native side and the lat/lon/radius persistence
that makes the rearm possible.

### A. Structured error reporting (UI can now say *why*)

Previously a failed `addGeofence()` returned `{added: false}`
and the UI showed a generic "Could not arm geofence" SnackBar.
The Play Services `ApiException` carries a status code
(1004 = location off, 1000 = too many geofences, …) but its
human message is almost always empty ("8: "), so the user had
no actionable signal.

- `GeofenceBridge.addGeofence` / `removeGeofence` now return a
  new `GeofenceResult` value (`{ok, error, code}`) instead of a
  bare `bool`. `PlatformException`s are caught defensively and
  converted to a `GeofenceResult.failed` so the UI never crashes
  on a channel-level error.
- `GeofenceArmingController` carries the human message through
  via `ArmingResult.message`.
- The alarms-screen SnackBar now renders the detail:
  "Could not arm geofence: Location services are off. Turn on
  Location in system Settings and try again." for 5 seconds.
- `GeofenceController.kt` (native) catches `ApiException`,
  translates the status code via the new `humanizeGeofenceError`
  helper (recognises 1000/1001/1004/1005 and the common
  `CommonStatusCodes`), and returns a structured
  `{added: false, error, code}` payload. `SecurityException` and
  generic `Exception` paths also return structured failures
  rather than `result.error(...)`, matching the channel
  contract.

### B. Re-arm geofences on reboot (no more silent disappear)

The OS wipes `GeofencingClient` registrations on reboot *and*
on app upgrade (`MY_PACKAGE_REPLACED`). The persisted
`AlarmScheduler.AlarmData` mirror survived, but the live
registration did not — so an armed geofence alarm silently
disappeared the next time the device restarted. This is the
single most common cause of "my location alarm didn't fire" in
user testing.

- `AlarmScheduler.AlarmData` gains `latitude`, `longitude`,
  `radiusMeters` (nullable; absent for time/timer entries).
  Persisted in SharedPreferences so `BootReceiver` can read
  them back. `isNull` (not absence) distinguishes "explicitly
  null" from "field missing" so v1 entries round-trip cleanly.
- `GeofenceController.rearmPersistedGeofences` (new) reads
  every persisted LOCATION entry and re-registers it with
  Play Services. Entries missing lat/lon/radius (persisted
  before this feature, or corrupted) are skipped with a
  warning. Out-of-range radii are skipped. Failures are
  logged, not thrown — a boot-path exception would leave the
  system in a half-armed state.
- `BootReceiver` calls `rearmPersistedGeofences` for
  `BOOT_COMPLETED`, `QUICKBOOT_POWERON`, and
  `MY_PACKAGE_REPLACED` (the last matters because app updates
  also wipe Play Services registrations).

### Tests

- `geofence_bridge_test`: success, humanized failure, and the
  `PlatformException`-→-`GeofenceResult` defensive path for
  both `addGeofence` and `removeGeofence`.
- `geofence_arming_controller_test` /
  `geofence_arming_edge_cases_test`: updated for the
  `GeofenceResult` return type.
- `full_flow_test`: `_FakeGeofenceBridge` returns
  `GeofenceResult.ok` / `.failed` instead of bools.

## Why

The geofence feature's two largest silent-failure modes
(opaque errors on arm, disappearance on reboot) are now both
surfaced or fixed. Together they make the feature trustworthy
enough to be the app's headline capability.

References requirements.md §5.5 (geofence one-shot auto-disarm
+ battery/health visibility) and workflow_plan.md Iter 4 DoD
("after firing and dismissing, confirm the alarm auto-disarms
… no silent failure").

## Files touched

- lib/native_bridge/geofence_bridge.dart
- lib/presentation/providers/geofence_arming_controller.dart
- lib/presentation/screens/alarms_screen.dart
- test/functionality/full_flow_test.dart
- test/native_bridge/geofence_bridge_test.dart
- test/presentation/providers/geofence_arming_controller_test.dart
- test/presentation/providers/geofence_arming_edge_cases_test.dart
- android/app/src/main/kotlin/com/wakeywakey/app/GeofenceController.kt
- android/app/src/main/kotlin/com/wakeywakey/app/AlarmScheduler.kt
- android/app/src/main/kotlin/com/wakeywakey/app/BootReceiver.kt

## Verification

- [x] `flutter analyze` clean (re-verified in batch)
- [x] `flutter test` — 294 tests pass (re-verified in batch)
- [ ] Manual on-device: arm a geofence, reboot the device,
      confirm it still triggers; attempt to arm with location
      off, confirm the SnackBar shows the humanized message
      (per workflow_plan.md Iter 4 manual DoD).
