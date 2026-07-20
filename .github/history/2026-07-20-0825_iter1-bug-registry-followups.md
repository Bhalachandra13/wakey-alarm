# Iter 1 — Resolve remaining known gaps from bug registry

- **Date:** 2026-07-20 08:25
- **Iteration:** 1
- **Scope:** docs + test cleanup (no functional code change)

## What changed

Addresses the two remaining actionable items from
`.github/history/2026-07-20-1200_iter1-bug-registry.md` §4
("Known Gaps / Open Issues"):

1. **GAP 3 — stale docs:** Removed the
   "No Dart-side consumer of the `alarmEvents` stream" item from
   `docs/workflow_plan.md` §Iteration 1 Known Gaps. The work was
   already landed in commit `550ae30` (BUG E): both
   `ringingAlarmIdProvider` and `AlarmsNotifier` now consume the
   EventChannel, and dismiss/snooze outcomes are mirrored into the
   sqflite database. The remaining two known gaps (snooze-count UI
   and sound-picker UI) are explicitly deferred to Iter 2 and are
   documented as such, with the snooze-count item updated to
   reflect that the native-side enforcement now works (only the
   `EditAlarmScreen` UI control is still missing).
2. **GAP 4 — pre-existing test failures/warnings:** Cleaned up
   `test/presentation/providers/alarms_provider_test.dart` (which
   was failing every test with "Binding has not yet been
   initialized" because the notifier's `build()` calls
   `ref.listen` on `alarmEventsProvider`):
   - Added `TestWidgetsFlutterBinding.ensureInitialized();` at the
     top of `main()`.
   - Added a `_FakeAlarmBridge` and override
     `alarmBridgeProvider` so the notifier can build and the
     scheduler can call `scheduleAlarm` / `cancelAlarm` without
     hitting the missing native MethodChannel.
   - Override `alarmEventsProvider` with `Stream.empty()` — the
     notifier only cares about `snoozed` / `dismissed` events and
     none of these tests exercise that path. A never-completing
     broadcast stream would otherwise keep the test isolate alive
     past the test function returning, causing a spurious 30s
     timeout.
   - Removed the unused `alarm_dao` import and the unused `id`
     binding in the `refresh reloads from database` test.
   Also cleaned up three pre-existing analyzer warnings in
   `test/`:
   - `test/domain/alarm_test.dart`: removed the unused `now`
     local.
   - `test/presentation/screens/alarms_screen_test.dart`: added
     braces around the bare `break;` statements flagged by
     `curly_braces_in_flow_control_structures`.

The BUG A–E fixes in the bug registry were already landed in
commits `2b8028c` and `550ae30`. This commit does not re-fix any
of them; it only picks up the open follow-up items that the
registry itself called out as "should be cleaned up before Iter 2
starts so the automated DoD is truly green."

## Why

`.github/history/2026-07-20-1200_iter1-bug-registry.md` §7
("Recommendations for Iteration 2") lists, in order:

1. Fix the 7 pre-existing test warnings/failures before adding
   new code.
2. Update `docs/workflow_plan.md` to mark the `alarmEvents`
   consumer gap as resolved.

This commit does both.

## Files touched

- `docs/workflow_plan.md` — removed the resolved `alarmEvents`
  consumer gap, tightened the wording on the two remaining
  Iter-2 gaps.
- `test/domain/alarm_test.dart` — dropped unused `now` local.
- `test/presentation/providers/alarms_provider_test.dart` —
  binding init, fake bridge, `alarmEventsProvider` override,
  unused-import + unused-local cleanup.
- `test/presentation/screens/alarms_screen_test.dart` — braces
  around bare `break;` statements (2 sites).
- `.github/history/2026-07-20-0825_iter1-bug-registry-followups.md`
  — this entry.

## Verification

- [x] `dart analyze test/` clean
- [x] `dart format --output=none --set-exit-if-changed .` clean
- [x] `flutter test` — **66 pass, 0 fail** (was 57 pass / 9 fail
      before this commit)
- [ ] `flutter analyze` (full project) — still slow on this WSL
      mount; `test/` and `lib/` analyze clean individually
- [ ] Manual on-device — N/A (no functional change)

## Notes

- The fake-bridge pattern (`_FakeAlarmBridge implements
  AlarmBridge`) is now duplicated between
  `alarms_provider_test.dart` and `alarms_screen_test.dart`. A
  follow-up commit could lift it into a shared
  `test/_helpers/fake_alarm_bridge.dart`, but that's a refactor
  outside the scope of this bugfix pass.
- The `eventController` inside the new `_FakeAlarmBridge` is
  currently dead code (the test overrides `alarmEventsProvider`
  directly, so the bridge's own stream is never consumed). Kept
  it for symmetry with the existing `_FakeAlarmBridge` in
  `alarms_screen_test.dart` and in case a future test wants to
  drive events through the bridge instead of via the override.
