import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';
import 'package:wakey_alarm/native_bridge/geofence_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/providers/geofence_arming_controller.dart';

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

class _FakeGeofenceBridge extends GeofenceBridge {
  _FakeGeofenceBridge() : super();

  LocationPermissionStatus permissionStatus =
      LocationPermissionStatus.grantedForegroundAndBackground;
  GeoPoint? currentLocation = const GeoPoint(latitude: 0, longitude: 0);
  bool addResult = true;

  List<Map<String, Object?>> addCalls = [];

  @override
  Future<LocationPermissionStatus> getPermissionStatus() async =>
      permissionStatus;

  @override
  Future<GeoPoint?> getCurrentLocation({
    Duration timeout = const Duration(seconds: 10),
  }) async => currentLocation;

  @override
  Future<bool> addGeofence({
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
  }) async {
    addCalls.add({
      'alarmId': alarmId,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
    });
    return addResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late WakeyDatabase database;
  late ProviderContainer container;
  late _FakeAlarmBridge fakeAlarmBridge;
  late _FakeGeofenceBridge fakeGeofenceBridge;
  late String dbPath;

  Alarm createLocationAlarm({
    int? id,
    bool isArmed = false,
    double lat = 51.5074,
    double lon = -0.1278,
    int radius = 2000,
  }) {
    return Alarm(
      id: id,
      label: 'Train stop',
      triggerType: AlarmTriggerType.location,
      latitude: lat,
      longitude: lon,
      radiusMeters: radius,
      isEnabled: true,
      isArmed: isArmed,
      soundUri: '',
      vibrate: true,
      snoozeDurationMin: 10,
      createdAt: '2026-07-20T10:00:00Z',
      updatedAt: '2026-07-20T10:00:00Z',
    );
  }

  setUp(() async {
    fakeAlarmBridge = _FakeAlarmBridge();
    fakeGeofenceBridge = _FakeGeofenceBridge();

    dbPath =
        '${Directory.systemTemp.path}/wakey-test-${DateTime.now().microsecondsSinceEpoch}.db';
    database = WakeyDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: dbPath,
    );
    await database.open();

    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(database),
        alarmBridgeProvider.overrideWithValue(fakeAlarmBridge),
        geofenceBridgeProvider.overrideWithValue(fakeGeofenceBridge),
        alarmEventsProvider.overrideWith(
          (ref) => fakeAlarmBridge.eventController.stream,
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    if (!fakeAlarmBridge.eventController.isClosed) {
      await fakeAlarmBridge.eventController.close();
    }
    final f = File(dbPath);
    if (f.existsSync()) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  });

  group('GeofenceArmingController.armAlarm already-armed guard', () {
    test(
      'returns alreadyArmed and does not call addGeofence when alarm.isArmed',
      () async {
        final dao = container.read(alarmDaoProvider);
        final id = await dao.insert(createLocationAlarm(isArmed: true));
        final armed = (await dao.read(id))!;

        final controller = container.read(geofenceArmingControllerProvider);
        final result = await controller.armAlarm(armed);

        expect(result.outcome, ArmingOutcome.alreadyArmed);
        expect(result.distanceMeters, isNull);
        expect(result.permissionStatus, isNull);
        // The critical assertion: we must NOT have called the native
        // bridge, since the alarm is already armed.
        expect(fakeGeofenceBridge.addCalls, isEmpty);
      },
    );

    test('alreadyArmed is returned even if permission would be missing', () async {
      // The already-armed guard runs before the permission check, so
      // a denied permission cannot be the reason the call returns
      // early when the alarm is already armed.
      fakeGeofenceBridge.permissionStatus = LocationPermissionStatus.denied;
      final dao = container.read(alarmDaoProvider);
      final id = await dao.insert(createLocationAlarm(isArmed: true));
      final armed = (await dao.read(id))!;

      final controller = container.read(geofenceArmingControllerProvider);
      final result = await controller.armAlarm(armed);

      expect(result.outcome, ArmingOutcome.alreadyArmed);
    });
  });

  group('GeofenceArmingController.armAlarm alreadyInside distance', () {
    test('returns the actual distance to the geofence center', () async {
      // Geofence is centered on London. User is at the same
      // coordinates — distance 0, well inside the 2 km radius.
      fakeGeofenceBridge.currentLocation = const GeoPoint(
        latitude: 51.5074,
        longitude: -0.1278,
      );
      final alarm = createLocationAlarm(id: 1, radius: 2000);
      final controller = container.read(geofenceArmingControllerProvider);
      final result = await controller.armAlarm(alarm);

      expect(result.outcome, ArmingOutcome.alreadyInside);
      expect(result.distanceMeters, isNotNull);
      expect(result.distanceMeters!, closeTo(0, 1.0));
      // No native call.
      expect(fakeGeofenceBridge.addCalls, isEmpty);
    });

    test('distance is computed for a non-zero inside point', () async {
      // User is ~111 m north of the geofence center (0.001 deg
      // latitude ≈ 111 m). That's inside the 2 km radius.
      fakeGeofenceBridge.currentLocation = const GeoPoint(
        latitude: 51.5084,
        longitude: -0.1278,
      );
      final alarm = createLocationAlarm(id: 1, radius: 2000);
      final controller = container.read(geofenceArmingControllerProvider);
      final result = await controller.armAlarm(alarm);

      expect(result.outcome, ArmingOutcome.alreadyInside);
      expect(result.distanceMeters, isNotNull);
      expect(result.distanceMeters!, greaterThan(100));
      expect(result.distanceMeters!, lessThan(200));
    });

    test('distance is non-null even at the exact edge of the radius', () {
      // The original implementation always passed `distanceMeters:
      // null` to ArmingResult.alreadyInside, which made the UI
      // unable to tell the user how far they were from the
      // boundary. This regression test ensures the distance is
      // computed even when the user is at the center of a
      // small-but-valid-radius alarm.
      fakeGeofenceBridge.currentLocation = const GeoPoint(
        latitude: 51.5074,
        longitude: -0.1278,
      );
      final alarm = createLocationAlarm(id: 1, radius: 200);
      final controller = container.read(geofenceArmingControllerProvider);
      // We can't await here because armAlarm is async, but the
      // body of the test is sync. Wrap in a future.
      return controller.armAlarm(alarm).then((result) {
        expect(result.outcome, ArmingOutcome.alreadyInside);
        expect(result.distanceMeters, isNotNull);
        expect(result.distanceMeters!, closeTo(0, 1.0));
      });
    });
  });

  group('GeofenceArmingController.armAlarm native call count', () {
    test('only one addGeofence call for a single arming', () async {
      // User is well outside the geofence radius.
      fakeGeofenceBridge.currentLocation = const GeoPoint(
        latitude: 52.4862,
        longitude: -1.8904,
      );
      final dao = container.read(alarmDaoProvider);
      final id = await dao.insert(createLocationAlarm());
      final alarm = (await dao.read(id))!;

      final controller = container.read(geofenceArmingControllerProvider);
      final result = await controller.armAlarm(alarm);

      expect(result.outcome, ArmingOutcome.armed);
      expect(fakeGeofenceBridge.addCalls, hasLength(1));
    });
  });
}
