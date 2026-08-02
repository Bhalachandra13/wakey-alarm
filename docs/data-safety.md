# Data Safety — Play Console Answers

This document is the **source of truth** for the answers you should
give in **Google Play Console → Policy → App content → Data safety**
when submitting Wakey-Wakey.

The Data Safety form asks whether the app **collects, shares, or
processes** each category of user data, and whether the data is
**encrypted in transit**, **user-controllable**, or **deleted on
uninstall**. Below is each section, the question, the correct answer,
and a short justification that references the codebase.

> **Source of truth:** the Data Safety form requires that the answers
> reflect what the app *actually does*, not what the privacy policy
> promises. Each answer below is cross-referenced to the file in the
> codebase that implements (or omits) the behaviour.

---

## 1. Data collection overview

| Play Console question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (TLS, via Google Play Services Location & Maps SDKs) |
| Do you provide a way for users to request that their data is deleted? | **No** (the only user data is on the device; uninstall deletes it) |

---

## 2. Data types — detailed

### 2.1 Location

| Play Console question | Answer |
|---|---|
| Is this data collected, shared, or both? | **Collected** |
| Is this data shared with third parties? | **No** (only processed locally by the app and by the on-device Geofencing API) |
| Is this data processed ephemerally? | **No** (saved to the local DB when you set up a geofence) |
| Is the collection optional? | **Yes** (geofence alarms are an opt-in feature; without granting the location permission, time-based alarms still work) |
| What is the purpose? | **App functionality** (geofence alarm evaluation) |
| Is the data **precise** location, **coarse** location, or both? | **Precise** |
| Is the data encrypted in transit? | **Yes** (the Google Play Services fused location provider uses TLS to receive fixes) |
| Can users request that their data is deleted? | **No** (uninstall deletes; no server-side data to delete) |

**Justification:** `lib/data/` (sqflite DAOs) stores the user-picked
geofence centre as `(latitude, longitude, radius_meters)` in the
`alarms` table. The native side
(`android/app/src/main/kotlin/.../GeofenceController.kt`) registers
that point as a `Geofence` with `LocationServices.getGeofencingClient()`,
which is on-device. The Maps SDK and Places Autocomplete also receive
the device's coarse location to render the map and search results —
that is the only data the app's Google-provided SDKs see, and it
goes only to Google under Google's own privacy policy (§4 of
`privacy-policy.md`).

### 2.2 App activity — app interactions

| Play Console question | Answer |
|---|---|
| Is this data collected, shared, or both? | **Not collected** |

The app does not log or transmit which alarms you set, which timers
you start, or any other in-app activity. The "App activity" category
is **not collected**.

### 2.3 App info & performance — crash logs / diagnostics

| Play Console question | Answer |
|---|---|
| Is this data collected, shared, or both? | **Not collected** |

No crash reporter (Crashlytics, Sentry, Bugsnag, etc.) and no
diagnostics SDK is bundled. There is no automatic crash log upload.

### 2.4 Device or other IDs

| Play Console question | Answer |
|---|---|
| Is this data collected, shared, or both? | **Not collected** |

No `ANDROID_ID`, no `Settings.Secure.ANDROID_ID`, no advertising ID
(GAID), no `getDeviceId()`, no IMEI access. The app's local
SQLite/SharedPreferences data is identified internally by autoincrement
row IDs, which are not user identifiers and are not transmitted.

### 2.5 Personal info — name, email, phone, etc.

| Play Console question | Answer |
|---|---|
| Is this data collected, shared, or both? | **Not collected** |

The app has no account system, no sign-in, no profile, no contact
form, and no fields that accept personally identifying information.

### 2.6 Financial info, Health & fitness, Messages, Photos & videos,
Audio files, Files & docs, Calendar, Contacts, Web browsing, In-app
search history

| Play Console question | Answer |
|---|---|
| Is this data collected, shared, or both? | **Not collected** |

The app declares no permissions for any of these categories and does
not access them.

---

## 3. Permissions — "Permission declarations" tab

In **Policy → App content → Permissions**, you must declare each
runtime permission the app requests, with a justification. The full
text of each justification (used as the "Permission is for" notes) is
in `permission-justifications.md`. Summary:

| Permission | Reason | User-facing prompt shown by Play Store |
|---|---|---|
| `android.permission.ACCESS_FINE_LOCATION` | Geofence alarm evaluation | "Wakey-Wakey uses precise location to fire your geofence alarms." |
| `android.permission.ACCESS_BACKGROUND_LOCATION` | Receive geofence transitions when the app is not in the foreground | "Wakey-Wakey uses background location to detect when you arrive at a saved location." |
| `android.permission.SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` | Schedule time-based alarms that fire at the wall-clock time even in Doze | "Wakey-Wakey schedules exact alarms so it can wake you at the time you chose." |
| `android.permission.USE_FULL_SCREEN_INTENT` | Show the ringing activity on the lock screen | "Wakey-Wakey shows a full-screen alarm when it's time to wake up." |
| `android.permission.FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_SPECIAL_USE` | Play alarm audio in a foreground service so it isn't killed | "Wakey-Wakey plays alarm audio in the background." |
| `android.permission.RECEIVE_BOOT_COMPLETED` | Re-arm scheduled alarms after a reboot | "Wakey-Wakey re-arms your alarms after the device restarts." |
| `android.permission.POST_NOTIFICATIONS` (API 33+) | Show ongoing notification while the timer / stopwatch is running | "Wakey-Wakey shows a notification while your timer is running." |
| `android.permission.VIBRATE` | Vibrate when the alarm rings | "Wakey-Wakey vibrates when the alarm rings." |
| `com.google.android.gms.permission.AD_ID` (auto-merged by Play Services) | Declared by Google Play Services, **not used by Wakey-Wakey** | (Play's auto-generated copy) |

The AD_ID permission is auto-merged by Google Play Services. We do
**not** use it (no ads, no analytics). When Play Console asks
"Does your app use the Advertising ID?", answer **No** — there is
no code path in this project that calls `AdvertisingIdClient` or
reads the GAID.

---

## 4. Data deletion

The Data Safety form also asks whether you offer a "data deletion
request" mechanism. The correct answer for this app is:

> **We don't need to** — the only user data the app holds is the
> on-device SQLite database and SharedPreferences, both of which
> are deleted by the platform when the user uninstalls the app. We
> operate no backend and hold no copy of the user's data.

Check **"No, this app does not have a way for users to request that
their data is deleted"** and explain in the free-text field:

> All user data is stored on-device and is automatically deleted
> when the app is uninstalled. The app does not maintain any
> server-side copy of user data.

---

## 5. Reviewer notes for the Play Console policy team

If a reviewer asks any of the following, point them at the
appropriate file:

- **"Where do you store user data?"** → on-device only
  (`lib/data/` sqflite + `shared_preferences`). No backend.
- **"What do you do with the Advertising ID?"** → nothing; the
  permission is auto-merged by Google Play Services and is not
  used by the app.
- **"Do you transmit location off-device?"** → no. The fused
  location fixes are received by the on-device GeofencingClient
  and never leave the device. The only data Google sees about
  your location is the map-tile requests the in-app map sends
  while the user is actively using the map picker.
- **"What crash / analytics SDKs do you use?"** → none.
- **"Do you target children?"** → no; the app's content is
  universal but it is not specifically designed for or marketed
  to children.
