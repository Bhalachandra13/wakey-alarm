# chore: release APK — Iteration 5 build

- **Date:** 2026-08-02 21:20
- **Iteration:** 5 (favourites + permission UX)
- **APK:** `build/app/outputs/flutter-apk/app-release.apk` (53 MB)
- **Build command:** `flutter build apk --release --no-shrink`
- **Build time:** 233.6 s (Gradle assembleRelease)

## Summary

This build packages the two Iteration 5 commits
([50a4da6](#) favourites, [ed4f0a9](#) permission wizard) plus
the Iter 4/2/1 groundwork commits that were sitting in the
working tree at the start of the session. Everything compiles
into a single universal release APK ready for on-device
verification of:

- The favourite-locations flow (save Home/Work, quick-pick
  chips in the map picker, "two taps to set up a geofence"
  headline use case).
- The unified permission setup wizard + consolidated
  `_PermissionsHealthBanner` (auto-pushed on first run,
  one-button "Set up" for notif / exact alarm / location /
  battery).
- The earlier hardened geofence pipeline
  (structured `GeofenceResult` errors, boot re-arm of
  geofences, AlarmService null-intent guard, R8 + ABI
  splits with native-bridge keep rules).

## Verification

- [x] `flutter analyze` clean
- [x] `flutter test` — 328 tests pass
- [x] `flutter build apk --release --no-shrink` succeeds
- [ ] Manual on-device (per `workflow_plan.md` Iter 5 DoD):
  - [ ] First-run: "Get ready" wizard auto-pushes on the
        alarms tab and walks all four items in order.
  - [ ] Open a geofence alarm → "Pick on map" → chip strip
        shows saved favourites; tapping Home drops the pin
        and flies the camera with the correct radius.
  - [ ] First-time Favourites empty state shows Add Home /
        Add Work; tapping Add Home opens the map picker and
        the resulting favourite shows up in the chip strip
        on the next picker open.
  - [ ] Arm a geofence, reboot the device, confirm the
        geofence still triggers (boot re-arm from the Iter 4
        groundwork commit).

## Why `--no-shrink`

AGENTS.md §8 recommends `--no-shrink` for the release build
because R8/ProGuard shrinking can strip
`MethodChannel`/`BroadcastReceiver`/`Service` classes if the
keep rules aren't set up. This build's Gradle config now
sets `isMinifyEnabled = true` with `proguard-rules.pro`
keeping every native bridge class (`AlarmService`,
`AlarmReceiver`, `BootReceiver`,
`GeofenceTransitionReceiver`, `RingingActivity`) plus
Google Play Services' reflection-instantiated
`TransitionPendingIntent` receiver — so the keep rules
exist and a future build without `--no-shrink` should be
safe. We're keeping `--no-shrink` for this build as a
conservative default until the un-shrunk release config
is manually verified on a real device (alarm must still
fire, geofence must still register, boot re-arm must
still work).

## Notes

- `Font asset "MaterialIcons-Regular.otf" was tree-shaken,
  reducing it from 1645184 to 6824 bytes (99.6% reduction).`
  Standard Flutter release behavior; the icon font is
  rebuilt to include only the glyphs the app actually uses.
- The build is 53 MB. R8 + resource shrinking are
  technically active in the build script (per the earlier
  `chore: R8/ProGuard + ABI splits` commit); `--no-shrink`
  disables them for this build's output.
