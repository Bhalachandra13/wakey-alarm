# Play Store — Publish Runbook

This is the end-to-end runbook for taking Wakey-Wakey from "the
AAB is built and signed" to "it is live on the Google Play Store."
It is written for the developer (TingerBuddanna) — assume
familiarity with `flutter build` and the Android toolchain.

The runbook is structured in the order Play Console requires:

1. Pre-flight (assets, signing, privacy policy hosting).
2. Developer / Console account.
3. Create the app entry.
4. Store listing (text + graphics).
5. App content (Data Safety, Ads, Content rating, Target audience,
   Government apps, Financial features, Health apps, Data deletion).
6. Permissions declarations.
7. App access (if any restricted functionality).
8. Release track (internal → closed → production).
9. Upload the AAB.
10. Rollout.

> **Where to keep this file in the workflow.** This is the
> "Phase D" of Iteration 5, per `workflow_plan.md`. Once the
> app is live, the iteration is considered "done" pending the
> manual on-device checklist — see §10 of this runbook.

---

## 0. Pre-flight checklist (do these first)

Complete every item in this section before opening Play Console.

### 0.1 AAB is built and signed

```bash
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`. The
AAB is signed with the upload keystore described in
`android/key.properties` (gitignored). Verify the signing:

```bash
unzip -p build/app/outputs/bundle/release/app-release.aab \
  META-INF/UPLOAD.RSA > /tmp/upload.rsa
keytool -printcert -file /tmp/upload.rsa
# Owner: CN=TingerBuddanna, OU=Wakey-Wakey, O=TingerBuddanna
# SHA1: 2F:C3:08:53:38:C4:1E:F9:DA:82:9E:09:8D:53:96:D0:E3:38:3C:2E
# 4096-bit RSA, valid until 2051.
```

> **Keystore backup.** Make three copies of
> `android/app/wakey-upload-key.jks` and `android/key.properties`
> in at least two physically separate places (e.g. encrypted
> USB drive + password manager attachment). Google Play App
> Signing will *re-sign* your AAB with their own app-signing
> key, but you still need the upload key to push future
> updates. **If you lose the upload keystore you can never
> push an update to this app.**

### 0.2 Maps API key

`android/local.properties` (gitignored) must contain a real
`MAPS_API_KEY=...` line before building the AAB — the value is
templated into the manifest at build time:

```properties
MAPS_API_KEY=AIza...
```

A real key is already present in your `local.properties`. The
key is restricted (in Google Cloud Console) to:

- **Application restrictions:** Android apps, with the SHA-1
  of your upload keystore
  (`2F:C3:08:53:38:C4:1E:F9:DA:82:9E:09:8D:53:96:D0:E3:38:3C:2E`)
  **and** the SHA-1 of the debug keystore, plus the package
  name `com.wakeywakey.app`.
- **API restrictions:** Maps SDK for Android, Places API.

If you rotate the Maps key later, edit `local.properties` and
rebuild the AAB. The key is not committed to the repo.

> **Why a key is needed at all.** The in-app map picker uses
> the Google Maps SDK; without a valid key, tiles don't render
> and the picker falls back to a coordinate-input form. The
> rest of the app (alarms, geofences, timer, stopwatch) works
> fine without one.

### 0.3 Privacy policy is hosted

You need a publicly reachable URL for the privacy policy. See
§1 below for the recommended GitHub Pages setup.

### 0.4 Screenshots

Play requires at least 2 screenshots per device class:

- Phone: 2–8 screenshots, JPG or PNG, 16:9 or 9:16, between
  320 px and 3840 px on the long edge.
- 7-inch tablet: optional but recommended.
- 10-inch tablet: optional.

Capture them on a real device — see §2 below.

### 0.5 Feature graphic and app icon

Already produced by `tools/generate_launcher_icon.py` and
checked into the repo at:

- `store_assets/icon-512.png` — Play listing icon (512×512 PNG).
- `store_assets/feature-graphic-1024x500.png` — Play feature
  graphic (1024×500 PNG or JPG).

---

## 1. Host the privacy policy

The easiest free, reliable, no-server option is **GitHub Pages**.

