import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/domain/alarm.dart';
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

void main() {
  late MockAlarmsNotifier mockNotifier;

  setUp(() {
    mockNotifier = MockAlarmsNotifier();
  });

  Widget createWidgetUnderTest({Alarm? alarm}) {
    return ProviderScope(
      overrides: [
        alarmsNotifierProvider.overrideWith(() => mockNotifier),
      ],
      child: MaterialApp(
        home: EditAlarmScreen(alarm: alarm),
      ),
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

  testWidgets('renders EditAlarmScreen in edit mode with initialized values', (tester) async {
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
}
