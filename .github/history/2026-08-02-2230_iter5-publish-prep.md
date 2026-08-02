# [Iter5] Play Store publishing prep — Iteration 5 Phase D

- **Date:** 2026-08-02 22:30
- **Iteration:** 5 (publishing prep — does not touch runtime behaviour)
- **Commit:** `cb87a3d`

## What changed

The Iteration 5 features (favourites + permission UX) are
code-complete; this commit is the **publishing scaffolding**
around them: the keystore, signing config, store assets,
privacy policy, Data Safety answers, permission
justifications, and the runbook for filling the Play
Console form. It is a separate commit because it does not
touch Dart or Kotlin source — only the build chain, the
resource directory, and four documentation files.

## Why

`workflow_plan.md` originally scoped Iteration 5 to
favourites + permission UX. Once those were done, the
project had no publishing pipeline: the release `buildType`
still signed with the debug keystore (which Play Console
rejects), there was no privacy policy, no store icon, no
Data Safety answers, and no runbook. The publishing prep
is the delta from "the AAB builds" to "the AAB is ready to
upload to Play Console."

The end-to-end Play Console walkthrough still has to be
performed by the human (it requires the $25 registration,
identity verification, hosted privacy policy, and on-device
screenshots). The runbook is structured so they can do
that without further help from the assistant.

## Files touched

