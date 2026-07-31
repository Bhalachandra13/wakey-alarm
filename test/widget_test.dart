import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/domain/timer_record.dart';
import 'package:wakey_alarm/native_bridge/permission_bridge.dart';
import 'package:wakey_alarm/presentation/app.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/providers/timers_provider.dart';

class MockAlarmsNotifier extends AlarmsNotifier {
  @override
  Future<List<Alarm>> build() async {
    return const [];
  }
}

class MockTimersNotifier extends TimersNotifier {
  @override
  Future<List<TimerRecord>> build() async {
    return const [];
  }
}

class _FakePermissionBridge implements PermissionBridge {
  @override
  Future<bool> canScheduleExactAlarms() async => true;

  @override
  Future<bool> requestExactAlarmPermission() async => true;

  @override
  Future<NativePermissionStatus> getNotificationPermissionStatus() async =>
      NativePermissionStatus.granted;

  @override
  Future<NativePermissionStatus> requestNotificationPermission() async =>
      NativePermissionStatus.granted;
}

void main() {
  testWidgets('app shell renders primary tabs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          alarmsNotifierProvider.overrideWith(() => MockAlarmsNotifier()),
          timersProvider.overrideWith(() => MockTimersNotifier()),
          permissionBridgeProvider.overrideWithValue(_FakePermissionBridge()),
        ],
        child: const WakeyAlarmApp(),
      ),
    );

    expect(find.text('Alarms'), findsWidgets);
    expect(find.text('Stopwatch'), findsOneWidget);
    expect(find.text('Timer'), findsOneWidget);

    // AlarmsScreen shows empty state immediately as build completes sync/mocked
    await tester.pumpAndSettle();
    expect(
      find.text('No alarms yet'),
      findsOneWidget,
      reason: 'Alarms screen should display empty state',
    );

    await tester.tap(find.text('Timer'));
    await tester.pumpAndSettle();

    expect(find.text('No timers yet'), findsOneWidget);
  });
}
