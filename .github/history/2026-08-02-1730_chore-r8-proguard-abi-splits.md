# chore(build): enable R8/ProGuard + ABI splits with native keep rules

- **Date:** 2026-08-02 17:30
- **Iteration:** cross-iteration (build infrastructure)
- **Commit:** a010e0b

## What changed

Enables R8/ProGuard code shrinking and per-ABI APK splits on
release builds, and adds the keep rules that make shrinking
safe for the native bridge classes the Dart side reaches via
`MethodChannel`/`EventChannel`.

- `android/app/build.gradle.kts`: `isMinifyEnabled = true` and
  `isShrinkResources = true` on the release build type, with
  `proguard-android-optimize.txt` + the new
  `proguard-rules.pro`. `splits.abi` produces one lean APK per
  architecture (arm64-v8a, armeabi-v7a, x86_64) with
  `isUniversalApk = true` for a fat-APK fallback. R8
  typically halves the release APK and noticeably speeds up
  dexing/linking.
- `android/app/proguard-rules.pro` (new): keeps every native
  bridge class the Dart side reaches by fully-qualified name
  (`AlarmService`, `AlarmReceiver`, `BootReceiver`,
  `GeofenceTransitionReceiver`, `RingingActivity`) plus
  Google Play Services Geofencing's reflection-instantiated
  `TransitionPendingIntent` receiver. Without these, R8 would
  rename or strip the classes and the method-channel lookups
  would fail at runtime — which is exactly the silent-failure
  mode AGENTS.md §8 warned about.
- `android/gradle.properties`: trims the Gradle daemon JVM
  args (8G → 2G) and enables parallel builds, the build
  cache, and the Kotlin daemon. Disables the configuration
  cache with a comment explaining the
  Flutter-Gradle-plugin + AGP 9 + Kotlin 2.3.20 incompatibility
  (Kotlin's `StoredPropertyStorage` holds a
  `java.lang.ref.ReferenceQueue` the cache can't serialise;
  the plugin's `DebugMinSdkCheck` task captures
  non-serialisable project objects). Re-enable when the
  upstream combo is fixed.

## Why

Release APK size and build speed. The keep rules are the
prerequisite for the future move to dropping
`--no-shrink` from the documented `flutter build apk
--release --no-shrink` command — the shrink is now safe, but
AGENTS.md §8 still recommends `--no-shrink` until the new
release config is manually verified on a real device (alarm
must still fire, geofence must still register). Follow-up
iteration can update the documented command.

## Files touched

- android/app/build.gradle.kts
- android/app/proguard-rules.pro (new)
- android/gradle.properties

## Verification

- [x] `flutter analyze` clean (the change is build-config
      only; the Dart tree is unaffected).
- [x] `flutter test` — 294 tests pass (unaffected).
- [ ] Manual on-device: run
      `flutter build apk --release --no-shrink` (or, after
      this is verified, without `--no-shrink`); install and
      confirm (a) the alarm still fires, (b) a geofence
      still registers, (c) the boot re-arm still works.
