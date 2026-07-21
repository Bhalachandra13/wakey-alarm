import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/screens/edit_alarm_screen.dart';

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

class _MockAlarmsNotifier extends AlarmsNotifier {
  final List<Alarm> savedAlarms = [];
  int _nextId = 1;

  @override
  Future<List<Alarm>> build() async {
    return savedAlarms;
  }

  @override
  Future<int> insertAlarm(Alarm alarm) async {
    final id = _nextId++;
    savedAlarms.add(alarm.copyWith(id: id));
    ref.invalidateSelf();
    return id;
  }

  @override
  Future<void> updateAlarm(Alarm alarm) async {
    final index = savedAlarms.indexWhere((a) => a.id == alarm.id);
    if (index != -1) {
      savedAlarms[index] = alarm;
    }
    ref.invalidateSelf();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late WakeyDatabase database;
  late _FakeAlarmBridge fakeBridge;
  late _MockAlarmsNotifier mockNotifier;

  setUp(() async {
    fakeBridge = _FakeAlarmBridge();
    addTearDown(fakeBridge.eventController.close);

    mockNotifier = _MockAlarmsNotifier();
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
        alarmsNotifierProvider.overrideWith(() => mockNotifier),
      ],
      child: const MaterialApp(home: EditAlarmScreen()),
    );
  }

  group('EditAlarmScreen with location trigger', () {
    testWidgets('default mode shows time-based UI', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      // The default is TIME. The exact label depends on locale
      // (12-hour vs 24-hour), but the literal "Tap to change time"
      // hint is locale-independent.
      expect(find.text('Tap to change time'), findsOneWidget);
      expect(find.text('REPEAT'), findsOneWidget);
      // The TRIGGER segment is shown.
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Location'), findsOneWidget);
    });

    testWidgets('switching to location reveals map picker section', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      // The Location segment in the trigger selector.
      await tester.tap(find.text('Location'));
      await tester.pumpAndSettle();

      // The time-based UI is hidden.
      expect(find.text('Tap to change time'), findsNothing);
      // The location UI is shown.
      expect(find.text('No location picked yet'), findsOneWidget);
      expect(find.text('Pick on map'), findsOneWidget);
      // REPEAT is hidden for location alarms (they're one-shot).
      expect(find.text('REPEAT'), findsNothing);
      // The radius slider is disabled until a location is picked.
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNull);
    });

    testWidgets('shows validation error when saving without a location', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      // Switch to location.
      await tester.tap(find.text('Location'));
      await tester.pumpAndSettle();

      // Try to save via the AppBar check icon button. The bottom
      // Save button can sit off-screen on the 800x600 test
      // surface, so use the AppBar action.
      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pump();

      // The SnackBar should appear.
      expect(find.text('Pick a location first'), findsOneWidget);
    });

    testWidgets('editing an existing location alarm pre-fills the form', (
      tester,
    ) async {
      const existing = Alarm(
        id: 1,
        label: 'Train stop',
        triggerType: AlarmTriggerType.location,
        latitude: 51.5074,
        longitude: -0.1278,
        radiusMeters: 5000,
        isEnabled: true,
        isArmed: false,
        soundUri: '',
        vibrate: true,
        snoozeDurationMin: 10,
        createdAt: '2026-07-20T10:00:00Z',
        updatedAt: '2026-07-20T10:00:00Z',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            alarmBridgeProvider.overrideWithValue(fakeBridge),
            alarmEventsProvider.overrideWith(
              (ref) => fakeBridge.eventController.stream,
            ),
            alarmsNotifierProvider.overrideWith(() => mockNotifier),
          ],
          child: const MaterialApp(home: EditAlarmScreen(alarm: existing)),
        ),
      );
      await tester.pumpAndSettle();

      // Title is "Edit Alarm" (not "Add Alarm").
      expect(find.text('Edit Alarm'), findsOneWidget);
      // Label is pre-filled.
      expect(find.text('Train stop'), findsOneWidget);
      // Location is shown with lat/long.
      expect(find.textContaining('51.50740'), findsOneWidget);
      expect(find.textContaining('-0.12780'), findsOneWidget);
      // The radius is 5 km (formatted without decimal for whole
      // kilometers).
      expect(find.text('5 km'), findsOneWidget);
    });
  });
}
