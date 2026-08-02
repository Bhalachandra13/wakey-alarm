# Permission Justifications — Play Console Answers

This document is the **source of truth** for the text you should
paste into the **Play Console → Policy → App content → Permissions
declaration** form for each runtime permission the app declares in
`AndroidManifest.xml`.

Each section has the:

- **Permission** name (as it appears in the manifest).
- **Manifest line** that declares it.
- **What it does** (the user-facing behaviour it enables).
- **The exact text** to paste into the Console's "Why does your app
  need this permission?" field, written to be:
  - clear and specific to the actual feature,
  - honest about when the permission is used (foreground vs
    background),
  - worded to match Google's recommended framing for sensitive
    permissions (location, exact alarm).

These texts are deliberately longer than the minimum Play requires —
the Play policy team has become more strict about vague
justifications, and "for app functionality" alone is now a
frequent rejection reason.

---

## 1. `android.permission.ACCESS_FINE_LOCATION`

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

**What it does.** When you arm a geofence alarm, Wakey-Wakey asks
Google Play Services to evaluate the device's precise latitude /
longitude against the circle you drew on the map. The fused location
provider is the standard Android way to get a precise fix; we do
not roll our own GPS reader.

**Permission declaration text (paste verbatim):**

> Used by Wakey-Wakey's geofence alarm feature. When you create a
> geofence alarm, the app registers a circle (centre + radius) with
> Android's `GeofencingClient`. The fused location provider then
> reports whether the device is inside or outside that circle. This
> is what lets the alarm fire when you arrive at a saved location
> (e.g. wake up a few kilometres before your bus stop).
>
> Location is requested in-app at the moment you tap "Set up geofence
> alarm" — the app does not request location on first launch and
> does not read the device's location for any other purpose. Location
> fixes are processed on-device by Android and are not transmitted
> off the device by Wakey-Wakey. The in-app map picker is the only
> other place location is used, and only while that screen is open.

---

## 2. `android.permission.ACCESS_COARSE_LOCATION`

