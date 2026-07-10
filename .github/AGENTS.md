# AGENTS.md — Wakey-Wakey (Flutter Android Alarm App)

> This file provides operating instructions for any AI coding assistant
> (Claude Code, GitHub Copilot, Cursor, etc.) working in this repository.
> It is tool-agnostic by design. Read this file in full before making any
> changes.

---

## 1. Required Reading Before Any Work

Before writing or modifying any code, the assistant **must** read:

1. [`docs/requirements.md`](../docs/requirements.md) — product scope, tech
   stack rationale, data model, permissions strategy, and per-iteration
   feature specifications.
2. [`docs/workflow_plan.md`](../docs/workflow_plan.md) — the iteration
   breakdown (Iteration 0–4), task checklists, dependencies between
   iterations, and the Definition of Done (DoD) for each.

> Adjust the paths above if these docs live elsewhere in this repo (e.g.
> `/docs` vs repo root) — but do not proceed without locating and reading
> both files first.

These two documents are the source of truth for scope and sequencing.
**Do not invent new features, restructure the iteration order, or change
architectural decisions (state management, persistence layer, native
bridge pattern, etc.) without explicitly flagging the change and getting
confirmation first.**

---

## 2. Available Skills (`.github/skills/`)

Before starting **any** task — writing code, planning an iteration,
touching native Android code, generating tests, or writing documentation
— check `.github/skills/` for a skill relevant to that task, and read it
in full before proceeding.

- Treat this as a mandatory first step, not an optional lookup. Skills
  encode project-specific or environment-specific conventions (e.g. how
  this project structures `MethodChannel` bridges, how it names sqflite
  migrations, how it wants Riverpod providers organized) that aren't
  obvious from the code alone and may not match generic training
  knowledge.
- **Check on every task, not just once per session** — a task midway
  through a long session (e.g. switching from writing Dart UI to writing
  native Kotlin) may need a different skill than the one already loaded.
- Multiple skills may apply to a single task (e.g. a task might touch both
  a "flutter-testing" skill and a "native-android-bridge" skill) — check
  for all relevant ones, don't stop at the first match.
- If no skill in `.github/skills/` covers the task at hand, proceed using
  the conventions already established in this file, `requirements.md`,
  and the existing codebase — do not treat a missing skill as a blocker.
- If a skill's guidance appears to conflict with something in
  `requirements.md` or `workflow_plan.md`, flag the conflict rather than
  silently picking one over the other.

---

## 3. Project Summary

Wakey-Wakey is an **Android-only** (Phase 1) Flutter alarm app. Its core
differentiator is a **geofencing alarm** that triggers based on proximity
to a location rather than wall-clock time, alongside standard alarm,
stopwatch, and timer features.

| Decision | Value |
|---|---|
| Platform | Android only, minSdk 26 |
| State management | Riverpod |
| Persistence | `sqflite` (alarms/timers/geofences), `shared_preferences` (settings) |
| Alarm firing | Native `AlarmManager.setAlarmClock()` → `BroadcastReceiver` → foreground `Service` → full-screen ringing `Activity`, bridged via `MethodChannel` |
| Geofencing | Native `GeofencingClient` (Google Play Services), **not** a third-party Flutter plugin |
| Maps | `google_maps_flutter` |
| Testing | Dart unit/widget tests (automated) + manual on-device checklist (native-touching features) |

Full rationale for each decision is in `requirements.md` — do not
re-derive or second-guess these without flagging it explicitly.

---

## 4. Iteration Discipline

Work proceeds **strictly iteration by iteration**, per `workflow_plan.md`:

- **Iteration 0** — Foundation (scaffolding, schema, Riverpod, MethodChannel stubs, permissions plumbing)
- **Iteration 1** — Normal alarm
- **Iteration 2** — Stopwatch
- **Iteration 3** — Timer
- **Iteration 4** — Geofencing alarm

Rules:

- Do not begin an iteration until the previous one's Definition of Done is
  fully met (see `workflow_plan.md` for the exact checklist per
  iteration).
- Do not silently combine or skip iterations to "save time."
- When an iteration is complete, update the checkboxes in
  `workflow_plan.md` to reflect what was actually done — this file is a
  living tracker, not a static plan.
- If a task in `workflow_plan.md` turns out to be infeasible or wrong as
  written, stop and flag it rather than quietly reinterpreting it.

---

## 5. Environment: WSL Only

