# Riverpod app shell with primary tabs

- **Date:** 2026-07-10 23:12
- **Iteration:** 0
- **Commit:** ad94a41

## What changed

Replaced the generated counter app with a Riverpod-wrapped Wakey-Wakey app
shell and bottom tabs for Alarms, Stopwatch, and Timer.

## Why

This implements the Iteration 0 app root, ProviderScope setup, stub
providers, and basic shell UI required by `docs/workflow_plan.md`.

## Files touched

- lib/main.dart
- lib/presentation/app.dart
- lib/presentation/providers/app_providers.dart
- test/widget_test.dart

## Verification

- [x] `dart format .` clean
- [x] `flutter analyze` clean
- [x] `flutter test` passing
- [ ] Manual on-device check needed? no
