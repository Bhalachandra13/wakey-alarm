import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';
import 'package:wakey_alarm/native_bridge/permission_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/domain/timer_record.dart';
import 'package:wakey_alarm/presentation/providers/timers_provider.dart';
import 'package:wakey_alarm/presentation/screens/timer_screen.dart';

class _FakeAlarmBridge implements AlarmBridge {
  _FakeAlarmBridge()
    : eventController = StreamController<AlarmEvent>.broadcast();
  final StreamController<AlarmEvent> eventController;
  bool scheduleTimerSuccess = true;
  @override
  Stream<AlarmEvent>? eventStream;
  @override
  Stream<AlarmEvent> get alarmEvents => eventController.stream;
  @override
  Future<bool> scheduleAlarm(Map<String, Object?> payload) async => true;
  @override
  Future<bool> scheduleTimer(Map<String, Object?> payload) async =>
      scheduleTimerSuccess;
  @override
  Future<bool> cancelAlarm(int alarmId) async => true;
  @override
  Future<String?> pickRingtone({String? currentUri}) async => null;
}

class _FakePermissionBridge implements PermissionBridge {
  _FakePermissionBridge({this.canSchedule = true});

  bool canSchedule;

  void dispose() {}

  @override
  Future<bool> canScheduleExactAlarms() async => canSchedule;

  @override
  Future<bool> requestExactAlarmPermission() async {
    canSchedule = true;
    return true;
  }

  @override
  Future<NativePermissionStatus> getNotificationPermissionStatus() async =>
      NativePermissionStatus.granted;

  @override
  Future<NativePermissionStatus> requestNotificationPermission() async =>
      NativePermissionStatus.granted;
}

class _FakeTimersNotifier extends TimersNotifier {
  bool createShouldSucceed = true;

  @override
  Future<List<TimerRecord>> build() async => const [];

  @override
  Future<bool> create({
    required String label,
    required int durationSeconds,
    String soundUri = '',
    bool vibrate = true,
    int snoozeDurationMin = 5,
    int? maxSnoozeCount,
  }) async => createShouldSucceed;
}

/// A notifier that returns a fixed list of seeded timers without
/// going through the DB. The real [TimersNotifier] starts a
/// `Timer.periodic` ticker on the first `create()`, which keeps
/// the test process alive past the test body. The seeded fake is
/// sufficient for tile-rendering tests; the live tick is covered
/// by `timers_provider_test.dart`.
class _SeededTimersNotifier extends TimersNotifier {
  @override
  Future<List<TimerRecord>> build() async {
    return const [
      TimerRecord(
        id: 1,
        label: 'Eggs',
        durationSeconds: 90,
        remainingSeconds: 90,
        state: TimerState.running,
        startedAt: '2026-07-22T12:00:00Z',
      ),
      TimerRecord(
        id: 2,
        label: 'Detail target',
        durationSeconds: 120,
        remainingSeconds: 120,
        state: TimerState.running,
        startedAt: '2026-07-22T12:00:00Z',
      ),
    ];
  }
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

