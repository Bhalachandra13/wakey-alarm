import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';
import 'package:wakey_alarm/native_bridge/permission_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/screens/alarms_screen.dart';

void main() {
  group('Alarm toggle error feedback', () {
    testWidgets('shows error snackbar when toggleEnabled returns false '
        '(e.g. SCHEDULE_EXACT_ALARM denied)', (tester) async {
      final bridge = _FakeAlarmBridge();
      final permissionBridge = _FakePermissionBridge(canSchedule: true);
      addTearDown(bridge.dispose);
      addTearDown(permissionBridge.dispose);
      final alarm = _createTimeAlarm(id: 1, isEnabled: false);
      final notifier = _FailingToggleAlarmsNotifier([alarm], toggleReturns: false);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            alarmBridgeProvider.overrideWithValue(bridge),
            permissionBridgeProvider.overrideWithValue(permissionBridge),
            alarmEventsProvider.overrideWith(
              (ref) => bridge.eventController.stream,
            ),
            alarmsNotifierProvider.overrideWith(() => notifier),
          ],
          child: const MaterialApp(home: Scaffold(body: AlarmsScreen())),
        ),
      );
      await _pumpUntilReady(tester);

      // Toggle the switch ON — toggleEnabled will return false.
      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('Could not schedule'),
        findsOneWidget,
        reason: 'Snackbar should tell the user why the alarm could not arm',
      );
      expect(
        find.textContaining('Alarms & reminders'),
        findsOneWidget,
        reason: 'Snackbar should name the exact permission to grant',
      );
      expect(
        notifier.toggleCallCount,
        1,
        reason: 'toggleEnabled should have been invoked once',
      );
    });

    testWidgets('does not show error snackbar when toggleEnabled succeeds', (
      tester,
    ) async {
      final bridge = _FakeAlarmBridge();
      final permissionBridge = _FakePermissionBridge(canSchedule: true);
      addTearDown(bridge.dispose);
      addTearDown(permissionBridge.dispose);
      final alarm = _createTimeAlarm(id: 1, isEnabled: false);
      final notifier = _FailingToggleAlarmsNotifier([alarm], toggleReturns: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            alarmBridgeProvider.overrideWithValue(bridge),
            permissionBridgeProvider.overrideWithValue(permissionBridge),
            alarmEventsProvider.overrideWith(
              (ref) => bridge.eventController.stream,
            ),
            alarmsNotifierProvider.overrideWith(() => notifier),
          ],
          child: const MaterialApp(home: Scaffold(body: AlarmsScreen())),
        ),
      );
      await _pumpUntilReady(tester);

      await tester.tap(find.byType(Switch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.textContaining('Could not schedule'),
        findsNothing,
        reason: 'No snackbar when toggle succeeded',
      );
    });
  });
}

Future<void> _pumpUntilReady(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(Switch).evaluate().isNotEmpty) return;
  }
}

Alarm _createTimeAlarm({required int id, required bool isEnabled}) {
  final now = DateTime.now().toIso8601String();
  return Alarm(
    id: id,
    label: 'Morning',
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

/// A test-double notifier that returns a fixed value from
/// [toggleEnabled] without touching the database or the native
/// bridge. Lets the test focus purely on the UI's reaction to the
/// success/failure return value.
class _FailingToggleAlarmsNotifier extends AlarmsNotifier {
  _FailingToggleAlarmsNotifier(this._alarms, {required this.toggleReturns});

  final List<Alarm> _alarms;
  final bool toggleReturns;
  int toggleCallCount = 0;

  @override
  Future<List<Alarm>> build() async => _alarms;

  @override
  Future<bool> toggleEnabled(int id, bool newState) async {
    toggleCallCount++;
    return toggleReturns;
  }
}

class _FakeAlarmBridge implements AlarmBridge {
  _FakeAlarmBridge()
    : eventController = StreamController<AlarmEvent>.broadcast();
  final StreamController<AlarmEvent> eventController;
  void dispose() => eventController.close();
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

class _FakePermissionBridge implements PermissionBridge {
  _FakePermissionBridge({required this.canSchedule});

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