1. Create a new public GitHub repo (e.g. `wakey-wakey-privacy`).
2. Copy `docs/privacy-policy.md` to `index.md` at the repo root.
3. In the repo's **Settings → Pages**, set Source to `main` /
   `/ (root)`. GitHub will host the file at
   `https://<your-username>.github.io/wakey-wakey-privacy/`.
4. Verify the URL loads in a private/incognito browser window.

> **Custom domain (optional).** If you have a domain, point a
> CNAME to `<username>.github.io` and put the domain in the
> repo's `CNAME` file.

Paste the final URL into the Play Console's **Store listing →
Privacy policy** field. Play checks the URL must return
HTTP 200 with the policy text visible (it does a fetch, not
just a HEAD).

> The privacy policy's contact email is set in
> `docs/privacy-policy.md` §8. If you ever change it, edit the
> in-repo file and push — the GitHub Pages site redeploys
> automatically.

---

## 2. Capture phone screenshots

On a real Android device (preferably a Pixel-class phone for
the canonical 1080×1920 capture), install the release AAB and
take screenshots of:

1. **Alarms tab — empty state** (first launch, before any
   alarms are added). Shows the welcoming empty state.
2. **Alarms tab — list with one time alarm and one geofence
   alarm** (set up both kinds first). Shows the mixed list.
3. **Map picker** with at least one favourite chip visible
   and the radius circle drawn.
4. **Ringing activity** — set an alarm for 1 minute in the
   future, lock the device, wait for it to fire, take the
   screenshot of the full-screen ringing UI.
5. **Permissions setup wizard** — open the app with all
   permissions revoked, navigate to the wizard.
6. **Timer / Stopwatch tab** showing the live countdown or
   progress ring.

To install the AAB on a device for capture, use either:

- `adb install build/app/outputs/bundle/release/app-release.aab`
  (requires `bundletool` if you want to install an AAB
  directly — `adb install` accepts APKs but AABs need
  `bundletool build-apks --bundle=app-release.aab --output=app.apks`
  followed by `bundletool install-apks --apks=app.apks`); OR
- run `flutter build apk --release` and install the APK at
  `build/app/outputs/flutter-apk/app-release.apk` via
  `adb install -r <path>`.

Place the screenshots in `store_assets/screenshots/phone/` with
the names `01-alarms-empty.png`, `02-alarms-list.png`, etc.

---

## 3. Developer / Console account

One-time, before the first publish.

1. Pay the **$25 USD** one-time Google Play Developer
   registration fee at
   <https://play.google.com/console/signup>. Use the Google
   account you want the developer identity to be tied to
   (this is the account whose name appears as "Offered by"
   on the listing).
2. Fill in the developer profile:
   - Developer name: **TingerBuddanna** (this is what users
     see as "Offered by TingerBuddanna").
   - Email: a contact address (can be different from the
     developer account email).
   - Phone: required for verification.
3. Identity verification: Google may ask for a government ID
   and (for organisations) business documents. For an
   individual developer, a passport or driver's licence
   usually suffices.

---

## 4. Create the app entry

1. Play Console → **All apps → Create app**.
2. **App name:** `Wakey-Wakey` (≤ 50 chars).
3. **Default language:** English (United States).
4. **App or game:** App.
5. **Free or paid:** Free.
6. **Declarations:** tick both checkboxes (Developer
   Program Policies, US export laws).
7. Click **Create app**. You land on the dashboard with a
   left-rail checklist.

Work through the left-rail in order; each section refuses to
mark itself complete until every required field is filled.

---

## 5. Store listing

Path: **Grow → Store presence → Main store listing**.

### 5.1 App details

| Field | Value |
|---|---|
| App name | `Wakey-Wakey` |
| Short description | (see §5.2) |
| Full description | (see §5.3) |
| App icon | `store_assets/icon-512.png` |
| Feature graphic | `store_assets/feature-graphic-1024x500.png` |
| Phone screenshots | (see §2 above) |
| 7-inch tablet screenshots | (optional) |
| 10-inch tablet screenshots | (optional) |
| Promo graphic | (optional, 1024×680) |
| TV banner | (skip — not a TV app) |
| Wear OS screenshot | (skip — not a Wear app) |
| App category | **Productivity** or **Tools** |
| Tags | `alarm`, `clock`, `timer`, `stopwatch`, `geofence` |
| Store listing experiment | (skip for first publish) |
| Privacy policy | the GitHub Pages URL from §1 |

