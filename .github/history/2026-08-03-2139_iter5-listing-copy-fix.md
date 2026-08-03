# 2026-08-03 21:39 — Iter5 — store listing copy: geofence pitch correction

- **Date:** 2026-08-03 21:39
- **Iteration:** 5 (publishing prep — listing copy only)
- **Commit:** `6f127f1`

## What
Two factual copy fixes in the runbook's full-description sample
(`docs/play-store-publish.md` §5.3) so the geofence pitch matches
the actual geofence semantics.

### Before → After

1. §5.3 Geofence alarms paragraph:
   - Before: "…so you can doze off on the train and wake up a few
     kilometres before your stop."
   - After: "…so you can doze off on the train and wake up as you
     pull into your stop."
   - Reason: the geofence ENTER event fires when the device
     crosses *into* the registered circle, not when it's
     approaching it. The previous wording promised a feature
     the API does not have.

2. §5.3 Favourite locations paragraph:
   - Before: "Two taps from 'I want to wake up before I reach
     the airport' to 'armed.'"
   - After: "Two taps from 'I want to be woken as I arrive at
     the airport' to 'armed.'"
   - Reason: same fix — the alarm fires at the centre of the
     geofence, not before it.

## Why
A reviewer or a user who tests the actual feature would notice
the discrepancy immediately. The first reviewer to install the
app, set a geofence at their home, and wait for the alarm would
find the alarm firing when they entered home, not before — and
the listing copy would be the first thing they pasted into a
one-star review.

## Verified
- `flutter analyze` not re-run (docs-only change).
- No AAB rebuild required.
- The corrected full description is also pasted directly into
  the chat for the developer to copy into the Play Console
  short-form field (the runbook version and the paste-ready
  version are kept in sync).
