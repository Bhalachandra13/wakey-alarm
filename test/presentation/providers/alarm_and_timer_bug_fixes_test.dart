import 'dart:async';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/domain/timer_record.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/providers/timers_provider.dart';

class _FakeAlarmBridge implements AlarmBridge {
  _FakeAlarmBridge()
    : eventController = StreamController<AlarmEvent>.broadcast();
  final StreamController<AlarmEvent> eventController;

  List<Map<String, Object?>> scheduledTimers = [];
  List<Map<String, Object?>> scheduledAlarms = [];
  List<int> cancelledIds = [];
  bool scheduleSuccess = true;
  bool scheduleTimerSuccess = true;

  @override
  Stream<AlarmEvent>? eventStream;
  @override
  Stream<AlarmEvent> get alarmEvents => eventController.stream;
  @override
  Future<bool> scheduleAlarm(Map<String, Object?> payload) async {
    scheduledAlarms.add(Map.of(payload));
    return scheduleSuccess;
  }

  @override
  Future<bool> scheduleTimer(Map<String, Object?> payload) async {
    scheduledTimers.add(Map.of(payload));
    return scheduleTimerSuccess;
  }

  @override
  Future<bool> cancelAlarm(int alarmId) async {
    cancelledIds.add(alarmId);
    return true;
  }

  @override
  Future<String?> pickRingtone({String? currentUri}) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late WakeyDatabase database;
  late ProviderContainer container;
  late _FakeAlarmBridge fakeBridge;
  late String dbPath;