**All build, test, and tooling commands must be run inside WSL (Ubuntu),
not native Windows PowerShell/CMD.** This includes `flutter`, `dart`,
`adb`, `sdkmanager`, `git`, and any shell scripts generated for this
project.

Specifically:

- The project directory must live on the **Linux filesystem inside WSL**
  (e.g. `~/projects/wakey-wakey`), **not** under `/mnt/c/...` or
  `/mnt/d/...`. Windows-mounted paths go through a slow filesystem
  translation layer and cause noticeably slower, occasionally flaky
  Gradle/Android builds.
- Any shell command the assistant proposes or runs (`flutter run`,
  `flutter test`, `flutter build apk`, `adb devices`, `sdkmanager ...`)
  should be written assuming a WSL Ubuntu bash shell.
- Device connectivity for physical-device testing is bridged from Windows
  into WSL via `usbipd-win`. The assistant should assume `adb devices`
  reflects whatever is currently attached via `usbipd attach` on the
  Windows side — it should not attempt to manage USB attachment itself,
  since that step happens outside WSL.
- If a command must be run on the Windows side (e.g. `usbipd` commands),
  say so explicitly rather than assuming it can be run from within the
  WSL shell.

---

## 6. Flutter Code Style & Conventions

- Follow **Effective Dart** conventions (naming, formatting, documentation
  comments) throughout: https://dart.dev/effective-dart
- Run `dart format .` before considering any file complete. Do not hand
  back unformatted code.
- Run `flutter analyze` and resolve all warnings/errors before marking a
  task done — do not leave lint issues for "later cleanup."
- **Folder structure** (established in Iteration 0, do not deviate):
  ```
  lib/
    data/          # sqflite schema, DAOs, repositories
    domain/        # models, business logic, use cases
    presentation/  # screens, widgets, Riverpod providers/state
    native_bridge/ # MethodChannel wrappers (Dart side)
  android/
    app/src/main/kotlin/...  # AlarmManager, BroadcastReceiver, Service, GeofencingClient (native side)
  ```
- **Widget composition:** prefer small, single-purpose widgets over large
  monolithic `build()` methods. Extract reusable UI (e.g. the ringing
  screen, used by both alarm and timer) into shared widgets rather than
  duplicating markup.
- **State management:** use Riverpod providers (`Notifier`/`AsyncNotifier`
  for mutable state, `Provider`/`StreamProvider` for derived/native event
  state). Do not introduce `setState`-based state management for
  anything beyond trivial, purely-local UI state (e.g. a text field's
  focus state).
- **Naming:** `snake_case` for files, `UpperCamelCase` for classes/widgets,
  `lowerCamelCase` for variables/methods, consistent with Dart convention.
- **Null safety:** the codebase is fully null-safe. Avoid `!` (null
  assertion) unless genuinely provably non-null — prefer explicit null
  checks or `??` fallbacks.
- **Comments:** document *why*, not *what*, especially around native
  bridge code and any Android-version-specific branching (e.g. API 31+
  exact alarm permission handling) — these are exactly the places a future
  reader (human or AI) will need context that isn't obvious from the code
  alone.

---

## 7. Commit & Change History Discipline

Work must be committed **frequently and granularly** — after each small
milestone or completed step, not just at the end of an iteration. A
"milestone" here means something like: a schema created, a single screen
implemented, a `MethodChannel` method wired end-to-end, a test suite added
and passing — not an entire iteration bundled into one commit.

### 6.1 Commit rules

- Commit as soon as a small, coherent unit of work is complete and in a
  working state (code compiles, `flutter analyze` is clean, relevant
  tests pass). Do not batch multiple unrelated changes into one commit.
- Use clear, conventional commit messages, prefixed with the iteration:
  ```
  [Iter0] Add sqflite schema for alarms and timers tables
  [Iter1] Implement AlarmManager.setAlarmClock native scheduling
  [Iter1] Add dismiss/snooze handling in ringing Activity
  [Iter4] Add radius validation (200m-20km) to geofence alarm model
  ```
- Never force-push or rewrite history on shared branches.
- If a change spans both Dart and native Kotlin code for the same
  feature step, it may be committed together, but unrelated Dart-only and
  Kotlin-only changes should still be separate commits.

### 6.2 History log (`.github/history/`)

In addition to normal git commits, maintain a **human-readable change
log** in `.github/history/`, one file per commit (or tightly-grouped
milestone), so the project's evolution can be reviewed without needing to
dig through `git log` diffs.