  Widget wrap() {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        alarmBridgeProvider.overrideWithValue(fakeBridge),
        permissionBridgeProvider.overrideWithValue(_FakePermissionBridge()),
        alarmEventsProvider.overrideWith(
          (ref) => fakeBridge.eventController.stream,
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: TimerScreen())),
    );
  }

  /// Pumps the widget tree a few times so the async notifier's first
  /// build (which loads from sqflite) can settle. We use repeated
  /// `pump` calls rather than `pumpAndSettle` because the
  /// `alarmEventsProvider` stream is open-ended (no events are ever
  /// added in these tests), and `pumpAndSettle` will spin forever
  /// waiting on it.
  Future<void> pumpUntilData(WidgetTester tester) async {
    // The TimersNotifier's build() reads from sqflite and listens
    // to the alarm events stream. We need both to settle before the
    // empty-state UI is visible. `pumpAndSettle` doesn't work here
    // because the alarm events stream is open-ended (broadcast,
    // no events). We pump in 20ms steps until the loading
    // indicator is gone or we hit the iteration cap.
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        // One more pump so the `data` callback can settle.
        await tester.pump();
        return;
      }
    }
  }

  group('TimerScreen', () {
    testWidgets('shows the empty state on a fresh install', (tester) async {
      final container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          alarmBridgeProvider.overrideWithValue(fakeBridge),
          permissionBridgeProvider.overrideWithValue(_FakePermissionBridge()),
          alarmEventsProvider.overrideWith(
            (ref) => fakeBridge.eventController.stream,
          ),
        ],
      );
      addTearDown(container.dispose);

      // Pre-warm the timers provider future inside `runAsync` so
      // sqflite FFI can do its real-async work. The widget tree
      // builds and reads from the already-resolved future.
      final timers = await tester.runAsync(
        () => container.read(timersProvider.future),
      );
      expect(timers, isEmpty);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: TimerScreen())),
        ),
      );
      await tester.pump();

      expect(find.text('No timers yet'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('tapping the FAB pushes the create-timer screen', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await pumpUntilData(tester);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('Add Timer'), findsOneWidget);
      expect(find.text('LABEL'), findsOneWidget);
      expect(find.text('DURATION'), findsOneWidget);
      expect(find.text('Hours'), findsOneWidget);
      expect(find.text('Minutes'), findsOneWidget);
      expect(find.text('Seconds'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('create-timer shows default values (0/5/0)', (tester) async {
      await tester.pumpWidget(wrap());
      await pumpUntilData(tester);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      // The default label is "Timer".
      expect(find.text('Timer'), findsOneWidget);
      // Default duration 0/5/0 (zero-padded to two digits each).
      expect(find.text('00'), findsNWidgets(2)); // hours + seconds
      expect(find.text('05'), findsOneWidget); // minutes
    });

    testWidgets(
      'an active timer tile shows the formatted remaining time',
      (tester) async {
        // The "live" countdown is sourced from
        // [liveTimerRemainingForIdProvider], which reads the
        // notifier's per-id map. The notifier's ticker is a real
        // `Timer.periodic`, so we keep the test focused on what
        // the *tile* renders and assert the formatted DB value is
        // shown. The provider tests already cover the live tick.
        final container = ProviderContainer(
          overrides: [
            timersProvider.overrideWith(_SeededTimersNotifier.new),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(home: Scaffold(body: TimerScreen())),
          ),
        );
        await tester.pump();

        // The seeded timer is in the list and the tile shows it.
        expect(find.text('Eggs'), findsOneWidget);
        // The formatted remaining time is "01:30" (90s = 1:30).
        expect(find.text('01:30'), findsOneWidget);
      },
    );

    testWidgets('tapping a timer tile opens the detail screen', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          timersProvider.overrideWith(_SeededTimersNotifier.new),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: TimerScreen())),
        ),
      );
      await tester.pump();

      // Tap the label — the whole tile is a tap target.
      await tester.tap(find.text('Detail target'));
      // The detail screen has a repeating AnimationController for
      // the heartbeat pulse, so `pumpAndSettle` would never
      // complete. A single `pump` is enough to push the new
      // route onto the navigator and run the first build.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The detail screen has the timer label in its AppBar.
      expect(find.text('Detail target'), findsWidgets);
      // The state pill is visible.
      expect(find.text('Running'), findsOneWidget);

      // Pop the detail screen so its AnimationController is
      // disposed — the `repeat()` controller would otherwise keep
      // the test process alive past this body.
      await tester.pageBack();
      await tester.pump();
    });

    testWidgets('shows exact-alarm permission banner when denied', (
      tester,
    ) async {
      final permissionBridge = _FakePermissionBridge(canSchedule: false);
      addTearDown(permissionBridge.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            alarmBridgeProvider.overrideWithValue(fakeBridge),
            permissionBridgeProvider.overrideWithValue(permissionBridge),
            alarmEventsProvider.overrideWith(
              (ref) => fakeBridge.eventController.stream,
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: TimerScreen())),
        ),
      );
      await pumpUntilData(tester);

      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find.textContaining('exact alarm').evaluate().isNotEmpty) break;
      }
      expect(
        find.textContaining('exact alarm'),
        findsOneWidget,
        reason: 'Timer tab should show the exact-alarm permission banner',
      );
    });

    testWidgets('shows error snackbar when timer schedule is rejected', (
      tester,
    ) async {
      final fakeNotifier = _FakeTimersNotifier()..createShouldSucceed = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            timersProvider.overrideWith(() => fakeNotifier),
            permissionBridgeProvider.overrideWithValue(
              _FakePermissionBridge(),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: TimerScreen())),
        ),
      );
      await pumpUntilData(tester);

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('Could not start the timer'),
        findsOneWidget,
        reason: 'User should be told why the timer could not start',
      );
      expect(
        find.textContaining('Alarms & reminders'),
        findsOneWidget,
        reason: 'Snackbar should name the exact permission to grant',
      );
      // The create screen should still be open so the user can retry.
      expect(find.text('Add Timer'), findsOneWidget);
    });
  });
}
