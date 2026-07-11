# Iteration 1: Wire AlarmsScreen to AppShell and Fix Widget Test

- **Date:** 2026-07-11 09:07
- **Iteration:** 1
- **Commit:** 20e2f34

## What changed

Wired the `AlarmsScreen` into the first tab of `AppShell` and resolved database-related crashes in the widget test (`test/widget_test.dart`) by overriding `alarmsNotifierProvider` with a mock notifier.

## Why

1. `AppShell` previously displayed an empty stub view (`_EmptyTabView`) for all tabs. Wiring the `AlarmsScreen` to the first tab allows users to view the list of alarms.
2. In the widget test, executing the real database initialization threw exceptions because native method channels for sqlite are not available in the VM test environment. Overriding the Riverpod provider with a mock notifier that returns an empty list immediately bypasses database setup/crashes, preventing infinite frame pumps and ensuring tests pass.

## Files touched

- `lib/presentation/app.dart` — Modified
  - Integrated `AlarmsScreen` into the body of `AppShell` for the "Alarms" tab.
  - Added a `FloatingActionButton` for creating alarms (currently showing a placeholder snackbar).
- `test/widget_test.dart` — Modified
  - Overrode `alarmsNotifierProvider` using a `MockAlarmsNotifier` subclass in `ProviderScope` to return an empty list immediately, bypassing native database integration during widget testing.

## Verification

- ✅ `flutter test` — all 44 tests pass successfully.
- ✅ `flutter analyze` — clean, no issues.
- ✅ `dart format` — all files properly formatted.
