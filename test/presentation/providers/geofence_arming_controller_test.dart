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
  String addError = 'simulated failure';
  int? addErrorCode;
  bool removeResult = true;
  bool batteryExempt = true;

  List<Map<String, Object?>> addCalls = [];
  List<int> removeCalls = [];

  @override
  Future<LocationPermissionStatus> getPermissionStatus() async =>
      permissionStatus;

  @override
  Future<LocationPermissionStatus> requestForegroundLocation() async =>
      permissionStatus;

  @override
  Future<LocationPermissionStatus> requestBackgroundLocation() async =>
      permissionStatus;

  @override
  Future<GeoPoint?> getCurrentLocation({
    Duration timeout = const Duration(seconds: 10),
  }) async => currentLocation;

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
  }) async {
    addCalls.add({
      'alarmId': alarmId,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
      'expirationMillis': expirationMillis,
      'label': label,
      'soundUri': soundUri,
      'vibrate': vibrate,
      'snoozeDurationMin': snoozeDurationMin,
      'maxSnoozeCount': maxSnoozeCount,
    });
    if (addResult) {
      return const GeofenceResult.ok();
    }
    return GeofenceResult.failed(error: addError, code: addErrorCode);
  }

  @override
  Future<GeofenceResult> removeGeofence(int alarmId) async {
    removeCalls.add(alarmId);
    return removeResult
        ? const GeofenceResult.ok()
        : GeofenceResult.failed(error: 'simulated remove failure');
  }

  @override
  Future<bool> isBatteryOptimizationExempt() async => batteryExempt;
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
      isArmed: false,
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
    // Order matters: dispose the container first so any Riverpod
    // listeners holding a stream subscription tear down before
    // we close the underlying stream controller.
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

  group('GeofenceArmingController.armAlarm', () {
    test('arms a valid location alarm with all checks passing', () async {
      // Pre-warm the alarms notifier.
      await container.read(alarmsNotifierProvider.future);

      // Set the user's location to a known point *outside* the
      // geofence radius (geofence is at London, point is in
      // Birmingham ~160 km away).
      fakeGeofenceBridge.currentLocation = const GeoPoint(
        latitude: 52.4862,
        longitude: -1.8904,
      );

      final dao = container.read(alarmDaoProvider);
      final id = await dao.insert(createLocationAlarm());

      final controller = container.read(geofenceArmingControllerProvider);
      final result = await controller.armAlarm((await dao.read(id))!);

      expect(result.outcome, ArmingOutcome.armed);
      expect(fakeGeofenceBridge.addCalls, hasLength(1));
      final call = fakeGeofenceBridge.addCalls.single;
      expect(call['alarmId'], id);
      expect(call['radiusMeters'], 2000);

      // The DB row should now have is_armed=true.
      final updated = await dao.read(id);
      expect(updated!.isArmed, isTrue);
    });

    test('passes alarm metadata to the geofence bridge for native persistence', () async {
      await container.read(alarmsNotifierProvider.future);
      fakeGeofenceBridge.currentLocation = const GeoPoint(
        latitude: 52.4862,
        longitude: -1.8904,
      );

      final dao = container.read(alarmDaoProvider);
      final id = await dao.insert(
        createLocationAlarm().copyWith(
          label: 'Train stop',
          soundUri: 'content://media/alarms/train',
          vibrate: false,
          snoozeDurationMin: 7,
          maxSnoozeCount: 3,
        ),
      );

      final controller = container.read(geofenceArmingControllerProvider);
      final result = await controller.armAlarm((await dao.read(id))!);

      expect(result.outcome, ArmingOutcome.armed);
      final call = fakeGeofenceBridge.addCalls.single;
      expect(call['label'], 'Train stop');
      expect(call['soundUri'], 'content://media/alarms/train');
      expect(call['vibrate'], isFalse);
      expect(call['snoozeDurationMin'], 7);
      expect(call['maxSnoozeCount'], 3);
    });

    test('returns invalidAlarm for a time-based alarm', () async {
      final timeAlarm = Alarm(
        label: 'Wake up',
        triggerType: AlarmTriggerType.time,
        timeHour: 7,
        timeMinute: 0,
        isEnabled: true,
        isArmed: false,
        soundUri: '',
        vibrate: true,
        snoozeDurationMin: 10,
        createdAt: '2026-07-20T10:00:00Z',
        updatedAt: '2026-07-20T10:00:00Z',
      );
      final controller = container.read(geofenceArmingControllerProvider);
      final result = await controller.armAlarm(timeAlarm);
      expect(result.outcome, ArmingOutcome.invalidAlarm);
    });

    test('returns invalidAlarm for a location alarm with bad radius', () async {
      final alarm = createLocationAlarm(radius: 50); // below 200 m
      final controller = container.read(geofenceArmingControllerProvider);
      final result = await controller.armAlarm(alarm);
      expect(result.outcome, ArmingOutcome.invalidAlarm);
    });

    test('returns permissionMissing when location is denied', () async {
      fakeGeofenceBridge.permissionStatus = LocationPermissionStatus.denied;
      final alarm = createLocationAlarm(id: 1);
      final controller = container.read(geofenceArmingControllerProvider);
      final result = await controller.armAlarm(alarm);
      expect(result.outcome, ArmingOutcome.permissionMissing);
      expect(result.permissionStatus, LocationPermissionStatus.denied);
    });

    test('returns permissionMissing for foreground-only permission', () async {
      fakeGeofenceBridge.permissionStatus =
          LocationPermissionStatus.grantedForegroundOnly;
      final alarm = createLocationAlarm(id: 1);
      final controller = container.read(geofenceArmingControllerProvider);
      final result = await controller.armAlarm(alarm);
      expect(result.outcome, ArmingOutcome.permissionMissing);
    });

    test('returns alreadyInside when user is inside the radius', () async {
      // User is *at* the geofence center, well inside the radius.
      fakeGeofenceBridge.currentLocation = const GeoPoint(
        latitude: 51.5074,
        longitude: -0.1278,
      );
      final alarm = createLocationAlarm(id: 1);
      final controller = container.read(geofenceArmingControllerProvider);
      final result = await controller.armAlarm(alarm);
      expect(result.outcome, ArmingOutcome.alreadyInside);
      // No native call should have been made.
      expect(fakeGeofenceBridge.addCalls, isEmpty);
    });

    test('returns registrationFailed when addGeofence fails', () async {
      fakeGeofenceBridge.addResult = false;
      fakeGeofenceBridge.addError = 'Location services are off';
      fakeGeofenceBridge.addErrorCode = 1004;
      fakeGeofenceBridge.currentLocation = const GeoPoint(
        latitude: 52.4862,
        longitude: -1.8904,
      );
      final alarm = createLocationAlarm(id: 1);
      final controller = container.read(geofenceArmingControllerProvider);
      final result = await controller.armAlarm(alarm);
      expect(result.outcome, ArmingOutcome.registrationFailed);
      // The native error string should be propagated so the UI
      // can tell the user *why* the geofence could not be armed.
      expect(result.message, 'Location services are off');
    });

    test('arms even when getCurrentLocation returns null (fallback)', () async {
      fakeGeofenceBridge.currentLocation = null;
      final alarm = createLocationAlarm(id: 1);
      final controller = container.read(geofenceArmingControllerProvider);
      final result = await controller.armAlarm(alarm);
      // Without a location we skip the "already inside" check and
      // arm directly. The user might be inside, but if location
      // is unavailable the choice is between "don't arm" and
      // "arm and let the user discover the issue empirically".
      // The latter is the friendlier UX.
      expect(result.outcome, ArmingOutcome.armed);
      expect(fakeGeofenceBridge.addCalls, hasLength(1));
    });
  });

  group('GeofenceArmingController.disarmAlarm', () {
    test('removes the native geofence and flips is_armed to false', () async {
      // Pre-warm.
      await container.read(alarmsNotifierProvider.future);

      final dao = container.read(alarmDaoProvider);
      final id = await dao.insert(createLocationAlarm());
      await dao.updateArmed(id, true);
      final armed = (await dao.read(id))!;

      final controller = container.read(geofenceArmingControllerProvider);
      final ok = await controller.disarmAlarm(armed);
      expect(ok, isTrue);
      expect(fakeGeofenceBridge.removeCalls, [id]);
      final updated = await dao.read(id);
      expect(updated!.isArmed, isFalse);
    });

    test('returns false for a time-based alarm', () async {
      final timeAlarm = Alarm(
        label: 'Wake up',
        triggerType: AlarmTriggerType.time,
        timeHour: 7,
        timeMinute: 0,
        isEnabled: true,
        isArmed: false,
        soundUri: '',
        vibrate: true,
        snoozeDurationMin: 10,
        createdAt: '2026-07-20T10:00:00Z',
        updatedAt: '2026-07-20T10:00:00Z',
      );
      final controller = container.read(geofenceArmingControllerProvider);
      expect(await controller.disarmAlarm(timeAlarm), isFalse);
    });
  });
}
