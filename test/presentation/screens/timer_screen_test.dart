import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/providers/timers_provider.dart';
import 'package:wakey_alarm/presentation/screens/timer_screen.dart';

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

  Widget wrap() {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        alarmBridgeProvider.overrideWithValue(fakeBridge),
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
  });
}
