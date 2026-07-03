# Wakey-Wakey — Requirements Document

## 1. Overview

Wakey-Wakey is an Android alarm application built with Flutter. Its core
differentiator is **geofencing-based alarms** — alarms that trigger based on
proximity to a location rather than (or in addition to) a wall-clock time.
This is aimed at use cases like commuters who doze off on transit and want
to be woken a few kilometers before their stop.

Alongside geofencing, the app provides the standard utility trio found in
most clock apps: a normal time-based alarm, a stopwatch, and a timer.

**Phase 1 scope:** Android only.
**Out of scope for Phase 1:** iOS support (deferred to a future phase with
its own research spike, given iOS's stricter background execution and
geofencing region limits).

---

## 2. Tech Stack & Architectural Decisions

| Area | Decision | Rationale |
|---|---|---|
| Platform | Android only, minSdk 26 (Android 8.0 Oreo) | Covers the vast majority of active devices while avoiding the worst of pre-background-permission-model complexity. Geofencing/exact alarms already require handling API 29+/31+/33+ permission changes regardless of floor. |
| Local persistence | `sqflite` for alarms/timers/geofences; `shared_preferences` for simple settings | Alarm/timer/geofence data must survive app kills and reboots, and be readable from background isolates and native broadcast receivers. SQLite is the most proven choice for this in production alarm apps. |
| State management | `Riverpod` | Much of this app's state originates from native events (alarm fired, geofence entered, timer completed) rather than pure UI interaction. Riverpod's `StreamProvider`/`AsyncNotifier` map cleanly onto native `MethodChannel` event streams, with better testability than `Provider` and less boilerplate than `Bloc`. |
| Alarm firing mechanism | Native Android `AlarmManager.setAlarmClock()` → `BroadcastReceiver` → foreground `Service` → full-screen ringing `Activity`, bridged to Flutter via `MethodChannel` | Dart-only timers die when the app/engine is killed — unacceptable for an alarm. `setAlarmClock()` is the same API stock clock apps use: exempt from Doze restrictions, shows the status-bar alarm icon, and supports full-screen intents for lock-screen ringing UI. |
| Geofencing mechanism | Native Android Geofencing API via `LocationServices.getGeofencingClient()` (Google Play Services), bridged via `MethodChannel` — **not** a third-party Flutter geofencing plugin | Native geofencing is OS-managed and battery-efficient (uses GPS/WiFi/cell fusion), survives app kills, and keeps this mission-critical logic under direct control rather than depending on the maintenance status of a third-party plugin. Note: Android's native API has a hard cap of 100 geofences per app (not a practical constraint here). |
| Maps / location picking | `google_maps_flutter` (Google Maps SDK) | Already committed to Google Play Services for geofencing, so staying in the Google ecosystem avoids juggling two location data sources. Also unlocks Places Autocomplete for address search. Requires a Google Maps API key, billing account (free tier), and a Play Console Data Safety declaration for precise location collection. |
| Testing | Layered: Dart unit/widget tests (automated, CI) + manual on-device checklist per iteration for native-touching features | Exact alarms, geofence triggers, and background survival cannot be meaningfully unit-tested — they require real-device verification. Full automated on-device integration testing is deferred to a later hardening phase. |

---

## 3. Data Model

### 3.1 `alarms` table (unified entity for time and location alarms)

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PRIMARY KEY | Auto-increment |
| `label` | TEXT | User-facing name, e.g. "Wake up", "Get off train" |
| `trigger_type` | TEXT | `TIME` or `LOCATION` (extensible to `BOTH` later) |
| `time_hour` | INTEGER, nullable | Populated only for `TIME` alarms |
| `time_minute` | INTEGER, nullable | Populated only for `TIME` alarms |
| `repeat_days` | TEXT, nullable | Bitmask or CSV of weekdays, e.g. `"MON,TUE,WED"` |
| `latitude` | REAL, nullable | Populated only for `LOCATION` alarms |
| `longitude` | REAL, nullable | Populated only for `LOCATION` alarms |
| `radius_meters` | INTEGER, nullable | 200–20,000; default 2000. Populated only for `LOCATION` alarms |
| `is_enabled` | BOOLEAN | Master on/off toggle |
| `is_armed` | BOOLEAN | Relevant only to `LOCATION` alarms — see §5.3 |
| `sound_uri` | TEXT | Selected alarm tone |
| `vibrate` | BOOLEAN | |
| `snooze_duration_min` | INTEGER | Default 5 or 10 (configurable) |
| `max_snooze_count` | INTEGER, nullable | Null = unlimited |
| `created_at` | TEXT (ISO 8601) | |
| `updated_at` | TEXT (ISO 8601) | |

### 3.2 `timers` table

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PRIMARY KEY | |
| `label` | TEXT | |
| `duration_seconds` | INTEGER | |
| `remaining_seconds` | INTEGER | For resume-after-restart display purposes |
| `state` | TEXT | `RUNNING`, `PAUSED`, `COMPLETED`, `CANCELLED` |
| `started_at` | TEXT (ISO 8601), nullable | |

### 3.3 Settings (via `shared_preferences`, not a table)

Theme, default snooze duration, default alarm sound, default geofence radius.

