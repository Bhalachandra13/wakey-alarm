# fix(alarm): guard AlarmService null-intent + START_REDELIVER_INTENT

- **Date:** 2026-08-02 17:20
- **Iteration:** 1 (alarm service robustness)
- **Commit:** 7575577

## What changed

`AlarmService.onStartCommand` now:

- Rejects a `null` `intent` explicitly. The OS may re-deliver a
  null intent to the service if the process is killed and
  restarted under memory pressure (the previous `START_STICKY`
  semantics). Falling through to the "start ringing" branch
  with a null intent would re-fire the ringtone with
  `alarmId = -1` and a default label — a phantom alarm the
  user cannot identify or dismiss properly. The guard stops
  the service and returns `START_NOT_STICKY`.
- Returns `START_REDELIVER_INTENT` instead of `START_STICKY`.
  If the OS kills the foreground service mid-ring
  (low-memory kill, Doze-induced restart, …) it will
  re-deliver the *original* intent, so the ringtone resumes
  with the same alarmId and metadata. `START_STICKY` would
  re-deliver a null intent, which the new guard at the top of
  `onStartCommand` now rejects, so `START_REDELIVER_INTENT` is
  the right flag for a service whose state is fully
  intent-derived.
- Drops the now-unnecessary `intent?` (nullable) receivers on
  every `getXxxExtra` call. The intent is proven non-null at
  the top of the method, so the chained `?.` / `?:` Elvis
  patterns are gone in favour of direct access.

## Why

A user report (paired with the timer live-countdown fix in
the same on-device pass) noted the alarm service occasionally
phantom-rang on devices with aggressive battery management
that killed the FGS and restarted it. The null-intent guard +
`START_REDELIVER_INTENT` is the minimum-change fix: the
service either resumes the real ring or stays silent, never
rings a phantom alarm.

## Files touched

- android/app/src/main/kotlin/com/wakeywakey/app/AlarmService.kt

## Verification

- [x] Compiles into the existing debug/release pipeline.
- [x] `flutter analyze` clean (the change is Kotlin-only; the
      Dart tree is unaffected).
- [ ] Manual on-device: force-kill the app process while an
      alarm is ringing, confirm either (a) the ring resumes
      with the same alarmId or (b) the service stays silent.
      Never a phantom ring. (Per workflow_plan.md Iter 1
      manual DoD; human verification on a real device.)