### Build chain
- `android/app/build.gradle.kts` — release `buildType` now
  signs with the upload keystore (via
  `android/key.properties`, gitignored); `splits.abi`
  block removed (incompatible with AAB builds, see
  https://issuetracker.google.com/402800800).
- `android/key.properties` — keystore credentials
  (gitignored; not in this commit).
- `android/app/wakey-upload-key.jks` — the upload keystore
  itself (gitignored; not in this commit). RSA 4096,
  9125-day validity, alias `upload`, DN
  `CN=TingerBuddanna, OU=Wakey-Wakey, O=TingerBuddanna`.
  SHA-1 `2F:C3:08:53:38:C4:1E:F9:DA:82:9E:09:8D:53:96:D0:E3:38:3C:2E`.

### Resources
- `android/app/src/main/AndroidManifest.xml` —
  `android:roundIcon`, `android:dataExtractionRules`,
  `android:fullBackupContent` added.
- `android/app/src/main/res/xml/backup_rules.xml` (new) —
  API 23-30 Auto Backup rules. Includes sharedpref +
  database + file; no `cache` exclude (the domain is
  invalid in the schema, and caches are never backed up
  by default).
- `android/app/src/main/res/xml/data_extraction_rules.xml`
  (new) — API 31+ data extraction rules (cloud backup +
  device-to-device transfer). Same policy as above.
- `android/app/src/main/res/values/colors.xml` (new) —
  `ic_launcher_background = #1E3A8A` for the adaptive
  icon background.
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
  (new) — adaptive icon (background colour + foreground
  drawable + monochrome variant).
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml`
  (new) — round variant, same content (launcher applies
  the mask).
- `android/app/src/main/res/drawable/ic_launcher_foreground.png`
  (new, 432×432) — the foreground artwork rendered by
  `tools/generate_launcher_icon.py`.
- `android/app/src/main/res/mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher.png`
  (regenerated) — legacy launcher fallback for launchers
  on API 26-27 that prefer the static icon.
- `android/app/src/main/res/mipmap-{m,h,xh,xxh,xxxh}dpi/ic_launcher_round.png`
  (new) — same artwork as `ic_launcher.png`, in the
  round resource slot.

### Assets
- `store_assets/icon-512.png` (new, 512×512) — Play Store
  listing icon.
- `store_assets/feature-graphic-1024x500.png` (new,
  1024×500) — Play Store feature graphic.
- `store_assets/README.md` (new) — documents the
  directory layout and how to regenerate the assets.
- `tools/generate_launcher_icon.py` (new) — pure-Python
  (stdlib only, no Pillow / ImageMagick) renderer. Box-
  filter downscales a 1024×1024 master design to every
  Play- and Android-required size. Idempotent.

### Documentation
- `docs/privacy-policy.md` (new) — accurate description
  of every on-device data category and the third-party
  SDKs (Google Play Services Location, Maps). Placeholder
  contact email; the runbook walks through hosting this
  on GitHub Pages and editing the placeholder before
  going live.
- `docs/data-safety.md` (new) — paste-ready answers for
  the Play Console Data Safety form, with code references
  for each answer (which file in the repo justifies the
  claim).
- `docs/permission-justifications.md` (new) — paste-
  ready justifications for every runtime permission the
  manifest declares. The long-form text is written to
  match the strict framing the Play policy team now
  requires; a short cheat-sheet at the bottom for the
  common case.
- `docs/play-store-publish.md` (new) — end-to-end
  runbook from pre-flight through post-publish, including
  the privacy policy hosting, screenshot capture, Data
  Safety form, permission declarations, staged rollout,
  and what to do on rejection.

### Pubspec
- `pubspec.yaml` — `description` field updated from the
  Flutter scaffold's "A new Flutter project." to a real
  product description. (The package is not published to
  pub.dev, but the field is shown by IDE tooling and is
  the canonical pubspec description.)

### Gitignore
- `.gitignore` — `/android/key.properties`,
  `/android/app/*.jks`, `/android/app/*.keystore` added.
  `android/.gitignore` already had equivalent rules; the
  root-level additions are defence in depth.

### Workflow plan
- `docs/workflow_plan.md` — new "Iteration 5 — Phase D:
  Play Store publishing prep" section at the end, with
  the same task-list / Dependencies / DoD structure as
  the other iterations. The publishing prep's DoD
  explicitly notes that the underlying feature DoD
  (favourites flow, permission wizard, geofence boot
  re-arm) is still pending human verification on a
  physical device — the publishing prep does not close
  those out.

## Verification

- [x] `flutter analyze` clean (10 min on WSL due to
      the repo size + the `/mnt/d/...` mount layer; was
      previously clean before this change too).
- [x] `flutter test` — 328 tests pass (unchanged).
- [x] `flutter build appbundle --release` succeeds
      (3-4 min). Output:
      `build/app/outputs/bundle/release/app-release.aab`
      (54.1 MB). Verified signed via:
      ```bash
      unzip -p build/app/outputs/bundle/release/app-release.aab \
        META-INF/UPLOAD.RSA > /tmp/upload.rsa
      keytool -printcert -file /tmp/upload.rsa
      # Owner: CN=TingerBuddanna, OU=Wakey-Wakey, O=TingerBuddanna
      # SHA1: 2F:C3:08:53:38:C4:1E:F9:DA:82:9E:09:8D:53:96:D0:E3:38:3C:2E
      # 4096-bit RSA, valid until 2051.
      ```
- [ ] **Manual (on-device):** the underlying Iteration 5
      features — favourites flow, permission wizard,
      geofence boot re-arm — see the existing Iteration 5
      DoD checkboxes in `workflow_plan.md`. **Still
      pending human verification.** The publishing prep
      does not close them out.
- [ ] **Manual (Play Console):** walk through
      `docs/play-store-publish.md` to fill the Console
      form, upload the AAB, and start the rollout. This
      requires the $25 Play Developer registration, a
      hosted privacy policy URL, and real device
      screenshots — none of which the assistant can
      perform.

## Architectural / scope decisions

These were the non-obvious choices. They're called out here
so the next person reviewing this commit doesn't waste time
re-deriving them.

1. **PKCS12 keystore, not JKS.** The default since JDK 9
   is PKCS12; `keytool -keypass` is ignored on PKCS12 (a
   single password protects both the store and the key).
   `key.properties` has `keyPassword == storePassword`,
   not because that's a property of PKCS12 itself, but
   because that's how `keytool` produces a PKCS12 file —
   you can't have a different key password from the
   store password.

2. **`storeFile` path resolution.** The `storeFile` in
   `key.properties` is `app/wakey-upload-key.jks`
   (relative to the `android/` subproject, which is
   `rootProject` from the `:app` module's perspective).
   `key.properties` itself is at `android/key.properties`,
   also relative to `android/`. The pattern of using
   `rootProject.file(...)` for both means the build is
   independent of where the repo is checked out (it
   works from `/mnt/d/...` on WSL, from `~/projects/...`
   on WSL, and from CI).

3. **Adaptive icon + legacy mipmap PNGs, both.** The
   adaptive XML lives under `mipmap-anydpi-v26/` and is
   picked up by API 26+ launchers. The legacy mipmap PNGs
   in `mipmap-{m,h,xh,xxh,xxxh}dpi/` are also kept because:
   (a) Play Console and some launchers on API 26-27 still
   prefer the static PNG, (b) a missing PNG would be
   substituted with a generic Android icon, which is ugly.
   The same artwork is used for both, generated from a
   single 1024×1024 master with a box-filter downscale.

4. **`splits.abi` removed, not gated.** AAB and per-ABI
   splits are mutually exclusive (see the
   https://issuetracker.google.com/402800800 link in the
   Gradle file). The splits were a dev-time convenience
   for direct sideloading. For Play distribution, Google
   splits per-ABI internally, so the splits are redundant
   and would actively break the AAB build. Removed
   outright; the runbook documents
   `flutter build apk --split-per-abi` for the rare case
   where a lean per-ABI APK is needed for sideloading.

5. **No `cache` exclude in backup rules.** The lint check
   for `FullBackupContent` rejects `<exclude domain="cache">`
   because `cache` isn't a valid exclude domain in the
   schema — and caches are never backed up by the platform
   by default, so the exclude is redundant anyway. The
   fix is to not list the cache exclude at all, which
   matches the platform's default behaviour.

6. **Privacy policy hosted on GitHub Pages, not a
   dedicated server.** Free, reliable, no maintenance,
   version-controllable (the in-repo `privacy-policy.md`
   is the source of truth; the GitHub Pages site is a
   one-command deploy). The user can switch to a
   dedicated host later if they want.

7. **No automated screenshot capture.** The runbook
   explicitly says the human captures screenshots on a
   physical device. Automated capture (via
   `flutter_test` golden files or integration tests) is
   a future polish — for v1.0.0, the variation in device
   sizes, dynamic colour, lock-screen UI, and the
   geofence-in-progress state is hard to get right
   programmatically, and Play reviewers are stricter
   about "this screenshot is not from the real app"
   than about "this screenshot is not exactly the
   marketing-blessed layout."

8. **Maps API key.** A real key is already present in
   `android/local.properties` (gitignored), so the AAB
   is built with a real key and the map picker will
   render. The runbook walks through the Google Cloud
   Console restriction setup (package name +
   upload-keystore SHA-1) so the key can't be abused if
   it leaks. If the user rotates the key later, edit
   `local.properties` and rebuild the AAB.
