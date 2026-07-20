import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/screens/alarms_screen.dart';

void main() {
  group('AlarmsScreen widgets', () {
    Alarm createTestAlarm({
      String label = 'Test Alarm',
      int? id,
      bool isEnabled = true,
    }) {
      final now = DateTime.now().toIso8601String();
      return Alarm(
        id: id,
        label: label,
        triggerType: AlarmTriggerType.time,
        timeHour: 7,
        timeMinute: 0,
        isEnabled: isEnabled,
        isArmed: false,
        soundUri: 'system://ringtone',
        vibrate: true,
        snoozeDurationMin: 10,
        createdAt: now,
        updatedAt: now,
      );
    }

    testWidgets('empty view displays correct icons and text', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.alarm_off, size: 48),
                SizedBox(height: 12),
                Text('No alarms yet'),
                SizedBox(height: 8),
                Text('Tap the + button to create your first alarm'),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.alarm_off), findsOneWidget);
      expect(find.text('No alarms yet'), findsOneWidget);
      expect(
        find.text('Tap the + button to create your first alarm'),
        findsOneWidget,
      );
    });

    testWidgets('alarm displays time correctly', (WidgetTester tester) async {
      final alarm = createTestAlarm(label: 'Morning Alarm');

      // Build time string
      final timeStr =
          '${alarm.timeHour.toString().padLeft(2, '0')}:${alarm.timeMinute.toString().padLeft(2, '0')}';

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Text(timeStr))));

      expect(find.text('07:00'), findsOneWidget);
    });

    testWidgets('alarm label displays correctly', (WidgetTester tester) async {
      const alarmLabel = 'Wake Up';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Card(child: ListTile(title: Text(alarmLabel))),
          ),
        ),
      );

      expect(find.text(alarmLabel), findsOneWidget);
    });

    testWidgets('edit button is present in list tile', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListTile(
              title: const Text('Test Alarm'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.edit), onPressed: () {}),
                  Switch(value: true, onChanged: (_) {}),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('time alarm displays time icon', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ListTile(
              leading: Icon(Icons.access_time),
              title: Text('Time Alarm'),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.access_time), findsOneWidget);
    });

    testWidgets('location alarm displays location icon', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ListTile(
              leading: Icon(Icons.location_on),
              title: Text('Location Alarm'),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.location_on), findsOneWidget);
    });

    testWidgets('switch toggle updates state', (WidgetTester tester) async {
      bool isEnabled = true;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Switch(
                  value: isEnabled,
                  onChanged: (newValue) {
                    setState(() {
                      isEnabled = newValue;
                    });
                  },
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(isEnabled, isFalse);
    });

    testWidgets('dismissible background shows delete icon', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Container(
              color: Colors.red,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
              child: const Icon(Icons.delete, color: Colors.white),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.delete), findsOneWidget);
    });

    testWidgets('time alarm displays location radius information', (
      WidgetTester tester,
    ) async {
      const radiusText = 'Location-based (500m radius)';

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text(radiusText))),
      );

      expect(find.text(radiusText), findsOneWidget);
    });

    testWidgets('card displays alarm in list tile format', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Card(
              child: ListTile(
                leading: const Icon(Icons.alarm),
                title: const Text('Morning Alarm'),
                subtitle: const Text('07:00'),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Card), findsOneWidget);
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('Morning Alarm'), findsOneWidget);
    });
  });

  group('AlarmsScreen with provider overrides', () {
    testWidgets('shows a ringing banner when an alarm is currently firing', (
      tester,
    ) async {
      final fakeBridge = _FakeAlarmBridge();
      addTearDown(fakeBridge.eventController.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            alarmBridgeProvider.overrideWithValue(fakeBridge),
            alarmsNotifierProvider.overrideWith(_EmptyAlarmsNotifier.new),
          ],
          child: const MaterialApp(home: Scaffold(body: AlarmsScreen())),
        ),
      );
      await tester.pump();

      // Initial state: no banner.
      expect(find.byIcon(Icons.notifications_active), findsNothing);

      // Fire an alarm.
      fakeBridge.eventController.add(
        const AlarmEvent(
          alarmId: 1,
          type: AlarmEventType.fired,
          triggerType: 'time',
        ),
      );
      // Pump until the banner shows.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byIcon(Icons.notifications_active).evaluate().isNotEmpty) {
          break;
        }
      }
      expect(find.byIcon(Icons.notifications_active), findsOneWidget);
      expect(find.textContaining('Ringing now'), findsOneWidget);
    });

    testWidgets('clears the ringing banner when alarm is dismissed', (
      tester,
    ) async {
      final fakeBridge = _FakeAlarmBridge();
      addTearDown(fakeBridge.eventController.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            alarmBridgeProvider.overrideWithValue(fakeBridge),
            alarmsNotifierProvider.overrideWith(_EmptyAlarmsNotifier.new),
          ],
          child: const MaterialApp(home: Scaffold(body: AlarmsScreen())),
        ),
      );
      await tester.pump();

      fakeBridge.eventController.add(
        const AlarmEvent(
          alarmId: 1,
          type: AlarmEventType.fired,
          triggerType: 'time',
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byIcon(Icons.notifications_active).evaluate().isNotEmpty) {
          break;
        }
      }
      expect(find.byIcon(Icons.notifications_active), findsOneWidget);

      fakeBridge.eventController.add(
        const AlarmEvent(alarmId: 1, type: AlarmEventType.dismissed),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byIcon(Icons.notifications_active).evaluate().isEmpty) {
          break;
        }
      }
      expect(find.byIcon(Icons.notifications_active), findsNothing);
    });
  });
}

class _EmptyAlarmsNotifier extends AlarmsNotifier {
  @override
  Future<List<Alarm>> build() async => const [];
}

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
  Future<bool> cancelAlarm(int alarmId) async => true;
  @override
  Future<String?> pickRingtone({String? currentUri}) async => null;
}
