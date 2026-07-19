import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/screens/edit_alarm_screen.dart';

class MockAlarmsNotifier extends AlarmsNotifier {
  final List<Alarm> savedAlarms = [];

  @override
  Future<List<Alarm>> build() async {
    return savedAlarms;
  }

  @override
  Future<int> insertAlarm(Alarm alarm) async {
    savedAlarms.add(alarm);
    ref.invalidateSelf();
    return 1;
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

class _FakeAlarmBridge implements AlarmBridge {
  String? pickResult;
  String? lastCurrentUri;
  final eventController = StreamController<AlarmEvent>.broadcast();

  @override
  Stream<AlarmEvent>? eventStream;

  @override
  Stream<AlarmEvent> get alarmEvents => eventController.stream;

  @override
  Future<bool> scheduleAlarm(Map<String, Object?> payload) async => true;

  @override
  Future<bool> cancelAlarm(int alarmId) async => true;

  @override
  Future<String?> pickRingtone({String? currentUri}) async {
    lastCurrentUri = currentUri;
    return pickResult;
  }
}

void main() {
  late MockAlarmsNotifier mockNotifier;
  late _FakeAlarmBridge fakeBridge;

  setUp(() {
    mockNotifier = MockAlarmsNotifier();
    fakeBridge = _FakeAlarmBridge();
  });

  Widget createWidgetUnderTest({Alarm? alarm}) {
    return ProviderScope(
      overrides: [
        alarmsNotifierProvider.overrideWith(() => mockNotifier),
        alarmBridgeProvider.overrideWithValue(fakeBridge),
      ],
      child: MaterialApp(home: EditAlarmScreen(alarm: alarm)),
    );
  }

  testWidgets('renders EditAlarmScreen in add mode', (tester) async {
    await tester.pumpWidget(createWidgetUnderTest());

    expect(find.text('Add Alarm'), findsOneWidget);
    expect(find.text('Alarm'), findsOneWidget); // Default label
    expect(find.text('REPEAT'), findsOneWidget);
    expect(find.text('LABEL'), findsOneWidget);
    expect(find.text('SOUND & VIBRATION'), findsOneWidget);
    expect(find.text('SNOOZE'), findsOneWidget);
  });

  testWidgets('renders EditAlarmScreen in edit mode with initialized values', (
    tester,
  ) async {
    final now = DateTime.now().toIso8601String();
    final testAlarm = Alarm(
      id: 42,
      label: 'Get up early',
      triggerType: AlarmTriggerType.time,
      timeHour: 6,
      timeMinute: 30,
      repeatDays: 'MON,WED,FRI',
      isEnabled: true,
      isArmed: false,
      soundUri: 'system://default',
      vibrate: false,
      snoozeDurationMin: 15,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(createWidgetUnderTest(alarm: testAlarm));

    expect(find.text('Edit Alarm'), findsOneWidget);
    expect(find.text('Get up early'), findsOneWidget); // Initialized label
  });

  testWidgets('shows "Default alarm sound" when no custom URI is set', (
    tester,
  ) async {
    await tester.pumpWidget(createWidgetUnderTest());
    expect(find.text('Default alarm sound'), findsOneWidget);
    expect(find.text('Reset'), findsNothing); // No reset for default
  });

  testWidgets('tapping "Change" calls pickRingtone with the current URI', (
    tester,
  ) async {
    final now = DateTime.now().toIso8601String();
    final testAlarm = Alarm(
      id: 1,
      label: 'test',
      triggerType: AlarmTriggerType.time,
      timeHour: 7,
      timeMinute: 0,
      isEnabled: true,
      isArmed: false,
      soundUri: 'content://media/alarms/old',
      vibrate: true,
      snoozeDurationMin: 10,
      createdAt: now,
      updatedAt: now,
    );

    fakeBridge.pickResult = 'content://media/alarms/new';
    await tester.pumpWidget(createWidgetUnderTest(alarm: testAlarm));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    expect(fakeBridge.lastCurrentUri, 'content://media/alarms/old');
    // The UI shows the last 24 characters of the URI prefixed with "...".
    expect(find.textContaining('alarms/new'), findsOneWidget);
    // After a successful pick, the Reset button is visible (custom URI set).
    expect(find.text('Reset'), findsOneWidget);
  });

  testWidgets('tapping "Reset" clears the custom URI back to default', (
    tester,
  ) async {
    final now = DateTime.now().toIso8601String();
    final testAlarm = Alarm(
      id: 1,
      label: 'test',
      triggerType: AlarmTriggerType.time,
      timeHour: 7,
      timeMinute: 0,
      isEnabled: true,
      isArmed: false,
      soundUri: 'content://media/alarms/custom',
      vibrate: true,
      snoozeDurationMin: 10,
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(createWidgetUnderTest(alarm: testAlarm));
    await tester.pumpAndSettle();

    expect(find.text('Reset'), findsOneWidget);

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(find.text('Default alarm sound'), findsOneWidget);
    expect(find.text('Reset'), findsNothing);
  });
}