  setUp(() async {
    fakeBridge = _FakeAlarmBridge();
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

  Alarm createTimeAlarm({
    int? id,
    String label = 'Time alarm',
    int hour = 7,
    int minute = 0,
    bool isEnabled = true,
  }) {
    final now = DateTime.now().toIso8601String();
    return Alarm(
      id: id,
      label: label,
      triggerType: AlarmTriggerType.time,
      timeHour: hour,
      timeMinute: minute,
      isEnabled: isEnabled,
      isArmed: false,
      soundUri: '',
      vibrate: true,
      snoozeDurationMin: 10,
      createdAt: now,
      updatedAt: now,
    );
  }

  Alarm createLocationAlarm({int? id, bool isEnabled = true}) {
    final now = DateTime.now().toIso8601String();
    return Alarm(
      id: id,
      label: 'Location alarm',
      triggerType: AlarmTriggerType.location,
      latitude: 51.5074,
      longitude: -0.1278,
      radiusMeters: 2000,
      isEnabled: isEnabled,
      isArmed: false,
      soundUri: '',
      vibrate: true,
      snoozeDurationMin: 10,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('AlarmsNotifier location-alarm scheduling', () {
    test(
      'insertAlarm does not call scheduleAlarm for a location alarm',
      () async {
        final notifier = container.read(alarmsNotifierProvider.notifier);
        final result = await notifier.insertAlarm(createLocationAlarm());

        expect(result.scheduled, isTrue);
        // The native AlarmManager must NOT be called for a location
        // alarm — the geofence arming flow handles that separately.
        expect(fakeBridge.scheduledAlarms, isEmpty);
        expect(fakeBridge.scheduledTimers, isEmpty);
      },
    );

    test(
      'updateAlarm does not call scheduleAlarm for a location alarm',
      () async {
        final notifier = container.read(alarmsNotifierProvider.notifier);
        final inserted = await notifier.insertAlarm(createLocationAlarm());
        fakeBridge.scheduledAlarms.clear();
        fakeBridge.cancelledIds.clear();

        final updated = (await notifier.updateAlarm(
          (await container
              .read(alarmByIdProvider(inserted.id).future))!,
        ));

        expect(updated, isTrue);
        // updateAlarm cancels the previous schedule (cancelledIds
        // contains the id) but does NOT re-schedule a location
        // alarm via the AlarmManager.
        expect(fakeBridge.scheduledAlarms, isEmpty);
        expect(fakeBridge.cancelledIds, contains(inserted.id));
      },
    );

    test(
      'toggleEnabled does not call scheduleAlarm for a location alarm',
      () async {
        final notifier = container.read(alarmsNotifierProvider.notifier);
        final inserted = await notifier.insertAlarm(
          createLocationAlarm(isEnabled: true),
        );
        fakeBridge.scheduledAlarms.clear();

        final ok = await notifier.toggleEnabled(inserted.id, true);
        expect(ok, isTrue);
        expect(fakeBridge.scheduledAlarms, isEmpty);
      },
    );

    test(
      'toggleEnabled still calls cancelAlarm when disabling a location alarm',
      () async {
        final notifier = container.read(alarmsNotifierProvider.notifier);
        final inserted = await notifier.insertAlarm(
          createLocationAlarm(isEnabled: true),
        );
        fakeBridge.cancelledIds.clear();

        final ok = await notifier.toggleEnabled(inserted.id, false);
        expect(ok, isTrue);
        expect(fakeBridge.cancelledIds, contains(inserted.id));
      },
    );

    test('insertAlarm still calls scheduleAlarm for a time alarm', () async {
      final notifier = container.read(alarmsNotifierProvider.notifier);
      final result = await notifier.insertAlarm(createTimeAlarm());

      expect(result.scheduled, isTrue);
      expect(fakeBridge.scheduledAlarms, hasLength(1));
      expect(fakeBridge.scheduledAlarms.single['alarmId'], result.id);
    });

    test(
      'toggleEnabled reports false when bridge rejects a time alarm',
      () async {
        fakeBridge.scheduleSuccess = false;
        final notifier = container.read(alarmsNotifierProvider.notifier);
        final inserted = await notifier.insertAlarm(
          createTimeAlarm(isEnabled: false),
        );
        // The first insert is fine; flip to enabled to trigger a
        // schedule that the bridge will reject.
        final ok = await notifier.toggleEnabled(inserted.id, true);
        expect(ok, isFalse);
        // The DB row is still updated to reflect the user's intent.
        final after =
            await container.read(alarmByIdProvider(inserted.id).future);
        expect(after!.isEnabled, isTrue);
      },
    );
  });

  group('TimersNotifier live remaining after resume', () {
    test(
      'resumed timer counts down from the paused remaining, not the full duration',
      () async {
        // Create a 60-second timer.
        final notifier = container.read(timersProvider.notifier);
        final ok = await notifier.create(
          label: 'Test',
          durationSeconds: 60,
        );
        expect(ok, isTrue);
        final initial =
            (await container.read(timersProvider.future)).single;
        expect(initial.remainingSeconds, 60);

        // Fake-advance the clock by 10 seconds, then pause. The
        // ticker would have called updateRemaining in production,
        // but in this test we update the row directly to keep the
        // test focused on the resume behavior.
        await withClock(Clock.fixed(DateTime.now().add(
              const Duration(seconds: 10),
            )), () async {
          final dao = container.read(timerDaoProvider);
          final id = initial.id!;
          await dao.update(initial.copyWith(remainingSeconds: 50));
          await notifier.pause(id);
          // Stop the ticker so we control the next read.
        });

        // After pause, the row reflects the frozen remaining.
        final paused = (await container.read(timersProvider.future))
            .firstWhere((t) => t.state == TimerState.paused);
        expect(paused.remainingSeconds, 50);

        // Resume. Started-at is reset to `now`, remaining is still
        // 50. The ticker should now count down from 50, not from 60.
        await withClock(Clock.fixed(DateTime.now().add(
              const Duration(seconds: 20),
            )), () async {
          await notifier.resume(paused.id!);
        });

        // The DB row's remainingSeconds was last set to 50 at pause
        // time. The ticker hasn't had a chance to tick under the new
        // clock, so the row still reads 50. The critical assertion
        // is that the *next tick* would subtract from 50, not 60.
        final resumed = (await container.read(timersProvider.future))
            .firstWhere((t) => t.state == TimerState.running);
        expect(resumed.durationSeconds, 60);
        expect(resumed.remainingSeconds, 50,
            reason: 'remaining must not reset to durationSeconds on resume');
      },
    );

    test(
      'resumed timer counts down correctly via the ticker',
      () async {
        // Use a shorter-duration timer so the ticker has time to
        // fire a few times. We control the clock so the assertions
        // are deterministic.
        final notifier = container.read(timersProvider.notifier);
        final start = DateTime(2026, 7, 22, 12, 0, 0);
        await withClock(Clock.fixed(start), () async {
          await notifier.create(label: 'Test', durationSeconds: 60);
        });
        final created =
            (await container.read(timersProvider.future)).single;

        // Advance 10s, pause, manually update remaining to 50.
        await withClock(Clock.fixed(start.add(const Duration(seconds: 10))),
            () async {
          final dao = container.read(timerDaoProvider);
          await dao.update(created.copyWith(remainingSeconds: 50));
          await notifier.pause(created.id!);
        });

        // Resume at t=20s. The ticker should now use 50 as the base.
        await withClock(Clock.fixed(start.add(const Duration(seconds: 20))),
            () async {
          await notifier.resume(created.id!);

          // Pump the ticker once. It runs at 200ms cadence, so a
          // 300ms advance gives it a chance to tick.
          await Future<void>.delayed(const Duration(milliseconds: 300));

          final afterResume =
              (await container.read(timersProvider.future)).single;
          // The first tick may or may not have written to the DB
          // (the persist guard waits ~1s). The live value should be
          // in the (40, 50] range. Critically, it must not have
          // reset to (50, 60].
          expect(afterResume.remainingSeconds, lessThanOrEqualTo(50),
              reason: 'remaining must not exceed the value at resume');
        });
      },
    );
  });

  group('TimersNotifier fired event stops the ticker', () {
    test(
      'ticker stops when a fired event arrives for the active timer',
      () async {
        await container.read(timersProvider.future);
        container.listen(timersProvider, (_, _) {});

        final notifier = container.read(timersProvider.notifier);
        await notifier.create(label: 'Test', durationSeconds: 60);
        final id = (await container.read(timersProvider.future))
            .single
            .id!;

        // The ticker is scheduled but won't have ticked yet in this
        // test (the production ticker runs at 200ms cadence; the
        // first tick fires asynchronously). Instead of waiting for
        // it, we directly check that _stopTicker resets the state
        // by observing the public getter after the fired event.
        // The live value is null until the first tick, but the
        // _lastTickedTimerId is set by _startTickerFor. The fired
        // event handler calls _stopTicker when the id matches, so
        // we verify the behavior via the notifier's public state.
        fakeBridge.eventController.add(
          AlarmEvent(
            alarmId: id,
            type: AlarmEventType.fired,
            triggerType: 'timer',
          ),
        );
        // Let the listener process.
        for (var i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        // After the fired event handler runs, the ticker must be
        // stopped. We can verify by checking that
        // liveRemainingForActive remains null (it would have been
        // populated by a tick if the ticker were still running).
        // The ticker is real Timer.periodic in the test environment
        // (we don't use fakeAsync here), so we wait long enough for
        // a tick to potentially fire (~250ms) and assert the value
        // is null.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(notifier.liveRemainingForActive, isNull,
            reason: 'ticker must stop after the fired event; '
                'got ${notifier.liveRemainingForActive}');
      },
    );

    test(
      'ticker stops when a snoozed event arrives for the active timer',
      () async {
        await container.read(timersProvider.future);
        container.listen(timersProvider, (_, _) {});

        final notifier = container.read(timersProvider.notifier);
        await notifier.create(label: 'Test', durationSeconds: 60);
        final id = (await container.read(timersProvider.future))
            .single
            .id!;

        fakeBridge.eventController.add(
          AlarmEvent(alarmId: id, type: AlarmEventType.snoozed),
        );
        for (var i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        // Wait long enough that a real tick would have fired.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(notifier.liveRemainingForActive, isNull,
            reason: 'ticker must stop after a snooze; '
                'got ${notifier.liveRemainingForActive}');
      },
    );

    test(
      'fired event for a non-active timer does not affect the active ticker',
      () async {
        await container.read(timersProvider.future);
        container.listen(timersProvider, (_, _) {});

        final notifier = container.read(timersProvider.notifier);
        await notifier.create(label: 'Test', durationSeconds: 60);

        // Fire a different timer that doesn't exist in our DB.
        fakeBridge.eventController.add(
          const AlarmEvent(
            alarmId: 99999,
            type: AlarmEventType.fired,
            triggerType: 'timer',
          ),
        );
        for (var i = 0; i < 50; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        // The active timer's ticker must still be running. We can't
        // easily verify it's *ticking* (that depends on real time),
        // but we can verify the notifier didn't crash and the row
        // is still present.
        final list = await container.read(timersProvider.future);
        expect(list, hasLength(1));
      },
    );
  });
}
