# 2026-08-04 08:05 — Iter5 — UX: clearer "Allow all the time" location copy

- **Date:** 2026-08-04 08:05
- **Iteration:** 5 (UI clarity from on-device testing)
- **Commit:** *(filled in after committing)*

## Symptom
On-device testing on a second Pixel 8 produced the same
"Could not arm geofence alarm" failure the user already saw
in Iter 4. Investigation showed both devices had identical
permissions EXCEPT for one thing: the wife\u2019s phone had
location granted as "Allow only while using the app" instead
of "Allow all the time". The system dialog\u2019s default-first
option is the foreground-only one, and the existing copy in
the wizard and the pre-Settings explanation screen did not
make it clear that this choice was the wrong one for a
geofence alarm.

## Fix
Three changes, all in the permission UX, all with the goal
of making "Allow all the time" the obvious choice.

1. **`lib/presentation/screens/background_location_explanation_screen.dart`**:
   the screen that appears after the user has already picked
   the wrong option and we need to send them to system
   Settings. Rewritten to add:
   * a warning callout explicitly named '"Allow only while
     using the app" is not enough' with the consequence
     (alarm doesn\u2019t fire when the app is in the background);
   * a visual mockup of the Android Settings Location page
     rendered with Flutter widgets, showing the four radio
     options and highlighting "Allow all the time" with a
     primary-coloured border, a filled radio button, and a
     "Pick this one" pill;
   * a numbered 4-step list ("Tap Open Settings" \u2192 "Tap
     Location" \u2192 "Choose Allow all the time" \u2192 "If Android
     asks Use precise location, pick Precise");
   * a privacy note in a secondary-container card.

2. **`lib/presentation/screens/permissions_setup_screen.dart`**:
   the wizard's checklist row title changed from "Location
   (for geofence alarms)" to "Precise location, all the
   time" and the description now names the OS wording
   verbatim: 'Android calls this "Allow all the time" \u2014
   not "While using the app", which would prevent the
   alarm from firing when the app is closed.'

3. Same file, in `PermissionsSetupFlow.runAllMissing`:
   added a **pre-foreground heads-up AlertDialog** that
   fires *before* the system foreground dialog, so the
   user is mentally prepared to pick "Allow all the time"
   when the OS dialog appears. The dialog explicitly names
   the wrong option and states the consequence.

## Tests
- Updated `permissions_setup_screen_test.dart`:
  - 'renders the checklist' test now expects
    'Precise location, all the time' instead of
    'Location (for geofence alarms)'.
  - 'Set up button runs the flow' test no longer needs to
    dismiss the heads-up dialog because it has no LOCATION
    alarm; a comment was added to that effect.
  - New test 'shows the pre-foreground heads-up dialog when
    a LOCATION alarm is set and location is denied' creates
    a fake `_LocationAlarmsNotifier`, sets geofence
    location to `denied`, taps "Set up", asserts the dialog
    is on screen with the key 'locationForegroundHeadsUp' and
    the text '"While using the app" is not enough', then
    taps the "I\u2019ll pick Allow all the time" button and
    verifies the fake bridge recorded the foreground
    request and the dialog is gone.
- Updated `background_location_explanation_screen_test.dart`:
  'renders explanation text and action buttons' test now
  expects the new title and heading, and asserts the
  'bgLocationWhyNotWhileUsingApp' callout key, the
  'bgLocationMockup' key, and the 'bgLocationMockupPickThisBadge'
  pill are all present.

## Verified
- `flutter analyze` on the four touched files: no issues.
- `flutter test`: 329 tests pass (8 in the two screens\u2019
  test files, up from 7 \u2014 the new heads-up test).

## Manual test plan
1. Reinstall the new APK over the existing install (same
   signing key, in-place update).
2. Open the wizard, tap "Set up". The pre-foreground
   heads-up dialog should appear with the "I\u2019ll pick
   Allow all the time" button.
3. Tap the button, then on Android\u2019s system dialog pick
   "Allow all the time" (it should now be obvious which
   one to pick thanks to the earlier heads-up).
4. If the user accidentally picks "Allow only while
   using the app" anyway, the new explanation screen
   should make it impossible to miss the right option:
   the warning callout, the highlighted mockup, and the
   numbered steps all reinforce the same message.

## Out of scope
- Disarm-side DB rollback on `removeGeofences` failure
  (filed as a follow-up in the previous history entry;
  the defensive cleanup in `addGeofence` already makes
  the user-visible bug recoverable on the next arm).
- Showing the visual mockup in the wizard's checklist
  row itself. The pre-foreground dialog + the
  explanation screen are the two places the user makes
  the actual decision, so the mockup belongs there
  rather than in the summary checklist.
