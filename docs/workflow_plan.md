# Wakey-Wakey — Development Workflow & Iteration Plan

This is a living document. Check off tasks as you complete them. Each
iteration has a **Definition of Done (DoD)** combining automated tests and
a manual on-device checklist — an iteration isn't complete until both are
satisfied, not just "looks done in the emulator."

---

## Iteration 0 — Foundation

*No user-visible feature. Produces the plumbing every later iteration
depends on.*

### Tasks
- [ ] Initialize Flutter project (Android-only config, minSdk 26)
- [ ] Set up folder structure (`lib/data`, `lib/domain`, `lib/presentation`,
      `lib/native_bridge`, `android/`)
- [ ] Add dependencies: `sqflite`, `shared_preferences`,
      `flutter_riverpod`
- [ ] Design and create `sqflite` schema: `alarms` table, `timers` table
      (see requirements.md §3)
- [ ] Write DB migration scaffolding (even if v1 has no migrations yet)
- [ ] Set up Riverpod `ProviderScope` at app root
- [ ] Define core Riverpod providers (empty/stub): alarms list, timers
      list, permission status
- [ ] Create native `MethodChannel` on both Dart and Kotlin sides
      (channel name convention, e.g. `com.wakeywakey/alarm_bridge`)
- [ ] Stub native methods: `scheduleAlarm()`, `cancelAlarm()`,
      `alarmFiredEventStream` (no real `AlarmManager` logic yet — just
      wiring)
- [ ] Set up Android notification channel(s)
- [ ] Implement `POST_NOTIFICATIONS` permission request flow (API 33+)
- [ ] Implement `SCHEDULE_EXACT_ALARM` permission request flow (API 31+)
- [ ] Basic app shell UI: bottom nav / tabs for Alarms, Stopwatch, Timer
      (empty screens are fine)

### Dependencies
None — this is the starting point.

### Definition of Done
- [ ] **Automated:** Unit tests for DB schema creation/migration pass
- [ ] **Automated:** Widget test confirms app shell renders with all tabs
- [ ] **Manual (on-device):** Fresh install → notification permission
      prompt appears and is handled correctly (grant + deny paths)
- [ ] **Manual (on-device):** Exact alarm permission flow correctly routes
      to Settings on API 33+ device/emulator and returns state correctly
- [ ] **Manual (on-device):** `MethodChannel` round-trip confirmed (Dart
      calls stub method → Kotlin logs receipt → returns dummy response)

---

## Iteration 1 — Normal Alarm

### Tasks
- [x] Alarm creation UI (time picker, repeat-day selector, label, sound,
      vibration toggle)
- [x] Alarm list UI (enable/disable toggle, edit, delete)
- [ ] Implement native `AlarmManager.setAlarmClock()` scheduling in Kotlin
- [ ] Implement `BroadcastReceiver` to catch alarm fire events
- [ ] Implement foreground `Service` to play sound + vibrate
- [ ] Implement full-screen ringing `Activity` with dismiss/snooze buttons
- [ ] Implement `USE_FULL_SCREEN_INTENT` manifest declaration
- [ ] Wire ringing `Activity` actions back to Dart via `MethodChannel`
      (dismiss/snooze events)
- [ ] Implement snooze logic (configurable duration, optional max count)
- [ ] Implement `BOOT_COMPLETED` receiver to reschedule all enabled alarms
      after device reboot
- [ ] Alarm sound picker (system sounds or bundled defaults)

### Dependencies
Requires Iteration 0 (DB schema, `MethodChannel` scaffolding, notification
channel, exact alarm permission).

### Definition of Done
- [ ] **Automated:** Unit tests for alarm CRUD operations (DB layer)
- [ ] **Automated:** Widget tests for alarm creation/list UI
- [ ] **Manual (on-device):** Schedule an alarm, force-kill the app,
      confirm it still rings at the correct time
- [ ] **Manual (on-device):** Reboot the device with an enabled alarm set,
      confirm it reschedules and still rings
- [ ] **Manual (on-device):** Enable battery optimization for the app,
      confirm the alarm still rings (Doze mode exemption via
      `setAlarmClock()`)
- [ ] **Manual (on-device):** Dismiss and snooze both work correctly from
      the lock screen
- [ ] **Manual (on-device):** Repeat-day alarms fire only on selected days

---

## Iteration 2 — Stopwatch

### Tasks
- [ ] Stopwatch UI (start/pause/resume/reset/lap)
- [ ] Riverpod state notifier for stopwatch (pure Dart, no persistence)
- [ ] Lap time list display

### Dependencies
Requires Iteration 0 (app shell, Riverpod setup). Does **not** depend on
Iteration 1's native pipeline.

### Definition of Done
- [ ] **Automated:** Unit tests for stopwatch state notifier
      (start/pause/reset/lap logic, elapsed time accuracy)