- **File naming:** `YYYY-MM-DD-HHmm_short-slug.md`, e.g.
  `2026-07-10-1430_iter0-sqflite-schema.md`. Use the commit timestamp
  (local time) and a short kebab-case description matching the commit.
- **File contents**, each entry should include:
  ```markdown
  # <Milestone title>

  - **Date:** 2026-07-10 14:30
  - **Iteration:** 0
  - **Commit:** <git short SHA, filled in after committing>

  ## What changed
  Brief description of the change in plain language.

  ## Why
  Why this change was made / which requirement or workflow task it
  addresses (reference `requirements.md` / `workflow_plan.md` section if
  applicable).

  ## Files touched
  - path/to/file1.dart
  - path/to/file2.kt

  ## Verification
  - [ ] `flutter analyze` clean
  - [ ] `flutter test` passing
  - [ ] Manual on-device check needed? (yes/no — describe if yes)
  ```
- Write the history entry **before or immediately after** committing —
  it should never lag more than one step behind the actual commits.
- Do not skip history entries for "small" changes — the point of this
  folder is a complete, granular record, not a curated highlight reel.
- These files are additive only — never delete or rewrite a past history
  entry. If a past decision is later reversed, add a **new** entry
  explaining the reversal and link back to the original file by name.

---

## 8. Testing Requirements Per Iteration

Per the Definition of Done in `workflow_plan.md`, every iteration has two
layers of testing — **both are required, not optional:**

1. **Automated (assistant-runnable):** Dart unit tests and widget tests.
   Run `flutter test` and confirm all pass before reporting an iteration
   as complete. Write new tests alongside new features — do not defer
   test-writing to "a later cleanup pass."
2. **Manual on-device (human-runnable only):** Any iteration touching
   native code (Iterations 1, 3, 4) has a manual checklist in
   `workflow_plan.md` (e.g. "force-kill the app, confirm alarm still
   rings"). **The assistant cannot perform these steps itself** — it
   should clearly list which manual checks remain outstanding for the
   human to verify on their physical device, rather than assuming they're
   covered by automated tests.

Do not report an iteration as "done" if only the automated tests pass —
explicitly state that manual on-device verification is still pending.

---

## 9. Verification Checklist (for human review)

Before accepting any iteration's work as complete, the human reviewer
should confirm:

- [ ] `flutter analyze` returns no errors or warnings
- [ ] `dart format --output=none --set-exit-if-changed .` passes (code is
      properly formatted)
- [ ] `flutter test` passes with no skipped/failing tests
- [ ] `workflow_plan.md` checkboxes for this iteration are updated to
      match actual completed work
- [ ] Any native Kotlin code (`AlarmManager`, `BroadcastReceiver`,
      foreground `Service`, `GeofencingClient` usage) has been read and
      understood by a human, not merely accepted on trust — these are the
      highest-risk, silent-failure-prone parts of the app
- [ ] The manual on-device checklist for this iteration (per
      `workflow_plan.md`) has been physically run on a real Android device
      and passed
- [ ] No scope creep: features beyond what `requirements.md` specifies for
      this iteration were not introduced without discussion
- [ ] Git history for this iteration is clean and reviewable (logically
      separated commits, descriptive messages) — not one giant
      unreviewable commit
- [ ] `.github/history/` has one entry per commit made during this
      iteration, each filled out completely (not left as a template
      stub)

---

## 10. What Not To Do

- Do not use third-party Flutter geofencing plugins as a shortcut — the
  native `GeofencingClient` approach is a deliberate architectural
  decision (see `requirements.md` §2), not an oversight.
- Do not add anti-oversleep dismiss mechanics (math puzzles,
  shake-to-dismiss, etc.) — explicitly deferred out of Phase 1 scope.
- Do not implement iOS-specific code paths — Phase 1 is Android only.
- Do not combine time and location triggers into a single `BOTH` alarm
  type — deferred, per `requirements.md` §6.
- Do not silently swap Riverpod for another state management approach,
  or `sqflite` for another persistence layer, even if it seems simpler for
  a given task.
- Do not request all Android permissions upfront on first launch — the
  staged, contextual permission flow (per `requirements.md` §4) is a
  deliberate UX decision.

---

## 11. When Uncertain

If a requirement is ambiguous, or a decision in `requirements.md` /
`workflow_plan.md` seems to conflict with something being implemented,
**stop and ask** rather than guessing. Silent assumptions in an alarm
app — especially around permissions, native scheduling, or geofence
arming/disarming — carry real risk of the app failing to wake the user,
which is the one failure mode this project cannot tolerate.
