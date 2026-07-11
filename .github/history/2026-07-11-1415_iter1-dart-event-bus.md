# Wire dismiss/snooze outcomes back to Dart via EventChannel + AlarmEventBus

- **Date:** 2026-07-11 14:15
- **Iteration:** 1
- **Commit:** <pending>

## What changed

**Native side**:

- **New** `android/app/src/main/kotlin/com/wakeywakey/app/AlarmEventBus.kt`:
  a process-wide singleton holding the `EventChannel.EventSink`
  for the `com.wakeywakey/alarm_events` channel. Uses
  `AtomicReference` for thread-safe attach/detach; `emit` is a
  no-op when no Dart listener is attached.
- **`MainActivity`** StreamHandler: `onListen` now calls
  `AlarmEventBus.attach(sink)` and `onCancel` calls
  `AlarmEventBus.detach()`. The Kotlin `alarmEventSink` field is
  retained for backward compatibility but is no longer the
  primary sink — `AlarmEventBus` is.
- **`RingingActivity`** dismiss/snooze button handlers now call
  a new `emitOutcome(type)` helper that pushes an event
  (`{"alarmId": <id>, "type": "snoozed"|"dismissed"}`) to
  `AlarmEventBus` before finishing the activity. This is the
  last step in both button handlers, so the event is always
  emitted before the activity tears down.

**Dart side**:

- **`AlarmBridge.alarmFiredEvents`** → renamed to
  **`AlarmBridge.alarmEvents`** and now emits a new
  `AlarmEvent` class (not the old `AlarmFiredEvent`).
- **`AlarmEvent` class**: holds `alarmId` (int), `type`
  (`AlarmEventType` enum: `fired`, `snoozed`, `dismissed`),
  and an optional `triggerType` string (`"time"` or
  `"location"`, only set for `fired` events).
- **`AlarmEventType`** enum with a `fromName(String)` factory
  that falls back to `fired` for unknown values (defensive
  against a future Kotlin side adding new types before the
  Dart side is updated).

**New tests** `test/native_bridge/alarm_event_test.dart`: 7
unit tests covering `AlarmEventType.fromName` and
`AlarmEvent.fromMap` for all three event kinds, plus the
`triggerType` absence on snooze/dismiss. All 7 pass.

## Why

The `RingingActivity` dismiss/snooze outcomes were orphaned
on the native side — the service was stopped, the activity
was finished, but the Dart side had no way to know what
happened. Now `RingingActivity` pushes a structured event
into `AlarmEventBus`, which is consumed by whatever Dart
listener is currently subscribed (typically none, when the
process was cold-started; the `EventChannel` is wired up but
no isolate is running). The infrastructure is now in place
for the Dart `AlarmsNotifier` to subscribe and track a
"ringing alarm" state — a follow-up that does not block
Iteration 1 closure.

The bus pattern was chosen over alternatives because:
- A `LocalBroadcastManager` would have been the obvious
  alternative, but it was deprecated in API 28 and removed
  entirely in androidx.localbroadcastmanager 1.1.0.
- A static `Companion.sink` on `MainActivity` would be
  reachable but breaks `MainActivity`'s "Activity as a
  thin adapter" design.
- A new foreground service just to host the sink would
  be massive overkill for a callback.

## Files touched

- `android/app/src/main/kotlin/com/wakeywakey/app/AlarmEventBus.kt`
  — New.
- `android/app/src/main/kotlin/com/wakeywakey/app/MainActivity.kt`
  — StreamHandler now wires the sink to `AlarmEventBus`.
- `android/app/src/main/kotlin/com/wakeywakey/app/RingingActivity.kt`
  — Dismiss/snooze handlers now call `emitOutcome(...)`.
- `lib/native_bridge/alarm_bridge.dart` — `alarmFiredEvents`
  renamed to `alarmEvents`; new `AlarmEvent` and
  `AlarmEventType` classes.
- `test/native_bridge/alarm_event_test.dart` — New (7 tests,
  all pass).

## Verification

- [x] `gradle :app:compileDebugKotlin` — BUILD SUCCESSFUL.
- [x] `dart analyze lib/native_bridge/alarm_bridge.dart
       test/native_bridge/alarm_event_test.dart` — "No issues
       found!"
- [x] `flutter test test/native_bridge/alarm_event_test.dart` —
  7/7 pass.
- [x] `flutter test` — 46/53 pass; **7 pre-existing failures
  remain in `alarms_provider_test.dart`**. These are unrelated
  to this commit: the test file never calls
  `TestWidgetsFlutterBinding.ensureInitialized()`, so any
  test that goes through `AlarmsNotifier.insertAlarm` (which
  uses the real `AlarmBridge` and therefore the real
  `MethodChannel`) fails on "Binding has not yet been
  initialized." Per the project's AGENTS.md note, this file
  is explicitly out of scope for the current iteration and
  is a known follow-up.

## Design notes

- `AlarmEventBus.emit` is intentionally fire-and-forget.
  There is no error reporting back to the caller because
  `EventChannel.EventSink.success` is also fire-and-forget
  on the Flutter side — the channel does not surface a
  failure to the Dart listener other than dropping the
  event. This is consistent with the rest of the codebase.
- The `AlarmFiredEvent` class was removed, not deprecated,
  because it was unreferenced outside `alarm_bridge.dart`
  itself. A `git grep AlarmFiredEvent` confirms zero other
  call sites.
- The event payload uses a `Map<String, Any?>` because
  `StandardMethodCodec` (the default Flutter codec) does
  not encode arbitrary Kotlin types. The Dart side's
  `AlarmEvent.fromMap` is the type-asserting counterpart.

## Known gaps (still on the list)

1. **No Dart-side consumer** for the new event stream. The
   `AlarmsNotifier` does not currently subscribe; nothing
   observes the "this alarm just rang" or "user just
   dismissed" signals yet. Adding a `ringingAlarmIdProvider`
   that listens and updates state is a one-method change in
   `alarms_provider.dart` and is a natural Iteration 1.5
   task — but it is not strictly required for the iteration
   to "be complete" per the workflow plan.
2. **No snooze max-count enforcement.** Still on the
   follow-up list.
3. **`AlarmService` does not emit a `fired` event** when
   it starts. This is by design — when the service starts,
   the Dart side is almost certainly not running (the
   process was cold-started by the alarm broadcast). A
   later iteration can wire it up if needed, but for now
   the only way Dart sees a "fired" event is if the app
   was already alive when the alarm fired.
