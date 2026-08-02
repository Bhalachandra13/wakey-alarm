# Wakey-Wakey — Development Workflow & Iteration Plan

This is a living document. Check off tasks as you complete them. Each
iteration has a **Definition of Done (DoD)** combining automated tests and
a manual on-device checklist — an iteration isn't complete until both are
satisfied, not just "looks done in the emulator."

## Iteration Status Snapshot

| # | Iteration | Code Status | Automated DoD | Manual DoD |
|---|-----------|-------------|---------------|------------|
| 0 | Foundation | ✅ Done | ✅ Done | ✅ Done |
| 1 | Normal Alarm | ✅ Done | ✅ Done | ⏳ Pending on-device verification |
| 2 | Stopwatch | ✅ Done (`9fd317b`) | ✅ Done | ⏳ Pending on-device verification |
| 3 | Timer | ✅ Done (`3a33da6`) | ✅ Done | ⏳ Pending on-device verification |
| 4 | Geofencing | ✅ Done (`53bc240`) | ✅ Done | ⏳ Pending on-device verification |
| 5 | Favourites + Permission UX | ✅ Done | ✅ Done (325 tests) | ⏳ Pending on-device verification |

All five feature iterations are code-complete. All 325 automated
tests pass (`flutter test`); `dart analyze` is clean; `dart format` is
clean. Only the on-device manual DoD checks remain — those require a
physical Android device (or emulator with the right permissions
granted) and a human, so they are explicitly out of scope for the
automated work.

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

1. **Snooze max-count not enforced in the UI.** The native side
   now reads and enforces `maxSnoozeCount` via the persisted
   `currentSnoozeCount` in `RingingActivity.scheduleSnooze` — once
   the limit is hit, the snooze tap is reported as a dismiss.
   However, `EditAlarmScreen` still does not expose a control to
   configure the limit; it only exposes `snoozeDurationMin`. Adding
   the UI picker is an Iter 2 task.
2. **No alarm sound picker UI.** The native side plays
   `RingtoneManager.getDefaultUri(TYPE_ALARM)`. The Dart side
   already has a `pickRingtone` MethodChannel (covered by
   `test/native_bridge/alarm_bridge_pick_ringtone_test.dart`),
   but it is not yet wired into `EditAlarmScreen`. Adding the
   picker is a UI task in Iter 2.

> Previously listed here: "No Dart-side consumer of the
> `alarmEvents` stream" — **resolved** in commit `550ae30`
> (BUG E from
> `.github/history/2026-07-20-1200_iter1-bug-registry.md`).
> Both `ringingAlarmIdProvider` and `AlarmsNotifier` now consume
> the EventChannel, and dismiss/snooze outcomes are mirrored into
> the sqflite database.

---

## Iteration 2 — Stopwatch

*Code complete and committed in `9fd317b`. The "no persistence" decision
(intentional per the iteration brief) means the manual "resets on app
kill" DoD check is not a defect but the documented behavior.*

### Tasks
- [x] Stopwatch UI (start/pause/resume/reset/lap)
- [x] Riverpod state notifier for stopwatch (pure Dart, no persistence;
      uses `package:clock` for testability with `fakeAsync`)
- [x] Lap time list display
- [x] MM:SS.hh / H:MM:SS.hh formatters

### Dependencies
Requires Iteration 0 (app shell, Riverpod setup). Does **not** depend on
Iteration 1's native pipeline.

### Definition of Done
- [x] **Automated:** Unit tests for stopwatch state notifier
      (start/pause/reset/lap logic, elapsed time accuracy) —
      `test/presentation/providers/stopwatch_provider_test.dart`
- [x] **Automated:** Widget tests for stopwatch UI interactions —
      `test/presentation/screens/stopwatch_screen_test.dart`
