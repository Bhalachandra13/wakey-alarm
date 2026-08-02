# Timer countdown ticks live every second (tiles + detail ring)

- **Date:** 2026-08-02 11:50
- **Iteration:** 3 (bug fix)
- **Commit:** 885933b

## What changed

Fixes the user-reported bug: the timer countdown did not update
second by second — frozen digits in the list tiles, and a detail
screen whose heartbeat animation pulsed while the numbers (and
progress) never moved. Three root causes, all in
`TimersNotifier`:

1. **Ticker never started on cold start.** `build()` loaded
   RUNNING rows from sqflite but only `create()`/`resume()`
   started the 200 ms ticker. Any timer that outlived the process
   rendered its stale persisted `remaining_seconds` forever.
   `build()` now calls `_reseedTracking()`, which seeds an
   in-memory countdown base `(remainingSeconds, startedAt)` for
   every RUNNING row and starts the ticker — and drops ids that
   are no longer running.
2. **Countdown math double-subtracted.** The old tick computed
   `remaining = DB.remainingSeconds - elapsedSince(startedAt)`
   *and* re-persisted that value every second, so the next tick
   subtracted the full elapsed from an already-shrunk base. The
   display raced to 00:00 at ~1.5–2x speed with skipped numbers,
   then sat there with the heartbeat still pulsing. While RUNNING,
   the row's `remaining_seconds` is now immutable (written only at
   create/resume, frozen at pause); the tick is a pure function
   `clamp(base - elapsed, 0, base)` with no DB IO at all. Cold
   starts resume correctly from the same two columns.
3. **`ref.invalidateSelf()` 5x/second.** Every tick triggered a
   full sqflite reload and AsyncValue reload transitions. The tick
   now bumps a lightweight `timerTickProvider` counter (only when
   a displayed second actually flips), which
   `liveTimerRemainingForIdProvider` /
   `liveTimerRemainingProvider` watch — the countdown UI rebuilds
   once per second without touching the DB.

Event handling: `fired`/`snoozed` now route through
`_deferToNative()` — the id is untracked, the row's remaining is
pinned to 0 (so the fallback display shows 00:00, not the run's
base value, while the native ringing UI owns the timer), and the
id is session-marked so `_reseedTracking` doesn't resurrect its
countdown on rebuild. `pause()` falls back to deriving the frozen
value from the seeded base when no tick has fired yet.

Detail screen: the linear progress bar is replaced by a circular
countdown ring (`_CountdownRing` + `_RingPainter`, CustomPaint).
The filled arc spans `remaining / duration` of the circumference
— full at start, depleting to empty at zero — redrawn every
second from the same live value as the digits, which sit inside
the ring and keep their heartbeat pulse while running.

Note: timers created by the old build may have a polluted
`remaining_seconds` (it was re-persisted mid-run). They resume at
a slightly low value once; freshly created timers are exact. Not
worth a schema migration for an ephemeral dev-phase row.

## Why

User report: countdown "doesn't update dynamically second by
second both in tiles and big window", "shows like heartbeat but
do not update", and the circle circumference must fill
proportionately. Requirements: workflow_plan.md Iter 3
"Countdown display UI (remaining time, pause/cancel before it
fires)".

## Files touched

- lib/presentation/providers/timers_provider.dart
- lib/presentation/screens/timer_detail_screen.dart
- lib/domain/timer_record.dart (doc comment accuracy)
- lib/data/timer_dao.dart (doc comment accuracy)
- test/presentation/providers/timers_provider_test.dart (+2
  regression tests: ticks down second-by-second at ~1s/s, and
  cold-started DB timers are tracked)
- lib/presentation/screens/timer_screen.dart,
  test/presentation/screens/timer_screen_test.dart,
  test/presentation/screens/timer_detail_screen_test.dart
  (pre-existing uncommitted multi-timer/detail-navigation work
  from the prior session, committed together as one coherent
  timer-feature unit)

## Verification

- [x] `flutter analyze` clean for all touched files (4 pre-existing
      lint infos/warnings in unrelated files left as-is)
- [x] `flutter test` passing — 294 tests, +2 new regression tests
- [ ] Manual on-device check needed? (yes) — create a timer, watch
      the tile + detail screen count down each second and the ring
      deplete; pause/resume; force-kill mid-countdown and reopen
      (should resume from the right value); let one fire and
      dismiss/snooze from the ringing UI.
