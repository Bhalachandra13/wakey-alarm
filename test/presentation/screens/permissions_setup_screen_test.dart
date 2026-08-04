import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';
import 'package:wakey_alarm/native_bridge/geofence_bridge.dart';
import 'package:wakey_alarm/native_bridge/permission_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/screens/permissions_setup_screen.dart';

class _FakePermissionBridge implements PermissionBridge {
  _FakePermissionBridge({
    this.notif = NativePermissionStatus.granted,
    this.exact = true,
  });
  NativePermissionStatus notif;
  bool exact;
  @override
  Future<NativePermissionStatus> getNotificationPermissionStatus() async =>
      notif;
  @override
  Future<NativePermissionStatus> requestNotificationPermission() async {
    notif = NativePermissionStatus.granted;
    return notif;
  }

  @override
  Future<bool> canScheduleExactAlarms() async => exact;
  @override
  Future<bool> requestExactAlarmPermission() async {
    exact = true;
    return true;
  }
}

class _FakeGeofenceBridge implements GeofenceBridge {
  _FakeGeofenceBridge();
  LocationPermissionStatus location =
      LocationPermissionStatus.grantedForegroundAndBackground;
  bool battery = true;
  @override
  Future<LocationPermissionStatus> getPermissionStatus() async => location;
  @override
  Future<LocationPermissionStatus> requestForegroundLocation() async {
    location = LocationPermissionStatus.grantedForegroundAndBackground;
    return location;
  }

  @override
  Future<LocationPermissionStatus> requestBackgroundLocation() async {
    location = LocationPermissionStatus.grantedForegroundAndBackground;
    return location;
  }

  @override
  Future<GeoPoint?> getCurrentLocation({
    Duration timeout = const Duration(seconds: 10),
  }) async => null;
  @override
  Future<GeofenceResult> addGeofence({
    required int alarmId,
    required double latitude,
    required double longitude,
    required int radiusMeters,
    int expirationMillis = -1,
    String label = 'Alarm',
    String soundUri = '',
    bool vibrate = true,
    int snoozeDurationMin = 10,
    int maxSnoozeCount = -1,
  }) async => const GeofenceResult.ok();
  @override
  Future<GeofenceResult> removeGeofence(int alarmId) async =>
      const GeofenceResult.ok();
  @override
  Future<bool> isBatteryOptimizationExempt() async => battery;
  @override
  Future<bool> requestBatteryOptimizationExemption() async {
    battery = true;
    return true;
  }
}

class _FakeAlarmBridge implements AlarmBridge {
  @override
  Stream<AlarmEvent>? eventStream;
  @override
  Stream<AlarmEvent> get alarmEvents => const Stream<AlarmEvent>.empty();
  @override
  Future<bool> scheduleAlarm(Map<String, Object?> payload) async => true;
  @override
  Future<bool> scheduleTimer(Map<String, Object?> payload) async => true;
  @override
  Future<bool> cancelAlarm(int alarmId) async => true;
  @override
  Future<String?> pickRingtone({String? currentUri}) async => null;
}

class _EmptyAlarmsNotifier extends AlarmsNotifier {
  @override
  Future<List<Alarm>> build() async => const <Alarm>[];
}