### 5.2 Short description (≤ 80 chars)

```
Geofence and time-based alarms. Wake up on time — or when you arrive.
```

(73 chars.)

### 5.3 Full description (≤ 4000 chars)

```
Wakey-Wakey is a clock app that fires your alarms the usual way — and
one new way: by location.

▸ Geofence alarms
  Set an alarm centred on a map point and a radius. The alarm fires
  the moment your device enters the circle, so you can doze off on
  the train and wake up a few kilometres before your stop. The native
  Android Geofencing API (Google Play Services) is used, so the
  detection is battery-efficient and survives the app being closed.

▸ Time-based alarms
  Wall-clock alarms with a snooze, a label, a per-day repeat, and a
  configurable vibration pattern. Powered by
  AlarmManager.setAlarmClock() — the same API the system Clock app
  uses — so alarms fire on time even when the device is in Doze.

▸ Favourite locations
  Save Home, Work, or any place you go often, and the next time you
  set up a geofence the saved points appear as one-tap chips in the
  map picker. Two taps from "I want to wake up before I reach the
  airport" to "armed."

▸ Timer
  A kitchen-style countdown timer with a live progress ring, an
  ongoing notification so the time left is visible without opening
  the app, and a sound that fires through the same full-screen UI as
  an alarm. Pause and resume; the timer survives the app being
  killed.

▸ Stopwatch
  A lap-aware stopwatch with a smooth progress ring, in line with
  the rest of the app's design. Saves laps so they survive the app
  being closed.

▸ Privacy by default
  No account. No analytics. No ads. No crash reporter. The only data
  the app holds is your alarms, your favourites, and your app
  preferences — all stored on your device. Location is read only
  while you are setting up a geofence or while a geofence alarm is
  armed; it is never transmitted off the device.

▸ Material You
  Dynamic colour on Android 12+. Light and dark themes. The UI is
  built with Material 3 components and respects your system font
  size and contrast settings.

Why this app exists: every other alarm app does only time. We wanted
a clock that knows where you are.
```

(≈ 2050 chars. Well under the 4000 limit.)

### 5.4 Categorisation

- **App category:** Productivity (alternatively: Tools).
- **Tags:** alarm, clock, timer, stopwatch, geofence, location,
  transit, productivity.

### 5.5 Contact details

- **Email:** a real address you check.
- **Website:** (optional) GitHub repo URL.
- **Phone:** (optional, leave blank).

---

## 6. App content (the long one)

Path: **Policy → App content**. There are eight sub-sections;
go through them in order.

### 6.1 Privacy policy

Already covered — the GitHub Pages URL from §1.

### 6.2 Data safety

The full set of Console answers is in
[`docs/data-safety.md`](data-safety.md). Go through each
sub-question and copy the answer.

The four key answers for this app:

- **Is data collected?** Yes (precise location, for the
  geofence feature only).
- **Is data shared?** No.
- **Is data encrypted in transit?** Yes (TLS via Google Play
  Services Location & Maps).
- **Is there a way to request deletion?** No — uninstall
  deletes the on-device data; there is no server-side copy.

For each data type, the Console shows three rows
(Collected / Shared / Both). Mark "Collected" for precise
location, "Not collected" for everything else.

### 6.3 Ads

- **Does your app contain ads?** No.

### 6.4 Content rating

- Click **Start questionnaire**.
- Category: **Utility → Other** (no communication, no user-
  generated content, no location sharing with other users).
- App has no violence, no profanity, no controlled substances,
  no gambling, no sexual content. The questionnaire
  auto-completes with a **Everyone / PEGI 3** rating.
- **IARC rating** is generated automatically; copy the
  certificate into the listing.

### 6.5 Target audience

- **Target age group:** 18+ (the app is not designed for or
  marketed to children, but is not restricted to adults).
- **Is the app designed for children?** No.

### 6.6 Government apps

- **Is this a government app?** No.

### 6.7 Financial features

- The app does not process payments, does not offer
  subscriptions, does not offer in-app purchases, and does
  not handle financial data. Tick **None of the above** on
  every sub-question.

