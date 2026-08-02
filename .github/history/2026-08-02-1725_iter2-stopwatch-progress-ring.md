# ui(stopwatch): animated progress ring + state-driven display

- **Date:** 2026-08-02 17:25
- **Iteration:** 2
- **Commit:** c4f0118

## What changed

The stopwatch screen's elapsed-time display is now wrapped in
a circular progress ring (`CustomPaint`) that sweeps around as
the stopwatch runs. The display text is state-driven
(running / paused / idle) instead of elapsed-only.

- `_StopwatchDisplay` takes the full `StopwatchState` (was:
  bare `Duration`) and renders a `_ProgressRing` around the
  digits. The ring shows fractional progress through the
  current minute (or hour, once we cross 1h) so the user has
  a peripheral cue that time is moving even when they aren't
  reading the digits. A gentle scale + opacity pulse runs
  while the stopwatch is running; the ring is static and muted
  when idle, and frozen (no pulse) when paused.
- The ring colour tracks state: primary when running,
  tertiary when paused, outline when idle.
- The digit text sits inside the ring in a `FittedBox` so
  multi-hour durations (H:MM:SS.hh) don't overflow; the ring
  stays a constant size regardless of text length.
- Sub-second progress uses the 50 ms tick (not the display
  second) so the sweep is visibly smooth — the digits still
  flip only once per second.

## Why

User feedback that a bare digit display makes it hard to tell
at a glance whether the stopwatch is actually running (vs.
frozen) and how far through a minute/lap you are. The ring
is a glance-readable peripheral signal that complements the
digits.

## Files touched

- lib/presentation/screens/stopwatch_screen.dart

## Verification

- [x] `flutter analyze` clean (re-verified in batch).
- [x] `flutter test` — 294 tests pass (the change is a
      pure-UI refactor; the `stopwatch_provider_test` covers
      the elapsed-time accuracy that the ring visualises).
- [ ] Manual on-device: confirm the ring sweeps while
      running, freezes on pause, and that the digits still
      match the lap-list times.