class _LocationAlarmsNotifier extends AlarmsNotifier {
  @override
  Future<List<Alarm>> build() async => const <Alarm>[
    Alarm(
      id: 1,
      label: 'Get off at airport',
      triggerType: AlarmTriggerType.location,
      latitude: 12.34,
      longitude: 56.78,
      radiusMeters: 1000,
      isEnabled: true,
      isArmed: false,
      soundUri: '',
      vibrate: true,
      snoozeDurationMin: 5,
      createdAt: '2026-08-03T00:00:00Z',
      updatedAt: '2026-08-03T00:00:00Z',
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  late _FakePermissionBridge perm;
  late _FakeGeofenceBridge geo;
  late _FakeAlarmBridge alarm;

  setUp(() {
    perm = _FakePermissionBridge();
    geo = _FakeGeofenceBridge();
    alarm = _FakeAlarmBridge();
  });

  Widget wrap() {
    return ProviderScope(
      overrides: [
        permissionBridgeProvider.overrideWithValue(perm),
        geofenceBridgeProvider.overrideWithValue(geo),
        alarmBridgeProvider.overrideWithValue(alarm),
        alarmsNotifierProvider.overrideWith(_EmptyAlarmsNotifier.new),
      ],
      child: const MaterialApp(home: PermissionsSetupScreen()),
    );
  }

  group('PermissionsSetupScreen', () {
    testWidgets('renders the checklist and the Set up button', (tester) async {
      // Make exact alarm un-granted so the Set up button is
      // visible (otherwise the all-set card replaces it).
      perm.exact = false;
      await tester.pumpWidget(wrap());
      // sqflite_ffi isn't involved here, but the bridge reads
      // are real-time; hop out of fake-async to let the initial
      // status checks complete.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('Get ready'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Exact alarms'), findsOneWidget);
      expect(find.text('Precise location, all the time'), findsOneWidget);
      expect(find.text('Battery optimisation'), findsOneWidget);
      expect(
        find.byKey(const Key('permissionsSetupRunButton')),
        findsOneWidget,
      );
    });

    testWidgets(
      'shows All set! card when every required permission is granted',
      (tester) async {
        // Everything granted → the screen should show the
        // "All set!" card instead of the Set up button.
        perm = _FakePermissionBridge();
        geo = _FakeGeofenceBridge();
        await tester.pumpWidget(wrap());
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
        expect(find.byKey(const Key('permissionsSetupAllSet')), findsOneWidget);
        expect(
          find.byKey(const Key('permissionsSetupDoneButton')),
          findsOneWidget,
        );
        // The Set up button is absent in the all-good state.
        expect(
          find.byKey(const Key('permissionsSetupRunButton')),
          findsNothing,
        );
      },
    );

    testWidgets('Set up button runs the flow and surfaces the all-set state', (
      tester,
    ) async {
      // Start with notif denied + exact denied, so the flow
      // has work to do. Location + battery are already good
      // (and location isn't required — no LOCATION alarms).
      perm = _FakePermissionBridge(
        notif: NativePermissionStatus.denied,
        exact: false,
      );
      geo = _FakeGeofenceBridge();
      await tester.pumpWidget(wrap());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      // The Set up button is visible because notif + exact are
      // missing.
      expect(
        find.byKey(const Key('permissionsSetupRunButton')),
        findsOneWidget,
      );
      // Tap Set up and pump until the flow settles. The flow
      // grants both permissions, the checklist updates, and
      // the All set! card appears. The location step is gated
      // by a "one quick heads-up" AlertDialog that the test
      // needs to dismiss before the foreground request fires.
      await tester.tap(find.byKey(const Key('permissionsSetupRunButton')));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      // The location step is not required here (no LOCATION
      // alarms in the fake list), so the heads-up dialog
      // does not appear; the All set! card is shown directly.
      expect(find.byKey(const Key('permissionsSetupAllSet')), findsOneWidget);
      // The fake bridges recorded the requests.
      expect(perm.notif, NativePermissionStatus.granted);
      expect(perm.exact, isTrue);
    });

    testWidgets(
      'shows the pre-foreground heads-up dialog when a LOCATION alarm '
      'is set and location is denied',
      (tester) async {
        // Override the alarms notifier with one that has a
        // LOCATION alarm, so the location step is required.
        // Foreground location is denied so the flow has to
        // surface the heads-up dialog before the system dialog.
        perm = _FakePermissionBridge(
          notif: NativePermissionStatus.granted,
          exact: true,
        );
        geo = _FakeGeofenceBridge()..location = LocationPermissionStatus.denied;

        Widget wrapWithLocationAlarm() {
          return ProviderScope(
            overrides: [
              permissionBridgeProvider.overrideWithValue(perm),
              geofenceBridgeProvider.overrideWithValue(geo),
              alarmBridgeProvider.overrideWithValue(alarm),
              alarmsNotifierProvider.overrideWith(
                _LocationAlarmsNotifier.new,
              ),
            ],
            child: const MaterialApp(home: PermissionsSetupScreen()),
          );
        }

        await tester.pumpWidget(wrapWithLocationAlarm());
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();

        // Tap "Set up". The flow should immediately surface the
        // heads-up dialog (before calling requestForegroundLocation).
        await tester.tap(find.byKey(const Key('permissionsSetupRunButton')));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();

        // The heads-up dialog is on screen and its key copy is present.
        expect(
          find.byKey(const Key('locationForegroundHeadsUp')),
          findsOneWidget,
        );
        expect(
          find.text('One quick heads-up'),
          findsOneWidget,
        );
        // The dialog names the wrong choice explicitly so the
        // user knows what NOT to pick in the next screen.
        expect(
          find.textContaining('"While using the app" is not enough'),
          findsOneWidget,
        );
        // Dismissing the dialog should advance the flow.
        await tester.tap(
          find.byKey(const Key('locationForegroundHeadsUpOk')),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
        // The fake bridge records the request; the dialog is gone.
        expect(geo.location, LocationPermissionStatus.grantedForegroundAndBackground);
        expect(
          find.byKey(const Key('locationForegroundHeadsUp')),
          findsNothing,
        );
      },
    );
  });
}
