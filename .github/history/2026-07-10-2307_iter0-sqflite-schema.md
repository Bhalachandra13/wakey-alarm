# Sqflite schema and migration scaffold

- **Date:** 2026-07-10 23:07
- **Iteration:** 0
- **Commit:** 2e28175

## What changed

Added the v1 SQLite database service with `alarms` and `timers` tables,
plus migration scaffolding and an in-memory schema test.

## Why

This implements the Iteration 0 persistence foundation from
`docs/requirements.md` section 3 and `docs/workflow_plan.md`.

## Files touched

- lib/data/wakey_database.dart
- test/data/wakey_database_test.dart
- pubspec.yaml
- pubspec.lock

## Verification

- [x] `dart format .` clean
- [x] `flutter analyze` clean
- [x] `flutter test` passing
- [ ] Manual on-device check needed? no
