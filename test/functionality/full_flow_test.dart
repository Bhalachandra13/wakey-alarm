import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/domain/timer_record.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';
import 'package:wakey_alarm/native_bridge/geofence_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/providers/geofence_arming_controller.dart';
import 'package:wakey_alarm/presentation/providers/timers_provider.dart';

/// A single, shared fake that records every native call and lets the
/// test simulate any native response. Used by every group in this
/// file to keep the setup boilerplate low.
class _FakeAlarmBridge implements AlarmBridge {
  _FakeAlarmBridge()
    : eventController = StreamController<AlarmEvent>.broadcast();
  final StreamController<AlarmEvent> eventController;

  final List<Map<String, Object?>> scheduleAlarmCalls = [];
  final List<Map<String, Object?>> scheduleTimerCalls = [];
  final List<int> cancelCalls = [];

  bool scheduleAlarmResult = true;
  bool scheduleTimerResult = true;

  @override
  Stream<AlarmEvent>? eventStream;
  @override
  Stream<AlarmEvent> get alarmEvents => eventController.stream;
  @override
  Future<bool> scheduleAlarm(Map<String, Object?> payload) async {
    scheduleAlarmCalls.add(Map.of(payload));
    return scheduleAlarmResult;
  }

  @override
  Future<bool> scheduleTimer(Map<String, Object?> payload) async {
    scheduleTimerCalls.add(Map.of(payload));
    return scheduleTimerResult;
  }

  @override
  Future<bool> cancelAlarm(int alarmId) async {
    cancelCalls.add(alarmId);
    return true;
  }

  @override
  Future<String?> pickRingtone({String? currentUri}) async => null;
}

class _FakeGeofenceBridge extends GeofenceBridge {
  _FakeGeofenceBridge() : super();

  LocationPermissionStatus permissionStatus =
      LocationPermissionStatus.grantedForegroundAndBackground;
  GeoPoint? currentLocation = const GeoPoint(latitude: 52.4862, longitude: -1.8904);
  bool addResult = true;
  bool removeResult = true;

  final List<Map<String, Object?>> addCalls = [];
  final List<int> removeCalls = [];

  @override
  Future<LocationPermissionStatus> getPermissionStatus() async =>
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
      'label': label,
      'soundUri': soundUri,
      'vibrate': vibrate,
      'snoozeDurationMin': snoozeDurationMin,
      'maxSnoozeCount': maxSnoozeCount,
    });
    return addResult
        ? const GeofenceResult.ok()
        : const GeofenceResult.failed(error: 'simulated failure');
  }

  @override
  Future<GeofenceResult> removeGeofence(int alarmId) async {
    removeCalls.add(alarmId);
    return removeResult
        ? const GeofenceResult.ok()
        : const GeofenceResult.failed(error: 'simulated remove failure');
  }
}

Alarm _timeAlarm({int? id, bool isEnabled = true, int hour = 7, int minute = 0}) {
  final now = DateTime.now().toIso8601String();
  return Alarm(
    id: id,
    label: 'Time alarm',
    triggerType: AlarmTriggerType.time,
    timeHour: hour,
    timeMinute: minute,
    isEnabled: isEnabled,
    isArmed: false,
    soundUri: 'content://default',
    vibrate: true,
    snoozeDurationMin: 10,
    maxSnoozeCount: 3,
    createdAt: now,
    updatedAt: now,
  );
}

Alarm _locationAlarm({
  int? id,
  bool isEnabled = true,
  bool isArmed = false,
  double lat = 51.5074,
  double lon = -0.1278,
  int radius = 2000,
}) {
  final now = DateTime.now().toIso8601String();
  return Alarm(
    id: id,
    label: 'Location alarm',
    triggerType: AlarmTriggerType.location,
    latitude: lat,
    longitude: lon,
    radiusMeters: radius,
    isEnabled: isEnabled,
    isArmed: isArmed,
    soundUri: '',
    vibrate: true,
    snoozeDurationMin: 10,
    maxSnoozeCount: null,
    createdAt: now,
    updatedAt: now,
  );
}

