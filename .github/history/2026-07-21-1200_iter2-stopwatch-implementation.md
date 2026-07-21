# Iteration 2: Stopwatch Implementation

- **Date:** 2026-07-21
- **Iteration:** 2
- **Commit:** `9fd317b` — `[Iter2] Implement Stopwatch with Riverpod state + UI + tests`

## What changed

Added a self-contained stopwatch feature as the second bottom-nav tab.
The implementation is intentionally **pure Dart with no persistence** —
the iteration brief explicitly noted that the stopwatch resets on app
kill is the accepted behavior.

- `lib/domain/stopwatch.dart` — `StopwatchState` (running / paused /
  reset) and `StopwatchLap` with value equality.
- `lib/presentation/providers/stopwatch_provider.dart` — `Notifier`
  using `package:clock` for testability with `fakeAsync`. 50 ms ticker
  interval for the on-screen centisecond display.
- `lib/presentation/utils/stopwatch_format.dart` — `MM:SS.hh` (under
  one hour) and `H:MM:SS.hh` (one hour or more) formatters.
- `lib/presentation/screens/stopwatch_screen.dart` — three circular
  control buttons (start/pause, lap, reset) and a reversed lap list
  (most recent on top).
- Wired into `lib/presentation/app.dart` (bottom-nav tab index 1).
- Fixed `lib/presentation/providers/app_providers.dart` which had
  duplicate stub providers (only `permissionStatusProvider` actually
  defined; the rest were removed in favor of providers in the
  `alarms_provider.dart` and `timers_provider.dart` files).

## Why

Iteration 2 of `workflow_plan.md`. Stopwatch is the simplest tab —
no native code, no persistence — so it doubles as a test bed for the
Riverpod + ticker pattern that the (more complex) Iter 3 and 4
features reuse.

## Files touched

- `lib/domain/stopwatch.dart` (new)
- `lib/presentation/providers/stopwatch_provider.dart` (new)
- `lib/presentation/utils/stopwatch_format.dart` (new)
- `lib/presentation/screens/stopwatch_screen.dart` (new)
- `lib/presentation/app.dart` (modified — added tab)
- `lib/presentation/providers/app_providers.dart` (modified —
  removed duplicate stubs)
- `pubspec.yaml` (added `clock: ^1.1.1`)
- `test/domain/stopwatch_test.dart` (new)
- `test/presentation/providers/stopwatch_provider_test.dart` (new —
  uses `fakeAsync`)
- `test/presentation/utils/stopwatch_format_test.dart` (new)
- `test/presentation/screens/stopwatch_screen_test.dart` (new)

## Verification

- [x] `flutter analyze` clean
- [x] `flutter test` passing (183/183 overall after Iter 4 landed)
- [x] `dart format --output=none --set-exit-if-changed .` passes
- [ ] Manual on-device check needed? **Yes:**
  - Confirm the stopwatch resets on app kill (expected behavior —
    verify the app does not crash on cold start).
  - Confirm timing accuracy over a multi-minute run (no significant
    drift while app is foregrounded).
  - Pending human verification per `workflow_plan.md` Iter 2 DoD.