### 6.8 Health apps

- The app does not collect health data, does not interact
  with Health Connect, and is not classified as a health
  app. Tick **None of the above**.

### 6.9 COVID-19 contact tracing / status apps

- No.

### 6.10 Data deletion

- "Does your app allow users to request that their data is
  deleted?" → **No** (the only data is on-device; uninstall
  deletes it; no backend to delete from). The free-text
  field's content is the same paragraph from
  [`docs/data-safety.md`](data-safety.md) §4.

---

## 7. Permissions declarations

Path: **Policy → App content → Permissions**.

The Play Console scans the merged manifest and presents each
runtime permission with a "Why does your app need this
permission?" field. The full text for each is in
[`docs/permission-justifications.md`](permission-justifications.md).
Summary of what to paste for each:

| Permission | Paste the text from § |
|---|---|

| `ACCESS_FINE_LOCATION` | §1 |
| `ACCESS_COARSE_LOCATION` | §2 |
| `ACCESS_BACKGROUND_LOCATION` | §3 |
| `USE_EXACT_ALARM` / `SCHEDULE_EXACT_ALARM` | §4 |
| `USE_FULL_SCREEN_INTENT` | §5 |
| `FOREGROUND_SERVICE_SPECIAL_USE` | §6 |
| `RECEIVE_BOOT_COMPLETED` | §7 |
| `POST_NOTIFICATIONS` | §8 |
| `VIBRATE` | §9 |
| `com.google.android.gms.permission.AD_ID` (auto-merged) | §10 |

The most scrutinised ones by the policy team are
`ACCESS_BACKGROUND_LOCATION` and the exact-alarm pair — make
sure those use the longer (not the cheat-sheet) text.

---

## 8. App access

Path: **Policy → App content → App access**.

- **Is your app restricted to a limited audience (login,
  invitation, approval)?** No.
- **Are there any accounts the reviewer needs to sign in
  with to review all features?** No. Every feature of the
  app is available without an account.

---

## 9. Release track and rollout

Path: **Release → Production → Create new release**.

For the first publish, walk the standard staged rollout:

### 9.1 Internal testing (optional, recommended)

1. **Release → Testing → Internal testing → Create new
   release.**
2. Upload the AAB.
3. Add your own Google account (and a couple of trusted
   friends) as internal testers via the email-list or
   by-creating-a-Google-Group flow.
4. Roll out 100%. Internal-test releases skip the
   standard review (they are reviewed on a separate,
   faster track) and propagate to devices within minutes.

Use this track to verify the listing looks right on a
real device before the production review.

### 9.2 Closed testing (optional, recommended for v1.0+1)

1. **Release → Testing → Closed testing → Create track.**
2. Pick a track name (e.g. "Beta").
3. Upload the same AAB.
4. Add testers by email list (up to 200 emails).
5. Closed-test releases *are* reviewed by Play but with
   a shorter SLA than production.

Skip this if you're confident and the internal test
checked out.

### 9.3 Production