- [ ] **Automated:** Widget tests for stopwatch UI interactions
- [ ] **Manual (on-device):** Confirm stopwatch resets on app kill
      (expected/accepted behavior — verify it's graceful, not a crash)
- [ ] **Manual (on-device):** Confirm timing accuracy over a multi-minute
      run (no significant drift while app is foregrounded)

---

## Iteration 3 — Timer

### Tasks
- [ ] Timer creation UI (duration input, optional label)
- [ ] Timer list UI (for multiple concurrent timers, if supported —
      confirm with product owner if multiple simultaneous timers are
      in scope)
- [ ] Reuse Iteration 1's native `AlarmManager` pipeline: schedule as
      `now + duration`
- [ ] Reuse ringing/dismiss/snooze UI with timer-specific
      label/iconography
- [ ] Countdown display UI (remaining time, pause/cancel before it fires)
- [ ] Persist `remaining_seconds` periodically for display continuity if
      app is reopened before firing

### Dependencies
Requires Iteration 1 (native alarm-firing pipeline must exist and be
proven reliable before extending it here).

### Definition of Done
- [ ] **Automated:** Unit tests for timer CRUD + countdown calculation
- [ ] **Automated:** Widget tests for timer creation/list UI
- [ ] **Manual (on-device):** Set a short timer, background the app,
      confirm it fires on time
- [ ] **Manual (on-device):** Force-kill the app mid-countdown, confirm
      the timer still fires (same native guarantee as Iteration 1)
- [ ] **Manual (on-device):** Cancel a timer before it fires, confirm no
      stray notification appears

---

## Iteration 4 — Geofencing Alarm

*The core differentiator feature. Largest iteration — expect this to take
longer than the others.*

### Tasks
- [ ] Add `google_maps_flutter` dependency, obtain and configure Google
      Maps API key
- [ ] Complete Play Console Data Safety declaration for precise location
      collection
- [ ] Map-based location picker screen with Places Autocomplete search
- [ ] Radius selector (slider/stepper, 200 m–20 km, default 2 km) with
      visual circle overlay on map
- [ ] Extend alarm creation flow to support `trigger_type = LOCATION`
- [ ] Implement foreground location permission request (contextual, at
      first geofence alarm creation)
- [ ] Implement background location permission flow with pre-explanation
      screen before the system Settings prompt
- [ ] Implement native `GeofencingClient` integration
      (`addGeofences()` / `removeGeofences()`) via `MethodChannel`
- [ ] Implement geofence transition `BroadcastReceiver`
      (`GEOFENCE_TRANSITION_ENTER`)
- [ ] Implement "Start Trip" explicit arming flow:
  - [ ] Check current location against radius before arming
  - [ ] Show warning if already inside radius
  - [ ] Register geofence only after confirmation
- [ ] Reuse ringing/dismiss/snooze UI for geofence-triggered alarms
- [ ] Implement one-shot auto-disarm: unregister geofence + flip
      `is_armed = false` after fire + dismiss/snooze
- [ ] Battery optimization exemption nudge (one-time) with OEM-aware
      instructions where feasible
- [ ] Persistent "health check" warning banner on alarm list if
      permissions/battery optimization are incomplete for any armed
      geofence alarm

### Dependencies
Requires Iteration 1 (ringing/dismiss/snooze UI and native alarm-service
pattern are reused here) and Iteration 0 (permission-flow patterns
established in Iteration 0 are extended here for location).

### Definition of Done
- [ ] **Automated:** Unit tests for geofence CRUD, radius validation
      (200 m–20 km bounds), arm/disarm state transitions
- [ ] **Automated:** Widget tests for map picker and radius selector UI
- [ ] **Manual (on-device):** Create a geofence alarm at a real nearby
      location, arm it, physically travel into the radius, confirm it
      fires
- [ ] **Manual (on-device):** Attempt to arm while already inside the
      radius, confirm the warning is shown and geofence is not registered
- [ ] **Manual (on-device):** Force-kill the app after arming, confirm the
      geofence still triggers (native `GeofencingClient` survives app
      death)
- [ ] **Manual (on-device):** After firing and dismissing, confirm the
      alarm auto-disarms and does not refire on GPS jitter near the
      boundary
- [ ] **Manual (on-device):** Deny background location permission,
      confirm the app clearly communicates the feature won't work
      reliably (no silent failure)
- [ ] **Manual (on-device):** Test on at least one OEM device known for
      aggressive battery optimization (e.g., Xiaomi/MIUI) with the
      optimization exemption granted vs. not granted, to confirm the
      health-check warning behaves correctly

---

## General Notes for Every Iteration

- Automated tests (unit + widget) should run in CI on every commit.
- Manual on-device checklists are **not optional** for any iteration that
  touches native code (1, 3, 4) — emulator-only testing is insufficient
  for verifying `AlarmManager`/`GeofencingClient` reliability.
- An iteration is only "done" when both the automated and manual DoD
  boxes are checked, not when the UI merely looks complete.
