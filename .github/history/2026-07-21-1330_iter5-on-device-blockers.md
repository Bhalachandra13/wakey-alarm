# Iteration 5 — fix on-device blockers (permission banner, toggle error, duration overflow)

## Status

- Three production blockers found during the first device test
  (Pixel 8, Android 16, API 36) are now fixed and verified by the
  full test suite (189 tests, +6 new). The first blocker
  (`SCHEDULE_EXACT_ALARM` not granted) made every alarm and
  timer schedule call throw a `SecurityException` silently — the
  Dart side rolled back the DB insert, but the user saw no error
  and the toggle visually flipped to "on" with nothing actually
  scheduled in `dumpsys alarm`.

## What changed

- **Permission banner on Alarms screen** —
  `_ExactAlarmPermissionBanner` (mirrors the existing
  `_GeofenceHealthBanner` pattern). Polls
  `permissionBridge.canScheduleExactAlarms()` on mount and shows
  an `InkWell` row that calls
  `permissionBridge.requestExactAlarmPermission()` to open the
  system Settings page. Three widget tests
  (`exact_alarm_banner_test.dart`): shown when missing, hidden
  when granted, tap dispatches the request.

- **Toggle error feedback** —
  `AlarmsNotifier.toggleEnabled` now returns `Future<bool>` —
  the native call's success/failure. The Switch `onChanged` in
  `alarms_screen.dart` awaits the result and shows a 5-second
  SnackBar naming the exact permission to grant
  (`"Alarms & reminders"`) when the schedule call returns false.
  The DB row is still updated to the user's intent (toggle ON)
  so the UI matches the request, but the failure is now
  surfaced. Two widget tests
  (`alarm_toggle_error_test.dart`) cover both the failure and
  the success path.

- **Add Timer Duration row overflow** —
  `DurationStepper` (renamed from the private
  `_DurationStepper`, marked `@visibleForTesting`) now uses
  `mainAxisSize: MainAxisSize.min` on its inner Row and
  `visualDensity: VisualDensity.compact` on both IconButtons,
  plus a 40dp (not 48dp) `SizedBox` for the number. The
  previous layout put 3× 48dp IconButtons + a 48dp number into
  a ~338dp column on a Pixel 8, overflowing by ~26dp; the new
  layout fits with ~20dp to spare. One widget test
  (`duration_overflow_test.dart`) sets the test surface to
  Pixel-8 physical size (1080×2400 @ 2.625 dpr) and asserts
  `tester.takeException()` is null after layout.

## WHY

- All three bugs were unit-test-blind: the Dart side has
  `scheduleAlarm` mocked everywhere, so the SecurityException
  never surfaced in the existing 183 tests. The only honest
  check for native integration is on a real device. The previous
  status said "ready for device" before any device test had
  actually happened — that was a planning error, not a code
  error. Going forward, the DoD for any "done" iteration that
  touches a MethodChannel should include a smoke-test on a
  connected device, not just the unit suite.

## Verification

- `flutter test`: 189 / 189 pass.
- `dart analyze`: 0 issues.
- `dart format --set-exit-if-changed lib test`: clean.
- Device test: pending — see next iteration's history entry.

## Follow-up

- After this lands, the on-device test should be re-run on the
  Pixel 8 to (a) confirm the ExactAlarmPermissionBanner appears
  on first launch, (b) verify the SnackBar surfaces when the
  user toggles an alarm without first granting the permission,
  and (c) verify the Add Timer form no longer renders the
  yellow-and-black overflow stripes on a 411dp-wide surface.

## References

- Prior: `.github/history/2026-07-21-1300_iter4-build-fix-play-services-location.md`
- Bug 1 root cause: Android 12+ requires user-granted
  `SCHEDULE_EXACT_ALARM` for `setAlarmClock`; manifest was
  correct but no UI surfaced the requirement.
- Bug 2 root cause: `AlarmsNotifier.toggleEnabled` discarded
  the native call's return value; the toggle looked armed but
  no `setAlarmClock` had succeeded.
- Bug 3 root cause: 3× 48dp IconButtons + 48dp number in a
  ~338dp column; fixed by `MainAxisSize.min` + compact density.
