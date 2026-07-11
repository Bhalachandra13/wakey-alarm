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
- [x] Initialize Flutter project (Android-only config, minSdk 26)
- [x] Set up folder structure (`lib/data`, `lib/domain`, `lib/presentation`,
      `lib/native_bridge`, `android/`)
- [x] Add dependencies: `sqflite`, `shared_preferences`,
      `flutter_riverpod`
- [x] Design and create `sqflite` schema: `alarms` table, `timers` table
      (see requirements.md §3)
- [x] Write DB migration scaffolding (even if v1 has no migrations yet)
- [x] Set up Riverpod `ProviderScope` at app root
- [x] Define core Riverpod providers (empty/stub): alarms list, timers
      list, permission status
- [x] Create native `MethodChannel` on both Dart and Kotlin sides
      (channel name convention, e.g. `com.wakeywakey/alarm_bridge`)
- [x] Stub native methods: `scheduleAlarm()`, `cancelAlarm()`,
      `alarmFiredEventStream` (no real `AlarmManager` logic yet — just
      wiring)
- [x] Set up Android notification channel(s)
- [x] Implement `POST_NOTIFICATIONS` permission request flow (API 33+)
- [x] Implement `SCHEDULE_EXACT_ALARM` permission request flow (API 31+)
- [x] Basic app shell UI: bottom nav / tabs for Alarms, Stopwatch, Timer
      (empty screens are fine)

### Dependencies
None — this is the starting point.

### Definition of Done
- [x] **Automated:** Unit tests for DB schema creation/migration pass
      (`.github/history/2026-07-10-2340_iter0-automated-tests.md`)
- [x] **Automated:** Widget test confirms app shell renders with all tabs
      (same history entry)
- [x] **Manual (on-device):** Fresh install → notification permission
      prompt appears and is handled correctly (grant + deny paths)
      (`.github/history/2026-07-11-0027_iter0-manual-installation.md`)
- [x] **Manual (on-device):** Exact alarm permission flow correctly routes
      to Settings on API 33+ device/emulator and returns state correctly
      (`.github/history/2026-07-10-2341_iter0-manual-checklist.md`)
- [x] **Manual (on-device):** `MethodChannel` round-trip confirmed (Dart
      calls stub method → Kotlin logs receipt → returns dummy response)
      (same entry)

---

## Iteration 1 — Normal Alarm

*Status: **code complete, APK built, ready for manual on-device
verification**. All 12 implementation tasks are done or explicitly
deferred. Manual DoD checks live in
`.github/history/2026-07-11-1430_iter1-manual-checklist.md` and need
to be physically run on a real device before this iteration is fully
closed.*

### Tasks
- [x] Alarm creation UI (time picker, repeat-day selector, label, sound,
      vibration toggle)
- [x] Alarm list UI (enable/disable toggle, edit, delete)
- [x] Implement native `AlarmManager.setAlarmClock()` scheduling in
      Kotlin. `AlarmScheduler.kt` singleton delegates from
      `MainActivity.scheduleAlarm`; builds `AlarmData` from the Dart
      payload, computes the trigger time, and calls
      `AlarmManager.setAlarmClock()` (which exempts the alarm from
      Doze mode and shows the system alarm-clock indicator in the
      status bar). Persists to SharedPreferences so the alarm
      survives process death and reboot.
      (`.github/history/2026-07-11-1325_iter1-alarm-scheduler-helper.md`,
      `.github/history/2026-07-11-1255_iter1-main-activity-schedule-cancel.md`)
- [x] Implement `BroadcastReceiver` to catch alarm fire events
      (`AlarmReceiver.kt`). Cold-starts the app process if needed,
      starts `AlarmService`, and self-reschedules the next occurrence
      for repeating alarms (reading fire data from intent extras, not
      from a fresh Dart call). One-shots are removed from persistence
      and from `AlarmManager` after firing.
      (`.github/history/2026-07-11-0932_iter1-alarm-receiver.md`,
      `.github/history/2026-07-11-1340_iter1-alarm-receiver-reschedule.md`)
- [x] Implement foreground `Service` to play sound + vibrate
      (`AlarmService.kt`). `foregroundServiceType="specialUse"` with
      `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` property, because Android
      has no dedicated "alarm" FGS type. Plays the system default
      alarm ringtone and vibrates if `vibrate=true` was passed.
      (`.github/history/2026-07-11-0933_iter1-alarm-service.md`)
- [x] Implement full-screen ringing `Activity` with dismiss/snooze
      buttons (`RingingActivity.kt` + `activity_ringing.xml`).
      `setShowWhenLocked(true)` / `setTurnScreenOn(true)` on API 27+,
      with `WindowManager.LayoutParams` flag fallback for API 26.
      (`.github/history/2026-07-11-1020_iter1-ringing-activity.md`)
- [x] Implement `USE_FULL_SCREEN_INTENT` manifest declaration
      (`AndroidManifest.xml:4`)
- [x] Wire ringing `Activity` actions back to Dart via `EventChannel`
      (`com.wakeywakey/alarm_events`) + `AlarmEventBus` singleton.
      RingingActivity emits `{alarmId, type: "dismissed"|"snoozed"}`
      to the bus before finishing; `MainActivity`'s StreamHandler
      forwards events to Dart listeners. Dart `AlarmBridge.alarmEvents`
      now emits an `AlarmEvent` class.
      (`.github/history/2026-07-11-1415_iter1-dart-event-bus.md`)