```xml
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

**What it does.** Declared in tandem with fine location because
Android requires apps to declare both. Wakey-Wakey does not actually
*use* coarse location for any feature — geofence evaluation needs
the precise fix — but the manifest must list both for the runtime
permission flow to behave correctly (granting fine implicitly
grants coarse, but a user who grants only coarse must still be
allowed to do so without crashing the app).

**Permission declaration text:**

> Declared alongside `ACCESS_FINE_LOCATION` because Android requires
> the two to be paired. Wakey-Wakey does not actively use coarse
> location; it is present so the app correctly handles the case
> where a user grants only "Approximate location" and is not
> penalised for the absence. The geofence feature requires precise
> location to work; the app surfaces a permission-setup banner that
> walks the user through upgrading to precise location if they want
> geofence alarms to function.

---

## 3. `android.permission.ACCESS_BACKGROUND_LOCATION`

```xml
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
```

**What it does.** A geofence transition can happen while the app is
in the background (e.g. you are on a bus and the app is not on
screen). Android's geofencing API requires the background-location
permission to be granted separately from foreground location, and
the user must grant it via a system Settings page — there is no
runtime dialog for it (since Android 10).

**Permission declaration text:**

> Wakey-Wakey's geofence alarm feature needs to detect when you
> arrive at a saved location even when the app is not on screen —
> the entire point of a geofence alarm is that it fires while you
> are in transit, not while you are looking at the app. Android
> requires this permission to be requested separately from
> foreground location and on a separate screen, and the in-app
> permission wizard walks the user through that flow.
>
> The permission is only requested after the user has tapped
> "Set up geofence alarm" for the first time — it is never asked
> for on first launch. Users who decline still have full access to
> time-based alarms, stopwatch, and timer.

---

## 4. `android.permission.SCHEDULE_EXACT_ALARM` and `USE_EXACT_ALARM`

```xml
<uses-permission android:name="android.permission.USE_EXACT_ALARM" />
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
```

**What it does.** Wakes the device at a specific wall-clock time to
fire the alarm. Without an exact-alarm permission, `AlarmManager`
is restricted by Doze / App Standby and may fire minutes to hours
late — unacceptable for a clock app.

`USE_EXACT_ALARM` is the install-time permission Google introduced
in API 33 for genuine alarm-clock apps; it is auto-granted (the
user is never prompted). `SCHEDULE_EXACT_ALARM` is the
runtime-grantable fallback for OEMs that don't honour
`USE_EXACT_ALARM` (some older devices). The app's
`canScheduleExactAlarms()` check accepts either.

**Permission declaration text (paste for both — Play asks once for
the "exact alarm" capability):**

> Wakey-Wakey is a clock app. Time-based alarms must fire at the
> wall-clock time the user chose, even when the device is in Doze
> mode and the app process is dead — that is the entire purpose of
> an alarm clock. `USE_EXACT_ALARM` is the install-time permission
> Android introduced in API 33 for genuine clock apps; it is
> auto-granted and the user is never prompted. `SCHEDULE_EXACT_ALARM`
> is the runtime-grantable equivalent kept as a fallback for
> manufacturers that don't honour the install-time one. The app
> calls `AlarmManager.setAlarmClock()`, the same API the system
> Clock app uses, which exempts the alarm from Doze and shows the
> status-bar alarm icon.

---

## 5. `android.permission.USE_FULL_SCREEN_INTENT`

```xml
<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />
```

**What it does.** When the alarm fires, the foreground service
posts a high-priority notification with a `fullScreenIntent`
that launches the ringing activity. This is what makes the
full-screen ringing UI appear on the lock screen, so the user
can dismiss or snooze without unlocking the phone.

**Permission declaration text:**

> When an alarm fires, Wakey-Wakey needs to launch its full-screen
> ringing activity from the lock screen so you can dismiss or
> snooze the alarm without first unlocking the phone. The
> foreground service posts a high-priority notification with a
> `fullScreenIntent`; `USE_FULL_SCREEN_INTENT` is the permission
> Android requires to launch an activity from the background via
> that path. Without it, the ringing UI would only appear after
> the user manually unlocked and opened the notification — which
> is the very failure mode an alarm clock is meant to prevent.

---

## 6. `android.permission.FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_SPECIAL_USE`

```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
```

**What it does.** Once the alarm fires, the ringing activity needs
the ringtone and vibration to keep playing even if the user
presses Home or the device goes to sleep. A regular background
service would be killed within seconds under Doze. The
foreground-service type `specialUse` is the only one that
matches "alarm clock" — there is no dedicated `mediaPlayback`
or `alarm` type.

**Permission declaration text:**

> When the alarm rings, Wakey-Wakey plays the ringtone and
> vibrates in a foreground service so the audio isn't killed when
> the device sleeps or the user presses Home. Android has no
> dedicated "alarm clock" foreground-service type, so the
> `specialUse` type is used with a `PROPERTY_SPECIAL_USE_FGS_SUBTYPE`
> property of "Alarm clock: plays ringtone and vibrates while the
> user dismisses or snoozes." This is the standard pattern for
> clock apps in the Play ecosystem. `FOREGROUND_SERVICE` is the
> base permission required for any foreground service; the
> `FOREGROUND_SERVICE_SPECIAL_USE` variant is the API 34+
> per-type requirement.

---

## 7. `android.permission.RECEIVE_BOOT_COMPLETED`

```xml
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```

**What it does.** Android's `AlarmManager` state is wiped on
shutdown. Without a boot receiver, every alarm would silently
disappear after a reboot. The boot receiver re-arms all
persisted alarms against the fresh `AlarmManager` instance.

**Permission declaration text:**

> When the device finishes booting, Wakey-Wakey's
> `BootReceiver` re-arms every alarm the user has set against the
> fresh `AlarmManager` instance, because Android clears all
> scheduled alarms on shutdown. Without this, the user would
> discover the morning after a reboot that none of their alarms
> are set. The receiver also handles `MY_PACKAGE_REPLACED` so
> alarms survive an app update.

---

## 8. `android.permission.POST_NOTIFICATIONS`

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

**What it does.** Required on API 33+ to show any notification.
The app uses it to:

- Show the high-priority ringing notification when an alarm
  fires (the notification's `fullScreenIntent` is what launches
  the ringing activity — see §5).
- Show an ongoing notification while a timer is counting down
  (so the user can see the remaining time and cancel without
  reopening the app).
- Show a low-priority "alarm scheduled" summary for the next
  upcoming alarm.

**Permission declaration text:**

> Wakey-Wakey shows three categories of notifications: (1) a
> high-priority ringing notification when an alarm fires, which
> includes the `fullScreenIntent` that launches the dismiss /
> snooze UI on the lock screen; (2) an ongoing notification
> while a timer is running, so the remaining time is visible
> without opening the app; (3) a low-priority summary of the
> next scheduled alarm. `POST_NOTIFICATIONS` is the API 33+
> runtime permission that gates all of these. The app's
> in-app permission wizard walks the user through granting it
> the first time a ringing notification is about to fire — it
> is never requested on first launch.

---

## 9. `android.permission.VIBRATE`

```xml
<uses-permission android:name="android.permission.VIBRATE" />
```

**Permission declaration text:**

> When an alarm fires, Wakey-Wakey vibrates the device in
> addition to playing the ringtone. The pattern is configurable
> per-alarm (silent / short / long / pattern). Vibrate is a
> normal (install-time) permission, so the user is never
> prompted for it.

---

## 10. `com.google.android.gms.permission.AD_ID` (auto-merged)

**This permission is not declared by Wakey-Wakey.** It is
auto-merged into the manifest by Google Play Services' manifest
merger because the Play Services Location and Maps libraries
declare it.

**Answer in Play Console (the form asks "Does your app use the
Advertising ID?"):** **No.**

**Justification to add to the free-text field if asked:**

> The `com.google.android.gms.permission.AD_ID` permission is
> auto-merged into the manifest by the Google Play Services
> library, but Wakey-Wakey does not use the Advertising ID in
> any code path. There are no ads in the app, no analytics, and
> no feature that reads the GAID. The permission is harmless to
> retain because it grants no capability the app exercises.

---

## Quick copy-paste cheat sheet

If you are filling the form quickly, here is the shortest
acceptable text per permission. Google may push back on
single-sentence answers; if it does, swap in the longer
versions above.

| Permission | Quick text |
|---|---|
| `ACCESS_FINE_LOCATION` | Used only when you set up a geofence alarm, to evaluate proximity to the saved location. |
| `ACCESS_COARSE_LOCATION` | Declared with fine location; not actively used. |
| `ACCESS_BACKGROUND_LOCATION` | Required so a geofence alarm can fire when the app is in the background (e.g. while you are on transit). |
| `USE_EXACT_ALARM` / `SCHEDULE_EXACT_ALARM` | This is a clock app; alarms must fire at the chosen wall-clock time even under Doze. |
| `USE_FULL_SCREEN_INTENT` | Lets the ringing activity appear on the lock screen so the alarm can be dismissed without unlocking. |
| `FOREGROUND_SERVICE_SPECIAL_USE` | Plays the alarm ringtone and vibration in a foreground service so audio is not killed. |
| `RECEIVE_BOOT_COMPLETED` | Re-arms scheduled alarms after a device reboot. |
| `POST_NOTIFICATIONS` | Shows the ringing notification, the timer ongoing notification, and the next-alarm summary. |
| `VIBRATE` | Vibrates when the alarm rings. |
