# Wakey-Wakey — Privacy Policy

**Last updated:** 3 August 2026

Wakey-Wakey ("the app") is an Android alarm application that, in addition
to a conventional time-based alarm, supports a **geofencing alarm** —
alarms that trigger when the device is near a chosen location. This
privacy policy explains what data the app handles, why, and what it
does **not** do with that data.

The app is developed and published by **TingerBuddanna**
("the developer").

---

## 1. Data the app handles

The app handles the following categories of data. **All of it stays on
the device by default.** Nothing is uploaded to a server operated by the
developer or to any third party except where explicitly noted.

### 1.1 Data you provide

- **Alarm list:** label, wall-clock time, repeat days, and (for
  geofence alarms) the chosen location and radius. Stored locally in
  the app's private SQLite database (`alarms` table).
- **Timer / stopwatch history:** recent timer durations and the current
  stopwatch state. Stored in the same local SQLite database (`timers`
  table).
- **Favourite locations:** a short list of saved locations (e.g. "Home",
  "Work") with their coordinates and labels. Stored in the same local
  SQLite database (`favourites` table).
- **App preferences:** default alarm ringtone, snooze length, theme,
  and similar settings. Stored in `shared_preferences` (an
  Android-provided key-value store).

### 1.2 Data the device collects on the app's behalf

- **Precise device location (latitude, longitude, accuracy):** read
  only while you are actively picking a location on the in-app map or
  when a geofence alarm is armed and the device is in motion. The
  native Android `FusedLocationProviderClient` (part of Google Play
  Services Location) supplies the location fixes; the app stores
  coordinates you pick as geofence centres locally, and uses your
  device's current location only to evaluate "is the device inside
  the registered circle?" against those saved coordinates.
  The app **does not transmit** your location to any server.

### 1.3 Data the app does **not** collect

The app does not collect, store, transmit, or have access to:

- Your name, email, phone number, or any account identifiers.
- Contacts, call logs, or SMS.
- Photos, media, microphone, or camera.
- Advertising identifiers (GAID / IDFA).
- Crash reports, analytics, telemetry, or diagnostics — **no Firebase
  Analytics, no Crashlytics, no Sentry, no Google Analytics, no
  third-party telemetry SDKs are bundled.**
- Any data when the app is not running on the device.

---

## 2. How the data is used

- **Alarm list, favourite locations, preferences:** used only to render
  the app's UI and to schedule / fire alarms. The data is read by the
  app's own components (UI, `AlarmManager`, `GeofencingClient`,
  `BroadcastReceiver`s, foreground `Service`).
- **Device location (when a geofence alarm is armed):** used only to
  evaluate proximity to the saved geofence centres. The fused
  location provider runs in the background; location fixes are
  received via the standard Android `GeofencingEvent` broadcast and
  are not stored beyond the lifetime of the geofence evaluation.
- **Location (when you pick a point on the map):** used only to
  populate the map picker camera and to save your chosen point to the
  `alarms` / `favourites` table. The Google Maps SDK fetches map
  tiles from Google's servers (see §4 for Google's own privacy
  practices).

---

## 3. Where the data is stored and who can access it

- All data listed in §1.1 is stored in the app's private internal
  storage (`/data/data/com.wakeywakey.app/`), which is inaccessible to
  other apps and to the user without root.
- On Android 6.0 and newer the app participates in the platform's
  **Auto Backup** feature, which encrypts and uploads app data to the
  user's own Google Drive (capped at 25 MB per app). This is end-to-end
  encrypted with a device-derived key and is accessible only to the
  signed-in Google account on a device the user signs into. The
  developer cannot read Auto Backup data.
- If you uninstall the app, the data is removed from the device. Auto
  Backup snapshots may persist on Google's servers for a limited
  retention window; you can clear them from your Google account's
  storage settings.
- On Android 12+ the app supports **device-to-device transfer** so
  that alarms and favourites move to a new phone. This is handled
  entirely by the Android platform; the developer has no visibility
  into the transfer.

---

## 4. Third-party services

The app embeds the following third-party SDKs. Each operates under
its own privacy policy; the app does not extend or augment their
collection.

| SDK | Provider | Purpose | Data shared with provider | Provider privacy policy |
|---|---|---|---|---|
| Google Play Services Location | Google LLC | Fused location fixes for geofence evaluation | Device location (when a geofence is armed) | https://policies.google.com/privacy |
| Google Maps SDK for Android | Google LLC | Map tiles and Places Autocomplete in the map picker | Device location (when the map is open), search queries you type in the Places autocomplete | https://policies.google.com/privacy |
| AndroidX / Material Components | Google LLC | Standard Android UI components | None | https://policies.google.com/privacy |

No other third-party SDKs are bundled. In particular, there is no
analytics, no ad network, no crash reporter, no social login, and no
remote-config service.

---

## 5. Children's privacy

The app is not directed at children under 13 and does not knowingly
collect personal information from children. The app does not contain
content that would be inappropriate for any age.

---

## 6. Your choices and controls

- **Delete all app data:** Uninstall the app. Android also deletes the
  Auto Backup snapshot for the app after a grace period; you can
  trigger this immediately from your Google account's storage
  settings.
- **Revoke location permission:** Go to Android Settings → Apps →
  Wakey-Wakey → Permissions → Location → Deny. Existing time-based
  alarms will continue to work; geofence alarms will not trigger
  until permission is granted again.
- **Revoke notification permission:** Go to Android Settings → Apps →
  Wakey-Wakey → Permissions → Notifications → Deny. You will still
  see the full-screen ringing UI when an alarm fires (this is a
  separate platform permission), but you will not see ongoing
  notifications.
- **Disable Auto Backup:** Go to Android Settings → System → Backup →
  toggle off, or set the app's backup data to off via `adb shell bmgr
  backup <package>`. The app's own data is unaffected; only the
  cross-device restore capability is lost.
- **Disable exact alarms:** Go to Android Settings → Apps →
  Wakey-Wakey → Alarms & reminders → Deny. Time-based alarms may
  then fire late (by minutes to hours) when the device is in Doze
  mode. The app surfaces a banner to walk you through re-granting
  this permission.

---

## 7. Changes to this policy

Material changes will be reflected by updating the "Last updated"
date at the top of this document and (for breaking changes) an
in-app notice. Continued use of the app after a change constitutes
acceptance of the updated policy.

---

## 8. Contact

For privacy questions, data deletion requests, or any other
inquiries:

- **Email:** [YOUR_EMAIL_HERE] *(replace with the developer's real
  contact address before submitting to the Play Store — this is
  the address Google and end users will use to reach you)*
- **Developer:** TingerBuddanna

The developer will respond to verified requests within 30 days.
