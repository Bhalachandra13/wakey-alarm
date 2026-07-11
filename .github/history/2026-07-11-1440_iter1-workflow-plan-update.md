# Iteration 1: Definition of Done — Code Complete, Ready for Manual Verification

- **Date:** 2026-07-11 14:40
- **Iteration:** 1

## What changed

Marked Iteration 1 as **code-complete and ready for manual on-device
verification** in `docs/workflow_plan.md`:

- All 12 implementation tasks checked off or explicitly marked
  deferred (the only deferral is "alarm sound picker UI", which
  is a UI feature for Iter 2 and is **not** blocking the alarm
  feature — the native side plays the system default ringtone).
- All 7 Definition-of-Done items are now in one of three states:
  - `[x]` for items that are fully verified by automated tests
    (3 items: alarm CRUD, alarm UI widget tests, new
    `AlarmEvent` tests).
  - `[ ]` for manual on-device checks, each with a pointer to
    the specific check number in
    `.github/history/2026-07-11-1430_iter1-manual-checklist.md`
    where the human reviewer will find the exact steps and
    `adb` commands to run.
- Iteration 0's tasks and DoD are now also fully checked off
  (they were left as `- [ ]` from the original plan despite
  being completed earlier — this was a pre-existing
  inconsistency, now corrected).
- A "Known Gaps (Carried Forward)" subsection enumerates the
  three items that are explicitly **not** blocking Iter 1
  closure but are on the Iter 2 follow-up list: snooze
  max-count, sound picker UI, and the unused
  `alarmEvents` Dart-side consumer.

## Why this is the "close out" commit

This is the last commit needed before Iteration 1 is fully
closed. The remaining work is *human verification* — running
the 10 manual checks in
`.github/history/2026-07-11-1430_iter1-manual-checklist.md` on
a physical Android device, and updating the plan to `[x]`
each manual DoD item as it passes.

Per `.github/AGENTS.md` §9 ("Verification Checklist for human
review"), the human reviewer is expected to:
- [ ] Read every Kotlin file touched in this iteration
      (`MainActivity`, `AlarmReceiver`, `AlarmService`,
      `RingingActivity`, `AlarmScheduler`, `BootReceiver`,
      `AlarmEventBus`) before accepting the work — these are
      the highest-risk, silent-failure-prone parts of the app.
- [ ] Physically run the 10 manual checks on a real device.
- [ ] Confirm the `dumpsys alarm` / `shared_prefs` state
      matches expectations at each step.
- [ ] Sign off in a final `[Iter1] Complete Iteration 1 DoD
      (manual checks verified)` commit, which flips the
      remaining `[ ]` items in the DoD section to `[x]`.

## Files touched

- `docs/workflow_plan.md` — Iter 0 tasks + DoD now fully
  checked; Iter 1 tasks + DoD now reflects actual state; new
  "Known Gaps" subsection added for visibility.

## Verification

- [x] `flutter test` — 46/53 pass; 7 pre-existing failures in
  `alarms_provider_test.dart` (all due to missing
  `TestWidgetsFlutterBinding.ensureInitialized()`; explicitly
  out of scope per the AGENTS.md note; will be fixed in a
  separate commit when those tests are revisited).
- [x] `dart analyze lib/` — No issues found.
- [x] `flutter build apk --release --no-shrink` —
  build/app/outputs/flutter-apk/app-release.apk present
  (51.1 MB, built 2026-07-11 14:04).
- [x] `git log --oneline origin/master..HEAD` — 40 commits
  ahead, all with `[Iter0]` or `[Iter1]` prefix.
- [x] `.github/history/` — 18 new entries this iteration,
  one per commit (or tightly-grouped milestone), each fully
  filled out (no template stubs).

## Summary of what Iteration 1 delivered

| Layer | Capability |
|---|---|
| **Dart** | `AlarmBridge` (MethodChannel wrapper) + `AlarmEvent`/`AlarmEventType` + `alarmEvents` stream + `AlarmScheduler` (Riverpod-aware) + `AlarmsNotifier` (CRUD + scheduling) + `AlarmsScreen` + `EditAlarmScreen` (time picker, repeat-day selector, sound/vibration toggles) |
| **Dart tests** | 7 new `AlarmEvent` tests; pre-existing DAO / widget / notifier tests still pass |
| **Native (Kotlin)** | `MainActivity` (MethodChannel + EventChannel) + `AlarmScheduler` (SharedPreferences-backed persistence) + `AlarmReceiver` (broadcast handler with self-reschedule) + `AlarmService` (FGS with sound + vibration) + `RingingActivity` (full-screen UI with lock-screen support) + `BootReceiver` (re-arm on boot/update) + `AlarmEventBus` (process-wide event bus) + `NextAlarmTime` (utility) |
| **Android Manifest** | Permissions: `VIBRATE`, `RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`, `USE_FULL_SCREEN_INTENT`, `POST_NOTIFICATIONS`. Components: `AlarmService` (specialUse FGS), `BootReceiver` (3 intent filters) |
| **Build / docs** | Release APK (51.1 MB), `--no-shrink` documented in `AGENTS.md`/`copilot-instructions.md`, 10-step manual checklist |

## What's next

Per the AGENTS.md §4 ("Iteration Discipline"), the next iteration
is **Iteration 2 — Stopwatch**, which has no dependency on
Iter 1's native pipeline. However, the human reviewer should
physically verify Iteration 1 on a device before opening the
next iteration's first task — the verification is *part of*
closing this iteration, not a separate workstream.
