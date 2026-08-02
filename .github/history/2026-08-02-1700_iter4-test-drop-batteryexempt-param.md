# test: drop unused batteryExempt param from _FakeGeofenceBridge

- **Date:** 2026-08-02 17:00
- **Iteration:** 4 (test cleanup)
- **Commit:** 5b855c3

## What changed

Removes the unused `batteryExempt` optional parameter from
`_FakeGeofenceBridge` in `test/presentation/screens/alarms_screen_test.dart`
and inlines `true` into `isBatteryOptimizationExempt()`.

`flutter analyze` flagged the parameter: no test ever passes
`batteryExempt: …`, so the default `true` is always used. The
parameter existed for symmetry with `permissionStatus` but
battery exemption is not the variable the banner/health tests
are exercising — the health banner is driven by `permissionStatus`
in the existing tests. Dropping the parameter silences the
warning without changing test behaviour.

## Why

AGENTS.md §6: resolve all analyzer warnings before marking a
task done.

## Files touched

- test/presentation/screens/alarms_screen_test.dart

## Verification

- [x] `flutter analyze` clean (re-ran in batch with the rest of
      the groundwork commits; warning resolved)
- [x] `flutter test` still green (the change is a no-op for
      tests that instantiated the fake)