> **Note:** The stopwatch is intentionally **not persisted** to a database
> table — it is pure in-memory Riverpod state. See §5.2.

---

## 4. Permissions Strategy

Modern Android requires a "gauntlet" of separate runtime permissions for
this app's feature set. Requesting all of them on first launch risks users
denying everything or uninstalling. Permissions are therefore requested
**contextually**, at the moment they become relevant:

| Permission | Requested when | Notes |
|---|---|---|
| `POST_NOTIFICATIONS` (API 33+) | First alarm/timer creation | Required to show the ringing notification / full-screen UI at all. |
| `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` (API 31+) | First alarm scheduled | On API 33+, this is a special permission granted via a Settings page, not a simple dialog. |
| `ACCESS_FINE_LOCATION` (foreground) | First geofence alarm created | Standard runtime dialog. |
| `ACCESS_BACKGROUND_LOCATION` | Immediately after foreground location is granted, preceded by an in-app explanation screen | On Android 11+, this must go through a system Settings page, not an in-app dialog. Showing an explanation screen *before* the system prompt improves grant rates. |
| Battery optimization exemption | One-time nudge after first geofence alarm is armed, plus a persistent "health check" warning banner elsewhere in the app if incomplete | Not a single Android API — OEM-specific (Xiaomi, Samsung, Oppo, etc.). Without this, OEM battery killers can silently break background geofencing/alarms even with all other permissions granted. |
| `USE_FULL_SCREEN_INTENT` | Declared in manifest; no runtime prompt on most versions | Needed for lock-screen ringing UI. |

**Design principle:** The app must never silently fail to wake the user due
to a missing permission. Incomplete permission state should be visibly
surfaced (e.g., a warning banner on the alarm list) rather than discovered
only when an alarm fails to fire.

---

## 5. Feature Specifications by Iteration

### 5.1 Iteration 0 — Foundation (no user-visible feature)

- Flutter project scaffolding, folder structure
- `sqflite` schema creation (`alarms`, `timers` tables) + migration setup
- Riverpod provider architecture skeleton
- Native `MethodChannel` scaffolding — stubbed methods on both Dart and
  Kotlin sides for: schedule alarm, cancel alarm, alarm-fired event stream
- Notification channel setup
- `POST_NOTIFICATIONS` and `SCHEDULE_EXACT_ALARM` permission requests only
  (location permissions deferred to Iteration 4)

### 5.2 Iteration 1 — Normal Alarm

- Create/edit/delete time-based alarms (`trigger_type = TIME`)
- Repeat-day selection
- Native `AlarmManager.setAlarmClock()` scheduling
- `BroadcastReceiver` → foreground `Service` → full-screen ringing
  `Activity`
- Tap-to-dismiss, tap-to-snooze (configurable duration, optional max
  snooze count)
- Alarm survives app kill and device reboot (reschedule via
  `BOOT_COMPLETED` receiver)
- Alarm tone + vibration selection

### 5.3 Iteration 2 — Stopwatch

- Pure Dart/Flutter, no native background work
- Start / pause / resume / reset / lap
- State held in Riverpod; **does not persist** across app kill — if the
  app is killed mid-stopwatch, the count resets. This is an accepted
  tradeoff, not a bug, given the low stakes of this feature.

### 5.4 Iteration 3 — Timer

- Create a countdown timer with a duration and optional label
- Reuses the **same native pipeline as Iteration 1**: scheduled as an
  exact alarm for `now + duration`, same ringing/dismiss/snooze UI, just
  different labeling/iconography
- Must fire reliably even if the app is backgrounded or killed (same
  guarantee as a normal alarm)

### 5.5 Iteration 4 — Geofencing Alarm

- Location-based alarms (`trigger_type = LOCATION`)
- Map-based location picker (`google_maps_flutter`) with Places
  Autocomplete address search
- Radius selection via slider/stepper: 200 m minimum (below this, Android's
  geofencing accuracy of ~100–150 m becomes unreliable) to 20 km maximum,
  default 2 km, shown as a visual circle overlay on the map
- Foreground + background location permission flow (per §4)
- **Explicit arming model:** a "Start Trip" toggle/button that:
  1. Checks the user's current location first
  2. If already inside the radius, warns the user instead of silently
     firing ("You're already within range — move outside first or adjust
     the radius")
  3. Only then registers the geofence with
     `GeofencingClient.addGeofences()`
- **One-shot auto-disarm:** on the first `ENTER` transition, the alarm
  fires (same ringing UI as time-based alarms). Once dismissed or
  snoozed, the geofence is unregistered natively
  (`removeGeofences()`) and the alarm flips back to `is_armed = false`,
  ready to be re-armed for the next trip. This prevents GPS-jitter
  re-triggering near the boundary.
- Battery optimization exemption nudge + persistent health-check warning
  if permissions/optimization state is incomplete

---

## 6. Explicitly Deferred (Future Phases)

- iOS support
- Anti-oversleep dismiss mechanics (math puzzle, shake-to-dismiss,
  QR/NFC scan) — noted as a strong candidate for a post-Phase-1 iteration
  given the app's transit/dozing-off use case
- Combined `TIME` + `LOCATION` trigger on a single alarm (`BOTH` type)
- Fully automated on-device integration testing (physical device farm,
  `integration_test` for native alarm/geofence flows)
