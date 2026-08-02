import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/domain/timer_record.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';
import 'package:wakey_alarm/presentation/providers/timers_provider.dart';
import 'package:wakey_alarm/presentation/screens/timer_detail_screen.dart';

class _FakeAlarmBridge implements AlarmBridge {
  _FakeAlarmBridge()
    : eventController = StreamController<AlarmEvent>.broadcast();
  final StreamController<AlarmEvent> eventController;
  @override
  Stream<AlarmEvent>? eventStream;
  @override
  Stream<AlarmEvent> get alarmEvents => eventController.stream;
  @override
  Future<bool> scheduleAlarm(Map<String, Object?> payload) async => true;
  @override
  Future<bool> scheduleTimer(Map<String, Object?> payload) async => true;
  @override
  Future<bool> cancelAlarm(int alarmId) async => true;
  @override
  Future<String?> pickRingtone({String? currentUri}) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late WakeyDatabase database;
  late _FakeAlarmBridge fakeBridge;

  setUp(() async {
    fakeBridge = _FakeAlarmBridge();
    addTearDown(fakeBridge.eventController.close);

    database = WakeyDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: ':memory:',
    );
    await database.open();
  });

  tearDown(() async {
    await database.close();
  });

  group('TimerDetailScreen', () {
    testWidgets('renders the timer label and initial remaining time', (
      tester,
    ) async {
      // Pre-seed an active timer in the DB.
      final container = ProviderContainer(
        overrides: [
          timersProvider.overrideWith(_SeededRunningTimerNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: TimerDetailScreen(timerId: 1),
          ),
        ),
      );
      // The detail screen has a repeating AnimationController for
      // the heartbeat pulse, so `pumpAndSettle` would never
      // complete. A single `pump` is enough for the first build.
      await tester.pump();

      expect(find.text('Boil eggs'), findsOneWidget);
      // 300s == 5:00 — the formatted remaining text is the source
      // of truth for the detail screen.
      expect(find.text('05:00'), findsOneWidget);
      // The state pill says "Running".
      expect(find.text('Running'), findsOneWidget);

      // Tear down by swapping the tree to an empty widget. The
      // detail screen's `dispose()` runs and the repeating
      // AnimationController is cancelled, letting the test
      // process exit cleanly. We avoid `tester.pageBack`
      // because that helper looks for a Material back button,
      // which the AppBar only auto-injects when there's a route
      // underneath — our test pump doesn't push one.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets(
      'the countdown is sourced from the per-timer live provider',
      (tester) async {
        // Build a notifier that always reports a 42s remaining
        // value. We verify the detail screen reads from the
        // per-timer provider (not a hard-coded "duration" value)
        // by picking a duration that does NOT match the live
        // value and asserting the live one wins.
        final container = ProviderContainer(
          overrides: [
            timersProvider.overrideWith(
              _SeededTimersNotifierWithValue.new,
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: TimerDetailScreen(timerId: 1),
            ),
          ),
        );
        await tester.pump();

        // The seeded live value is 42s → 00:42. The DB value is
        // 60s → 01:00. The detail screen shows 00:42 because the
        // live provider takes precedence.
        expect(find.text('00:42'), findsOneWidget);
        expect(find.text('01:00'), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'tapping pause via the provider flips the state pill to Paused',
      (tester) async {
        final notifier = _SeededRunningTimerNotifier();
        final container = ProviderContainer(
          overrides: [
            timersProvider.overrideWith(() => notifier),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: TimerDetailScreen(timerId: 1),
            ),
          ),
        );
        await tester.pump();

        // Pump the action and assert the state changed. We don't
        // go through the InkWell here because the test for the
        // pause flow is the notifier's responsibility; this test
        // is about the UI's reaction to the state change.
        await notifier.pause(1);
        await tester.pump();
        expect(find.text('Paused'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });
}

/// A notifier that returns a single RUNNING timer. Used by the
/// detail screen tests so we don't have to spin up a real
/// `Timer.periodic` ticker. The live-countdown test uses a
/// separate notifier that pre-populates a specific live value.
class _SeededRunningTimerNotifier extends TimersNotifier {
  @override
  Future<List<TimerRecord>> build() async {
    return const [
      TimerRecord(
        id: 1,
        label: 'Boil eggs',
        durationSeconds: 300,
        remainingSeconds: 300,
        state: TimerState.running,
        startedAt: '2026-07-22T12:00:00Z',
      ),
    ];
  }

  @override
  Future<void> pause(int id) async {
    state = AsyncData([
      const TimerRecord(
        id: 1,
        label: 'Boil eggs',
        durationSeconds: 300,
        remainingSeconds: 300,
        state: TimerState.paused,
        startedAt: '2026-07-22T12:00:00Z',
      ),
    ]);
  }
}

/// A notifier that pre-populates the live-remaining map with a
/// specific value (42s for id=1). The detail screen's
/// `liveTimerRemainingForIdProvider(1)` will return 42, which
/// proves the screen reads the per-timer live provider rather
/// than the DB value.
class _SeededTimersNotifierWithValue extends TimersNotifier {
  @override
  Future<List<TimerRecord>> build() async {
    return const [
      TimerRecord(
        id: 1,
        label: 'Live value test',
        durationSeconds: 60,
        remainingSeconds: 60,
        state: TimerState.running,
        startedAt: '2026-07-22T12:00:00Z',
      ),
    ];
  }

  @override
  int? liveRemainingFor(int id) {
    if (id == 1) return 42;
    return super.liveRemainingFor(id);
  }
}
