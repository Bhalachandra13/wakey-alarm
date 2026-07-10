# Foundation dependencies and layer structure

- **Date:** 2026-07-10 23:02
- **Iteration:** 0
- **Commit:** cf2cc84

## What changed

Added the Iteration 0 Flutter dependencies and tracked the required data,
domain, presentation, and native bridge layer folders.

## Why

This provides the package and folder foundation required by
`docs/workflow_plan.md` before adding persistence, providers, and platform
bridge code.

## Files touched

- pubspec.yaml
- pubspec.lock
- lib/data/
- lib/domain/
- lib/presentation/
- lib/native_bridge/

## Verification

- [x] `dart format .` clean
- [x] `flutter analyze` clean
- [x] `flutter test` passing
- [ ] Manual on-device check needed? no