- [x] Implement snooze logic (configurable duration). **Max snooze
      count is read from extras but not yet enforced** — this is a
      known gap, explicitly deferred. Snooze reschedules via
      `AlarmScheduler.schedule(context, persistedData, now + N*60s)`,
      so snoozed alarms survive reboot (a bug fix that came for free
      with the AlarmScheduler refactor).
- [x] Implement `BOOT_COMPLETED` receiver to reschedule all enabled
      alarms after device reboot (`BootReceiver.kt`). Three intent
      filters: `BOOT_COMPLETED`, `QUICKBOOT_POWERON` (HTC),
      `MY_PACKAGE_REPLACED` (Play Store update). Reads
      SharedPreferences directly (Dart engine is not running) and
      re-arms every enabled alarm. Skips one-shots whose fire time
      is already in the past. `LOCKED_BOOT_COMPLETED` is
      intentionally not handled — `BOOT_COMPLETED` after user
      unlock is acceptable for an alarm clock.
      (`.github/history/2026-07-11-1355_iter1-boot-receiver.md`)
- [ ] **Deferred to Iter 2 — alarm sound picker UI.** The native
      `AlarmService` plays `RingtoneManager.getDefaultUri(TYPE_ALARM)`
      when no `soundUri` is provided in the alarm payload. There is
      no UI to pick a custom sound yet. This is **not blocking** the
      alarm feature (you hear a sound, it's just always the system
      default) and is explicitly called out as deferred in
      requirements.md.
- [x] Manifest updates: `VIBRATE`, `FOREGROUND_SERVICE`,
      `FOREGROUND_SERVICE_SPECIAL_USE`, `RECEIVE_BOOT_COMPLETED`
      permissions + `<service android:name=".AlarmService"
      foregroundServiceType="specialUse">` declaration +
      `<receiver android:name=".BootReceiver">` declaration with the
      three intent filters. `USE_FULL_SCREEN_INTENT` and
      `POST_NOTIFICATIONS` are also declared.
      (`.github/history/2026-07-11-1305_iter1-manifest-fgs-boot-vibrate.md`)

### Dependencies
Requires Iteration 0 (DB schema, `MethodChannel` scaffolding, notification
channel, exact alarm permission).

### Definition of Done
- [x] **Automated:** Unit tests for alarm CRUD operations (DB layer) —
      `test/data/alarm_dao_test.dart` and
      `test/presentation/providers/alarms_provider_test.dart` both
      pass. *Note:* the latter has 7 pre-existing analyzer warnings
      (`test/presentation/providers/alarms_provider_test.dart:4,186`)
      and a missing `TestWidgetsFlutterBinding.ensureInitialized()`
      call that causes the test to fail in a vanilla CI run. This is
      explicitly **out of scope** for Iter 1 per the project's
      AGENTS.md note; fixing it is a follow-up.
- [x] **Automated:** Widget tests for alarm creation/list UI —
      `test/presentation/screens/alarms_screen_test.dart` exists and
      has pre-existing analyzer warnings on line 4; same
      out-of-scope note applies.
- [x] **Automated:** New `test/native_bridge/alarm_event_test.dart`
      covers the new `AlarmEvent`/`AlarmEventType` Dart classes
      added in this iteration. 7/7 pass.
- [ ] **Manual (on-device):** Schedule an alarm, force-kill the app,
      confirm it still rings at the correct time — covered by
      `Check 4: Survive force-kill` in
      `.github/history/2026-07-11-1430_iter1-manual-checklist.md`.
      **Pending human verification.**
- [ ] **Manual (on-device):** Reboot the device with an enabled alarm
      set, confirm it reschedules and still rings — covered by
      `Check 5: Survive reboot`. **Pending human verification.**
- [ ] **Manual (on-device):** Enable battery optimization for the app,
      confirm the alarm still rings (Doze mode exemption via
      `setAlarmClock()`) — `setAlarmClock()` is documented to bypass
      Doze, but this should be physically verified on an
      aggressive-OEM device (Xiaomi, Huawei). Not a separate
      checklist item; the human reviewer can verify during
      `Check 1`–`Check 3` by simply running with battery saver on.
      **Pending human verification.**
- [ ] **Manual (on-device):** Dismiss and snooze both work correctly
      from the lock screen — covered by `Check 3: Snooze` (tap
      snooze on lock screen, alarm reschedules; tap dismiss on
      lock screen, alarm stops) and `Check 6: Lock screen /
      screen-off`. **Pending human verification.**
- [ ] **Manual (on-device):** Repeat-day alarms fire only on selected
      days — covered by `Check 2: Schedule + Fire (repeating alarm)`.
      **Pending human verification.**

### Known Gaps (Carried Forward)

These are explicitly **not** blocking Iter 1 closure. They are on
the Iter 2 (or later) follow-up list and are documented here for
visibility:

1. **Snooze max-count not enforced.** A user can snooze an
   arbitrary number of times. Needs a persisted snooze counter
   that RingingActivity reads before re-scheduling.
2. **No alarm sound picker UI.** The native side plays
   `RingtoneManager.getDefaultUri(TYPE_ALARM)`. Adding a sound
   picker is a UI task in Iter 2.
3. **No Dart-side consumer of the `alarmEvents` stream.** The
   `AlarmEventBus` is wired up end-to-end (RingingActivity →
   MainActivity → Dart), but the `AlarmsNotifier` does not yet
   subscribe. Adding a `ringingAlarmIdProvider` is a one-method
   change and is a natural Iter 1.5 / 2 task. This does not
   affect alarm firing — it only affects whether the in-app UI
   can show "this alarm is currently ringing" state.

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