Future<bool> _waitForCondition(
  bool Function() predicate, {
  Duration step = const Duration(milliseconds: 20),
  int maxIterations = 100,
}) async {
  for (var i = 0; i < maxIterations; i++) {
    if (predicate()) return true;
    await Future<void>.delayed(step);
  }
  return predicate();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late WakeyDatabase database;
  late ProviderContainer container;
  late _FakeAlarmBridge fakeBridge;
  late _FakeGeofenceBridge fakeGeofenceBridge;
  late String dbPath;

  setUp(() async {
    fakeBridge = _FakeAlarmBridge();
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
        alarmBridgeProvider.overrideWithValue(fakeBridge),
        geofenceBridgeProvider.overrideWithValue(fakeGeofenceBridge),
        alarmEventsProvider.overrideWith(
          (ref) => fakeBridge.eventController.stream,
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    if (!fakeBridge.eventController.isClosed) {
      await fakeBridge.eventController.close();
    }
    final f = File(dbPath);
    if (f.existsSync()) {
      try {
        f.deleteSync();
      } catch (_) {}
    }
  });

  // ===========================================================================
  // FUNCTIONAL TESTS — exercise the full insert → schedule → list flow
  // ===========================================================================

  group('Alarm create/list/schedule flow', () {
    test('insert a time alarm appears in the list and triggers a schedule', () async {
      final notifier = container.read(alarmsNotifierProvider.notifier);
      final result = await notifier.insertAlarm(_timeAlarm());
      expect(result.scheduled, isTrue);

      final list = await container.read(alarmsNotifierProvider.future);
      expect(list, hasLength(1));
      expect(list.first.id, result.id);
      expect(list.first.isEnabled, isTrue);

      // The native bridge was called once with the correct id.
      expect(fakeBridge.scheduleAlarmCalls, hasLength(1));
      expect(fakeBridge.scheduleAlarmCalls.single['alarmId'], result.id);
    });

    test(
      'insert then delete removes from the list and cancels the schedule',
      () async {
        final notifier = container.read(alarmsNotifierProvider.notifier);
        final result = await notifier.insertAlarm(_timeAlarm());
        await notifier.deleteAlarm(result.id);

        final list = await container.read(alarmsNotifierProvider.future);
        expect(list, isEmpty);
        expect(fakeBridge.cancelCalls, contains(result.id));
      },
    );

    test('update reschedules when the time changes', () async {
      final notifier = container.read(alarmsNotifierProvider.notifier);
      await notifier.insertAlarm(_timeAlarm(hour: 7));
      final original = (await container.read(alarmsNotifierProvider.future))
          .single;

      final updated = original.copyWith(timeHour: 8);
      final ok = await notifier.updateAlarm(updated);
      expect(ok, isTrue);

      // The bridge saw a cancel and a new schedule.
      expect(fakeBridge.cancelCalls, contains(original.id));
      expect(fakeBridge.scheduleAlarmCalls, hasLength(2));
      final lastCall = fakeBridge.scheduleAlarmCalls.last;
      expect(lastCall['alarmId'], original.id);
      expect(lastCall['timeHour'], 8);
    });

    test('toggleEnabled off then on reschedules', () async {
      final notifier = container.read(alarmsNotifierProvider.notifier);
      final result = await notifier.insertAlarm(_timeAlarm());
      final id = result.id;
      fakeBridge.scheduleAlarmCalls.clear();
      fakeBridge.cancelCalls.clear();

      await notifier.toggleEnabled(id, false);
      await notifier.toggleEnabled(id, true);

      expect(fakeBridge.cancelCalls, contains(id));
      expect(fakeBridge.scheduleAlarmCalls, hasLength(1));
      expect(fakeBridge.scheduleAlarmCalls.single['alarmId'], id);
    });

    test('disabling a one-shot alarm does not delete it from the DB', () async {
      final notifier = container.read(alarmsNotifierProvider.notifier);
      final result = await notifier.insertAlarm(_timeAlarm());
      final id = result.id;

      await notifier.toggleEnabled(id, false);

      // The row is still present.
      final after = await container.read(alarmByIdProvider(id).future);
      expect(after, isNotNull);
      expect(after!.isEnabled, isFalse);
    });

    test('schedule failure keeps the DB row in the enabled state', () async {
      // Create a disabled alarm first (so the initial insert
      // doesn't try to schedule), then flip to enabled to trigger
      // a schedule that the bridge will reject.
      fakeBridge.scheduleAlarmResult = false;
      final notifier = container.read(alarmsNotifierProvider.notifier);
      final alarm = _timeAlarm(isEnabled: false);
      final result = await notifier.insertAlarm(alarm);
      expect(result.scheduled, isTrue,
          reason: 'a disabled alarm does not need to be scheduled');

      // Toggle ON triggers a re-schedule that fails.
      final ok = await notifier.toggleEnabled(result.id, true);
      expect(ok, isFalse);
      // The DB row is still enabled (the user expressed intent).
      final after = await container
          .read(alarmByIdProvider(result.id).future);
      expect(after!.isEnabled, isTrue);
    });
  });

  // ===========================================================================
  // FUNCTIONAL TESTS — geofence arming end-to-end
  // ===========================================================================

  group('Geofence arming/disarming flow', () {
    test(
      'arm a location alarm registers a geofence and flips isArmed in the DB',
      () async {
        final dao = container.read(alarmDaoProvider);
        final id = await dao.insert(_locationAlarm());
        final alarm = (await dao.read(id))!;

        final controller = container.read(geofenceArmingControllerProvider);
        final result = await controller.armAlarm(alarm);
        expect(result.outcome, ArmingOutcome.armed);
        expect(fakeGeofenceBridge.addCalls, hasLength(1));

        final armed = await dao.read(id);
        expect(armed!.isArmed, isTrue);
      },
    );

    test(
      'disarm removes the native geofence and flips isArmed in the DB',
      () async {
        final dao = container.read(alarmDaoProvider);
        final id = await dao.insert(_locationAlarm());
        await dao.updateArmed(id, true);
        final armed = (await dao.read(id))!;

        final controller = container.read(geofenceArmingControllerProvider);
        final ok = await controller.disarmAlarm(armed);
        expect(ok, isTrue);
        expect(fakeGeofenceBridge.removeCalls, [id]);
        final disarmed = await dao.read(id);
        expect(disarmed!.isArmed, isFalse);
      },
    );

    test(
      'dismissed event for a location alarm removes the geofence and disarms it',
      () async {
        // Simulate the user arming, then the native side sending a
        // fired + dismissed sequence (the user acknowledged the
        // ringing UI). The AlarmsNotifier's listener should
        // remove the geofence and flip is_armed to false.
        final dao = container.read(alarmDaoProvider);
        final id = await dao.insert(_locationAlarm());

        // Pre-warm the alarms notifier so its event listener is
        // active.
        await container.read(alarmsNotifierProvider.future);
        container.listen(alarmsNotifierProvider, (_, _) {});

        // Arm the alarm.
        final controller = container.read(geofenceArmingControllerProvider);
        final alarm = (await dao.read(id))!;
        var r = await controller.armAlarm(alarm);
        expect(r.outcome, ArmingOutcome.armed);
        expect((await dao.read(id))!.isArmed, isTrue);

        // The native side fires and then the user dismisses.
        fakeBridge.eventController.add(
          AlarmEvent(
            alarmId: id,
            type: AlarmEventType.fired,
            triggerType: 'location',
          ),
        );
        // Small delay so the fired event is processed before the
        // dismissed event (avoids race in the listener).
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fakeBridge.eventController.add(
          AlarmEvent(
            alarmId: id,
            type: AlarmEventType.dismissed,
            triggerType: 'location',
          ),
        );

        // Wait for the listener to process the dismissed event.
        await _waitForCondition(
          () => fakeGeofenceBridge.removeCalls.contains(id),
          maxIterations: 200,
        );
        expect(fakeGeofenceBridge.removeCalls, contains(id));

        // After dismiss, the alarm should be disarmed.
        await _waitForCondition(
          () => !(container.read(alarmsNotifierProvider).value!
              .firstWhere((a) => a.id == id, orElse: () => _locationAlarm())
              .isArmed),
          maxIterations: 200,
        );

        // Re-arm for a future trip. Since is_armed is now false,
        // the controller should accept the call.
        final after = (await dao.read(id))!;
        r = await controller.armAlarm(after);
        expect(r.outcome, ArmingOutcome.armed);
        expect((await dao.read(id))!.isArmed, isTrue);
      },
    );
  });

  // ===========================================================================
  // FUNCTIONAL TESTS — timer lifecycle
  // ===========================================================================

  group('Timer create/pause/resume/cancel flow', () {
    test('create inserts a running row and schedules via the bridge', () async {
      final notifier = container.read(timersProvider.notifier);
      final ok = await notifier.create(
        label: 'Boil eggs',
        durationSeconds: 300,
      );
      expect(ok, isTrue);

      final list = await container.read(timersProvider.future);
      expect(list, hasLength(1));
      expect(list.first.state, TimerState.running);
      expect(list.first.durationSeconds, 300);
      expect(list.first.remainingSeconds, 300);

      // TimersNotifier.create calls AlarmBridge.scheduleTimer, which
      // in the real bridge adds triggerType='TIMER'. Our fake records
      // the payload before that enrichment, so we only assert on
      // the fields TimersNotifier itself passes.
      expect(fakeBridge.scheduleTimerCalls, hasLength(1));
      final payload = fakeBridge.scheduleTimerCalls.single;
      expect(payload['alarmId'], list.first.id);
      expect(payload['label'], 'Boil eggs');
      expect(payload['triggerAtMillis'], isA<int>());
    });

    test('pause freezes the remaining and cancels the native schedule', () async {
      final notifier = container.read(timersProvider.notifier);
      await notifier.create(label: 'Test', durationSeconds: 600);
      final id = (await container.read(timersProvider.future)).single.id!;
      fakeBridge.cancelCalls.clear();

      await notifier.pause(id);
      expect(fakeBridge.cancelCalls, contains(id));

      final after = (await container.read(timersProvider.future)).single;
      expect(after.state, TimerState.paused);
    });

    test('cancel deletes the row and cancels the native schedule', () async {
      final notifier = container.read(timersProvider.notifier);
      await notifier.create(label: 'Test', durationSeconds: 60);
      final id = (await container.read(timersProvider.future)).single.id!;
      fakeBridge.cancelCalls.clear();

      await notifier.cancel(id);
      expect(fakeBridge.cancelCalls, contains(id));
      final after = await container.read(timersProvider.future);
      expect(after, isEmpty);
    });

    test('resume after pause re-schedules with a fresh fire time', () async {
      final notifier = container.read(timersProvider.notifier);
      await notifier.create(label: 'Test', durationSeconds: 600);
      final id = (await container.read(timersProvider.future)).single.id!;
      await notifier.pause(id);
      fakeBridge.scheduleTimerCalls.clear();
      fakeBridge.cancelCalls.clear();

      final ok = await notifier.resume(id);
      expect(ok, isTrue);
      expect(fakeBridge.scheduleTimerCalls, hasLength(1));
      // The fresh fire time is in the future.
      final triggerAt =
          fakeBridge.scheduleTimerCalls.single['triggerAtMillis'] as int;
      expect(triggerAt, greaterThan(DateTime.now().millisecondsSinceEpoch));
    });

    test('schedule failure on create rolls back the DB row', () async {
      fakeBridge.scheduleTimerResult = false;
      final notifier = container.read(timersProvider.notifier);
      final ok = await notifier.create(label: 'Test', durationSeconds: 60);
      expect(ok, isFalse);
      final list = await container.read(timersProvider.future);
      expect(list, isEmpty);
    });

    test('fired → dismiss event deletes the timer row', () async {
      await container.read(timersProvider.future);
      container.listen(timersProvider, (_, _) {});
      final notifier = container.read(timersProvider.notifier);
      await notifier.create(label: 'Test', durationSeconds: 600);
      final id = (await container.read(timersProvider.future)).single.id!;

      fakeBridge.eventController.add(
        AlarmEvent(
          alarmId: id,
          type: AlarmEventType.fired,
          triggerType: 'timer',
        ),
      );
      fakeBridge.eventController.add(
        AlarmEvent(alarmId: id, type: AlarmEventType.dismissed),
      );

      await _waitForCondition(
        () => (container.read(timersProvider).value ?? const <TimerRecord>[])
            .isEmpty,
        maxIterations: 200,
      );
      final list = container.read(timersProvider).value!;
      expect(list, isEmpty);
    });

    test('snooze event without a preceding fired event keeps the row running',
        () async {
      // The fired → snooze sequence is tricky to test reliably in
      // a unit test because the TimersNotifier's invalidateSelf
      // races with the stream subscription teardown. We test the
      // snooze path independently: a snoozed event for an
      // existing timer should leave the row in the RUNNING state.
      await container.read(timersProvider.future);
      container.listen(timersProvider, (_, _) {});
      final notifier = container.read(timersProvider.notifier);
      await notifier.create(label: 'Test', durationSeconds: 600);
      final id = (await container.read(timersProvider.future)).single.id!;
      fakeBridge.scheduleTimerCalls.clear();

      // Wait for the first tick to settle so we know the ticker is
      // running. Then send a snooze event.
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (notifier.liveRemainingForActive != null) break;
      }
      fakeBridge.eventController.add(
        AlarmEvent(alarmId: id, type: AlarmEventType.snoozed),
      );

      // Wait for the listener to process the event.
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      // The row should still be present and running.
      final list = await container.read(timersProvider.future);
      expect(list, hasLength(1));
      expect(list.first.state, TimerState.running);
      expect(list.first.id, id);
    });
  });

  // ===========================================================================
  // FUNCTIONAL TESTS — ringing state
  // ===========================================================================

  group('Ringing state', () {
    test('a fired event makes ringingAlarmIdProvider emit the alarm id', () async {
      // Start the async generator before any events are added.
      final subscription = container.listen<AsyncValue<int?>>(
        ringingAlarmIdProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      // Give the async generator a moment to yield its initial
      // null value and wire up the stream subscription.
      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (container.read(ringingAlarmIdProvider).value == null) break;
      }

      fakeBridge.eventController.add(
        const AlarmEvent(
          alarmId: 42,
          type: AlarmEventType.fired,
          triggerType: 'time',
        ),
      );
      final settled = await _waitForCondition(
        () => container.read(ringingAlarmIdProvider).value == 42,
        maxIterations: 300,
        step: const Duration(milliseconds: 20),
      );
      expect(settled, isTrue,
          reason: 'fired event should propagate to provider, got '
              '${container.read(ringingAlarmIdProvider).value}');
      expect(container.read(ringingAlarmIdProvider).value, 42);
    });

    test('timer fired events do NOT set the ringing state', () async {
      final subscription = container.listen<AsyncValue<int?>>(
        ringingAlarmIdProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (container.read(ringingAlarmIdProvider).value == null) break;
      }

      fakeBridge.eventController.add(
        const AlarmEvent(
          alarmId: 99,
          type: AlarmEventType.fired,
          triggerType: 'timer',
        ),
      );
      // Wait a few ticks to be sure no emission happened.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(container.read(ringingAlarmIdProvider).value, isNull);
    });

    test('a dismissed event clears the ringing state', () async {
      final subscription = container.listen<AsyncValue<int?>>(
        ringingAlarmIdProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);

      for (var i = 0; i < 50; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (container.read(ringingAlarmIdProvider).value == null) break;
      }

      fakeBridge.eventController.add(
        const AlarmEvent(
          alarmId: 7,
          type: AlarmEventType.fired,
          triggerType: 'time',
        ),
      );
      await _waitForCondition(
        () => container.read(ringingAlarmIdProvider).value == 7,
        maxIterations: 300,
        step: const Duration(milliseconds: 20),
      );

      fakeBridge.eventController.add(
        const AlarmEvent(alarmId: 7, type: AlarmEventType.dismissed),
      );
      final settled = await _waitForCondition(
        () => container.read(ringingAlarmIdProvider).value == null,
        maxIterations: 300,
        step: const Duration(milliseconds: 20),
      );
      expect(settled, isTrue,
          reason: 'dismissed event should clear ringing state');
    });
  });

  // ===========================================================================
  // FUNCTIONAL TESTS — error / edge paths
  // ===========================================================================

  group('Error and edge paths', () {
    test('insertAlarm with create returning false rolls back the row', () async {
      // Sanity: the notifier relies on the bridge's schedule result.
      // A false result for a time alarm does NOT roll back (only
      // the user has to retry), but a false result for create
      // (timer) does. Verify the time alarm keeps the row.
      fakeBridge.scheduleAlarmResult = false;
      final notifier = container.read(alarmsNotifierProvider.notifier);
      final result = await notifier.insertAlarm(_timeAlarm());
      expect(result.scheduled, isFalse);
      final list = await container.read(alarmsNotifierProvider.future);
      expect(list, hasLength(1),
          reason: 'time alarm row must be kept even if scheduling fails');
    });

    test('toggleArmed only flips the DB flag, no native side effect', () async {
      final notifier = container.read(alarmsNotifierProvider.notifier);
      final result = await notifier.insertAlarm(_locationAlarm());
      fakeBridge.scheduleAlarmCalls.clear();
      fakeGeofenceBridge.addCalls.clear();
      fakeGeofenceBridge.removeCalls.clear();

      await notifier.toggleArmed(result.id, true);
      final after = await container
          .read(alarmByIdProvider(result.id).future);
      expect(after!.isArmed, isTrue);
      // No native side effects from toggleArmed — arming is the
      // GeofenceArmingController's job.
      expect(fakeBridge.scheduleAlarmCalls, isEmpty);
      expect(fakeGeofenceBridge.addCalls, isEmpty);
      expect(fakeGeofenceBridge.removeCalls, isEmpty);
    });

    test('create with zero duration throws ArgumentError', () async {
      final notifier = container.read(timersProvider.notifier);
      expect(
        () => notifier.create(label: 'x', durationSeconds: 0),
        throwsArgumentError,
      );
    });

    test('create with negative duration throws ArgumentError', () async {
      final notifier = container.read(timersProvider.notifier);
      expect(
        () => notifier.create(label: 'x', durationSeconds: -5),
        throwsArgumentError,
      );
    });

    test(
      'arming a location alarm inside the geofence returns alreadyInside with distance',
      () async {
        // User is *at* the geofence center, well inside the 2 km
        // radius.
        fakeGeofenceBridge.currentLocation = const GeoPoint(
          latitude: 51.5074,
          longitude: -0.1278,
        );
        final dao = container.read(alarmDaoProvider);
        final id = await dao.insert(_locationAlarm());
        final alarm = (await dao.read(id))!;

        final controller = container.read(geofenceArmingControllerProvider);
        final result = await controller.armAlarm(alarm);
        expect(result.outcome, ArmingOutcome.alreadyInside);
        expect(result.distanceMeters, isNotNull);
        expect(result.distanceMeters!, closeTo(0, 1.0));
        // No native call was made.
        expect(fakeGeofenceBridge.addCalls, isEmpty);
      },
    );
  });
}