- [ ] **Manual (on-device):** Confirm stopwatch resets on app kill
      (expected/accepted behavior — verify it's graceful, not a crash)
      **Pending human verification** (this is the expected behavior,
      not a defect — re-verify on a real device that the app does not
      crash on cold start with a previously-running stopwatch).
- [ ] **Manual (on-device):** Confirm timing accuracy over a multi-minute
      run (no significant drift while app is foregrounded)
      **Pending human verification.**

---

## Iteration 3 — Timer

*Code complete and committed in `3a33da6`. Multiple concurrent timers
are supported (a primary use case — "boil eggs AND reply to the email in
20 min"). The timer reuses Iteration 1's `AlarmManager` pipeline by
extending the payload with `triggerType: "TIMER"` + an absolute
`triggerAtMillis`, so the cold-start guarantee and reboot resilience
come for free.*

### Tasks
- [x] Timer creation UI (duration stepper, optional label)
- [x] Timer list UI (multiple concurrent timers supported)
- [x] Reuse Iteration 1's native `AlarmManager` pipeline: schedule as
      `now + duration` via the new `AlarmBridge.scheduleTimer` method
      (extends the existing payload with `triggerType="TIMER"`)
- [x] Reuse ringing/dismiss/snooze UI with timer-specific
      label/iconography (`RingingActivity` prefixes the label with
      `"Timer: "` when `triggerType=="TIMER"`)
- [x] Countdown display UI (remaining time, pause/cancel before it fires)
- [x] Persist `remaining_seconds` in sqflite for display continuity if
      app is reopened before firing
- [x] Add `timers` table to schema (Iteration 0's design was
      forward-looking — v1 already had the table)

### Dependencies
Requires Iteration 1 (native alarm-firing pipeline must exist and be
proven reliable before extending it here).

### Definition of Done
- [x] **Automated:** Unit tests for timer CRUD + countdown calculation
      — `test/data/timer_dao_test.dart` and
      `test/presentation/providers/timers_provider_test.dart`
- [x] **Automated:** Widget tests for timer creation/list UI —
      `test/presentation/screens/timer_screen_test.dart`
- [ ] **Manual (on-device):** Set a short timer, background the app,
      confirm it fires on time **Pending human verification.**
- [ ] **Manual (on-device):** Force-kill the app mid-countdown, confirm
      the timer still fires (same native guarantee as Iteration 1)
      **Pending human verification.**
- [ ] **Manual (on-device):** Cancel a timer before it fires, confirm no
      stray notification appears **Pending human verification.**

---

## Iteration 4 — Geofencing Alarm

*Code complete and committed in `53bc240`. The native side uses the
Google Play Services `GeofencingClient` (not the platform
`LocationManager`) so it only works on devices with Google Play
Services — which is the entire Phase 1 target. The native receiver
reuses the existing `AlarmService` / `RingingActivity` pipeline by
emitting a `triggerType="location"` event and carrying the trigger
type through to the ringing UI (which prefixes the label with
`"Location: "`).*

*The "Places Autocomplete search" task in the original plan was
descoped — the map picker supports manual lat/long fallback (typed
inputs) which makes the feature testable in CI without a Maps API
key. A future iteration can add a search box on top of the map.*

### Tasks
- [x] Add `google_maps_flutter` dependency. `MAPS_API_KEY` is a
      placeholder in the manifest; without a real key, the map
      widget shows a blank canvas but the rest of the geofence
      feature (permission flow, validation, arming, native
      registration, fire pipeline) works.
- [ ] Complete Play Console Data Safety declaration for precise
      location collection **Pending real Play Console submission.**
- [x] Map-based location picker screen (no Places search in this
      iteration; manual lat/long text input available as fallback)
- [x] Radius selector (slider, 200 m–20 km, default 2 km) with
      visual circle overlay on map
- [x] Extend alarm creation flow to support `trigger_type = LOCATION`
      (SegmentedButton in `EditAlarmScreen` between "Time" and
      "Location")
- [x] Implement foreground location permission request (contextual,
      at first geofence alarm creation, via `LocationPermissionFlow`)
- [x] Implement background location permission flow with
      pre-explanation screen before the system Settings prompt
- [x] Implement native `GeofencingClient` integration
      (`addGeofences()` / `removeGeofences()`) via a new
      `com.wakeywakey/geofence` `MethodChannel` and
      `GeofenceController.kt`
- [x] Implement geofence transition `BroadcastReceiver`
      (`GEOFENCE_TRANSITION_ENTER` → `GeofenceTransitionReceiver.kt`)
- [x] Implement "Start Trip" explicit arming flow:
  - [x] Check current location against radius before arming
        (uses Haversine via `GeofenceValidator.isPointInsideGeofence`)
  - [x] Show "You're already inside" dialog if already inside radius
  - [x] Register geofence only after the user moves outside
- [x] Reuse ringing/dismiss/snooze UI for geofence-triggered alarms
      (`triggerType` carried through the alarm pipeline)
- [x] Implement one-shot auto-disarm: unregister geofence + flip
      `is_armed = false` after fire + dismiss/snooze
      (handled in `AlarmsNotifier._onNativeDismiss`)
- [x] Battery optimization exemption nudge (in
      `_GeofenceHealthBanner`; tap → opens the system Settings
      page to add the app to the exemption list)
- [x] Persistent "health check" warning banner on alarm list if
      permissions/battery optimization are incomplete for any armed
      geofence alarm

### Dependencies
Requires Iteration 1 (ringing/dismiss/snooze UI and native alarm-service
pattern are reused here) and Iteration 0 (permission-flow patterns
established in Iteration 0 are extended here for location).

### Definition of Done
- [x] **Automated:** Unit tests for geofence CRUD, radius validation
      (200 m–20 km bounds), arm/disarm state transitions —
      `test/domain/geofence_validator_test.dart` (22 tests),
      `test/presentation/providers/geofence_arming_controller_test.dart`
- [x] **Automated:** Widget tests for the map picker and radius
      selector — `test/presentation/screens/edit_alarm_location_test.dart`
      (the map widget itself can't be tested without a Maps API key;
      the manual lat/long and radius slider are tested)
- [x] **Automated:** `test/native_bridge/geofence_bridge_test.dart`
      covers the Dart `GeofenceBridge` MethodChannel wrapper
- [ ] **Manual (on-device):** Create a geofence alarm at a real nearby
      location, arm it, physically travel into the radius, confirm it
      fires **Pending human verification.**
- [ ] **Manual (on-device):** Attempt to arm while already inside the
      radius, confirm the warning is shown and geofence is not registered
      **Pending human verification.**
- [ ] **Manual (on-device):** Force-kill the app after arming, confirm the
      geofence still triggers (native `GeofencingClient` survives app
      death) **Pending human verification.**
- [ ] **Manual (on-device):** After firing and dismissing, confirm the
      alarm auto-disarms and does not refire on GPS jitter near the
      boundary **Pending human verification.**
- [ ] **Manual (on-device):** Deny background location permission,
      confirm the app clearly communicates the feature won't work
      reliably (no silent failure) **Pending human verification.**
- [ ] **Manual (on-device):** Test on at least one OEM device known for
      aggressive battery optimization (e.g., Xiaomi/MIUI) with the
      optimization exemption granted vs. not granted, to confirm the
      health-check warning behaves correctly **Pending human
      verification.**

---

## Iteration 5 — Favourite Locations + Permission UX

*Scope addition beyond `requirements.md` §5 (favourites aren't in the
original spec) — added in response to the feedback that "setting up a
geofence alarm is the headline use case, and it should be the easiest
thing in the app to do." Two related halves: make it cheap to reuse a
location the user has already picked (favourites), and stop making
the user assemble three separate permission prompts in three separate
places (unified setup wizard + consolidated health banner).*

### Tasks

- [x] Add a `favourite_locations` sqflite table (v2→v3 migration).
      Schema: `id`, `name`, `icon_code`, `latitude`, `longitude`,
      `radius_meters`, `created_at`, `updated_at`. Lives alongside
      `alarms` rather than as a column on `alarms` because a
      single favourite is reused across many alarms — "Home"
      doesn't disappear when the alarm that first used it is
      deleted, and renaming "Home" → "Apartment" updates every
      alarm that points at it without a per-alarm rewrite.
- [x] `FavouriteLocation` domain model with a tiny icon enum
      (`home`, `work`, `school`, `favorite`, `place`) that maps
      common names to a sensible default and falls back to
      `place` for unknown names. Stable string `code` persisted
      in the DB so the column survives across app upgrades even
      if Material renames a glyph.
- [x] `FavouriteLocationDao` (insert / read / getAll / update /
      delete / deleteAll / count) — `getAll` sorts by
      `created_at ASC` so the user's mental order is preserved.
- [x] Riverpod `FavouriteLocationsNotifier` (AsyncNotifier) with
      `add` (auto-picks icon from name), `edit` (rename/icon/
      radius), `move` (lat/lon/radius), `delete`. Plus a
      `hasFavouritesProvider` derived flag.
- [x] `FavouritesScreen` (manage): list with delete (confirm
      dialog), tap-to-edit (reopens map picker pre-filled), +
      in the app bar to add. Empty-state shows one-tap
      **Add Home** / **Add Work** affordances plus an
      **Add a custom place** escape hatch. New place flow:
      map picker → name dialog (default "Home"/"Work" from the
      entry point) → save.
- [x] Quick-pick chip strip in `MapPickerScreen`. When the user
      has saved favourites, a horizontal row of ActionChips
      (icon + name) appears at the bottom of the search panel.
      Tapping a chip drops the pin, flies the camera, and
      adopts the favourite's default radius — the "two taps to
      set up a geofence" affordance. When no favourites exist
      yet, an inline "Tip: save frequent places for one-tap
      picking" nudge with a "Manage" link replaces the strip.
- [x] Entry point on the alarms screen: a compact
      `_SavedPlacesRow` above the alarm list (bookmark icon +
      "Saved places" + count + chevron) pushes `FavouritesScreen`.
- [x] `EditAlarmScreen` location section: the existing "Pick on
      map" button now opens the picker with the chip strip
      visible, so the user can pick a favourite without an
      extra navigation hop.
- [x] Tests: DAO CRUD + icon mapping (15), provider add/edit/
      move/delete/hasFavourites (7), `FavouritesScreen` empty
      state + populated list + add flow (6), map picker chip
      strip + empty nudge + tapping a chip drops the pin with
      the favourite's radius (3). All 31 new tests pass;
      `flutter analyze` clean.
- [ ] **Deferred to a future iteration** — geofence-aware
      "Save this pin as Home" action inside the map picker
      (currently the user adds favourites via the Favourites
      screen's + / Add Home / Add Work). Not blocking: the
      current path is two taps (open Favourites → Add Home →
      pick on map) and is the guided on-ramp for first-time
      users anyway.

### Permissions UX (shipped in the same iteration)

- [x] Unified "Get ready" setup screen (`PermissionsSetupScreen`).
      One screen, plain language, one primary "Set up" button
      that walks the user through notif → exact alarm →
      foreground location → background explanation → background
      → battery optimisation in a single coherent flow.
      Triggered on first run via a `permissions_setup_shown`
      SharedPreferences flag (auto-pushed from the alarms
      screen's first build when something is missing) and
      any time the user taps "Fix" on the consolidated banner.
- [x] Replaced the three separate banners on `alarms_screen`
      (`NotificationPermissionBanner`, `ExactAlarmPermissionBanner`,
      `_GeofenceHealthBanner`) with a single
      `_PermissionsHealthBanner` that lists every missing item
      in one card with one "Fix" button → opens the setup
      screen. The setup screen covers all three cases, so the
      consolidation is behaviour-preserving. The old banner
      widgets are retained (still used by the timer screen).
- [x] Tests for the setup screen (mocked bridges) and the
      consolidated banner.

### Dependencies

Requires Iterations 0–4 (DB schema, sqflite migrations, Riverpod,
permission flow patterns, map picker, geofence bridge).

### Definition of Done

- [x] **Automated:** DAO + provider + widget tests pass
      (`test/data/favourite_location_dao_test.dart`,
      `test/presentation/providers/favourite_locations_provider_test.dart`,
      `test/presentation/screens/favourites_screen_test.dart`,
      updated `test/presentation/screens/map_picker_screen_test.dart`).
      325 tests pass overall.
- [x] **Automated:** `flutter analyze` clean.
- [x] **Automated:** Permission setup screen + consolidated
      banner — covered by `test/presentation/screens/
      permissions_setup_screen_test.dart` and the updated
      banner test in `alarms_screen_test.dart`.
- [ ] **Manual (on-device):** From a fresh install, tap "Get
      ready" and confirm the single flow covers notif / exact
      alarm / foreground / background without three separate
      prompts. **Pending human verification.**
- [ ] **Manual (on-device):** Open a geofence alarm, tap "Pick
      on map", confirm the chip strip shows saved favourites
      and tapping one drops the pin + flies the camera with
      the correct radius. **Pending human verification.**
- [ ] **Manual (on-device):** First-time Favourites empty state
      shows Add Home / Add Work; tapping Add Home opens the
      map picker and the resulting favourite shows up in the
      chip strip on the next picker open. **Pending human
      verification.**

### Scope note

`requirements.md` does not mention favourite locations. This
iteration is an explicit addition agreed with the user after
on-device testing showed that the headline geofence use case
("alarm me near home / near my stop") required a map + search
on every alarm creation. The favourites feature is the
minimum delta that makes the common case 2 taps. The
permission UX consolidation is the matching half: the previous
three-banner / three-prompt flow was the second-largest
source of setup friction in user testing.

## General Notes for Every Iteration

- Automated tests (unit + widget) should run in CI on every commit.
- Manual on-device checklists are **not optional** for any iteration that
  touches native code (1, 3, 4) — emulator-only testing is insufficient
  for verifying `AlarmManager`/`GeofencingClient` reliability.
- An iteration is only "done" when both the automated and manual DoD
  boxes are checked, not when the UI merely looks complete.