1. **Release → Production → Create new release.**
2. **Upload** the AAB (`build/app/outputs/bundle/release/app-release.aab`).
3. **Release name:** `1.0.0 (1)` (internal label, users don't see it).
4. **Release notes:** see §9.4.
5. **Rollout percentage:** Start at **5%** for the first
   24 hours to catch any policy or install-rate issues,
   then bump to 100%. (For the first publish you can go
   straight to 100% if you have run the internal test.)
6. **Countries:** All countries (or uncheck the regions
   where the Maps API key isn't valid — for v1, all
   countries, because the Maps fallback works without
   tiles).
7. Click **Review release → Start rollout to Production**.

### 9.4 First release notes (English)

```
Welcome to Wakey-Wakey 1.0!

• Geofence alarms — wake up when you arrive at a location,
  not just at a wall-clock time.
• Time-based alarms with snooze, label, and per-day repeat.
• Timer with a live progress ring and ongoing notification.
• Stopwatch with lap saving.
• Save favourite locations for one-tap geofence setup.
• Material 3 design with dynamic colour and dark theme.

Privacy by default: no account, no ads, no analytics, no
crash reporter. All data stays on your device.
```

### 9.5 What happens after you click Rollout

- The first production release goes through a Play
  review (typically 3–7 days for a new app; faster for
  updates).
- If the review approves, the app is published and
  becomes searchable on the Play Store within a few
  hours.
- If the review requests changes, fix the requested
  issues and re-upload; the SLA resets.

---

## 10. Post-publish

### 10.1 Manual on-device DoD (still required)

Per `workflow_plan.md` §"Iteration 5 — DoD" and AGENTS.md §8,
the publishing prep does **not** close out the iteration —
the manual on-device checklist for the underlying features
must still be run on a physical device. Specifically:

- [ ] First-run permission wizard auto-pushes on the alarms
      tab and walks all four items in order.
- [ ] Open a geofence alarm → "Pick on map" → chip strip
      shows saved favourites; tapping Home drops the pin
      and flies the camera with the correct radius.
- [ ] First-time Favourites empty state shows Add Home /
      Add Work; tapping Add Home opens the map picker and
      the resulting favourite shows up in the chip strip
      on the next picker open.
- [ ] Arm a geofence, reboot the device, confirm the
      geofence still triggers (boot re-arm).
- [ ] Time-based alarm fires on time after a reboot.
- [ ] Snooze and dismiss both work from the lock screen
      full-screen UI.

### 10.2 Post-launch monitoring

- **Play Console → Monitor → Crashes & ANRs** — even
  without Crashlytics, the platform's own crash report
  will surface unhandled exceptions, and stack traces
  will appear here.
- **Play Console → Ratings and reviews** — reply to
  reviews from the same screen; low-star reviews with
  detailed repros are the most actionable feedback
  source.
- **Play Console → Statistics** — install counts,
  uninstall counts, ratings distribution. Useful
  baseline for v1.1.

### 10.3 Updating to a new version

1. Bump `version: X.Y.Z+N` in `pubspec.yaml` (X.Y.Z is the
   user-visible version, N is the monotonically increasing
   integer Play uses for ordering).
2. `flutter build appbundle --release`.
3. Play Console → Production → Create new release → upload.
4. Bump the rollout to 100% once it is clear the new
   version is healthy.

The upload keystore from §0.1 is required for every
update — Play App Signing re-signs the AAB you upload with
their app-signing key, but they will reject the upload
if the upload key's SHA-1 doesn't match what they
registered at first publish.

---

## 11. If Play Console rejects the submission

Common rejection reasons for a clock app, in order of
likelihood:

1. **"Background location justification insufficient."**
   Expand the §3 text in `permission-justifications.md` to
   describe *when* background location is used
   (only while a geofence is armed, never otherwise).
2. **"Exact alarm justification insufficient."**
   Make sure the §4 text mentions that without an exact
   alarm the clock app is non-functional.
3. **"Data Safety — location marked as collected but not
   declared in Privacy Policy URL."**
   Confirm the privacy policy URL fetches successfully and
   contains a section explicitly titled "Location" (case-
   insensitive match). The Console is particular about
   this.
4. **"Screenshots are not from the release build."**
   Make sure the screenshots you uploaded are from the AAB
   you uploaded, not from a `flutter run` debug build.
   The debug build has a different launcher icon and
   different behaviour, which Play catches.
5. **"App does not function on a device without Google
   Play Services."** This is fine — the geofence feature
   requires Play Services, and the app's manifest
   requires it via the Play Services Location library.
   If asked, explain in the reviewer notes that the
   app is intentionally an "apps with Play Services
   dependency" app and that the README states this.

If the rejection is something other than the above, copy
the exact rejection text into a new file at
`docs/play-store-rejections/<date>-<short-name>.md` and
address it there before re-submitting. The history
folder is append-only per AGENTS.md §7.2.

---

## 12. What is **not** in this runbook

- iOS / App Store distribution. Phase 1 is Android-only
  per `requirements.md` §1; iOS is a future-phase research
  spike.
- F-Droid or other alternative stores. The AAB can be
  sideloaded; the same `app-release.apk` from
  `flutter build apk --release` works for direct installs.
  Document the sideload flow separately if/when needed.
- Play App Signing opt-out. Wakey-Wakey uses the default
  flow (Play manages the app-signing key; you manage the
  upload key). Do not try to opt out unless you have a
  regulatory reason to.
