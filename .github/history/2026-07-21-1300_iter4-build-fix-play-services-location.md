# Iteration 4 follow-up — geofence build fix (play-services-location dep)

## Status

- Committed 4 `BUILD SUCCESSFUL` test runs after Iter 4 landed (183 tests
  pass, `dart analyze` + `dart format` clean), but the APK never
  actually compiled in this environment. The first end-to-end
  `flutter build apk --debug` failed with three Kotlin errors
  (`GeofenceController.kt:367:22`, `:374:37`, `:377:61`) at the
  `removeGeofence` call site. Investigating revealed the root cause
  was much earlier: the Gradle build never had
  `com.google.android.gms:play-services-location` on the classpath at
  all. The imports (`com.google.android.gms.location.{Geofence,
  GeofencingClient, GeofencingRequest, LocationServices, Priority}`)
  silently resolved to `Unresolved reference 'google'` for the whole
  family, which then cascaded into the downstream type-inference
  errors that initially looked like a method-local bug.

## WHY

- GeofencingClient + FusedLocationProviderClient + the
  `Priority.PRIORITY_HIGH_ACCURACY` constant all live in
  `play-services-location`. `google_maps_flutter` pulls in
  `play-services-maps` but NOT the `play-services-location`
  artifact, so the Iter 4 Kotlin side (GeofenceController,
  GeofenceTransitionReceiver) compiled in IDE previews where the
  AGP-managed "hypothetical" classpath included extra SDK addons,
  but failed in a clean Gradle build. The Dart tests passed because
  they mock the entire MethodChannel surface — Kotlin symbol
  resolution is a host-side concern. This is a gap the unit tests
  cannot see; the only honest check is an actual APK build, which
  we should have done before claiming Iter 4 was "ready for
  device".

## Fix

- Added `implementation("com.google.android.gms:play-services-location:21.3.0")`
  to `android/app/build.gradle.kts`. Re-running
  `./gradlew :app:compileDebugKotlin` now finishes `BUILD SUCCESSFUL`
  in 1m 57s. Full APK build is the next verification step.

## Follow-up

- All Kotlin files in `android/app/src/main/kotlin/com/wakeywakey/app/`
  are now compilable against the real artifact set. Pixel 8 (Android
  16, API 36) is connected over wireless adb at
  `192.168.8.82:40813`. Next action: install the freshly-built debug
  APK and walk the DoD checks listed in the three prior history
  entries (Iter 2 stopwatch timing, Iter 3 timer-with-app-killed,
  Iter 4 geofence arm/disarm).

## References

- Prior: `.github/history/2026-07-21-1200_iter4-geofencing-implementation.md`
- Commit: pending (this entry covers the chore that follows Iter 4)
