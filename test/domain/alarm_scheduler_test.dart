import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/domain/alarm_scheduler.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';

class _RecordingAlarmBridge implements AlarmBridge {
  List<Map<String, Object?>> scheduleCalls = [];
  List<int> cancelCalls = [];

  @override
  Stream<AlarmEvent>? eventStream;
  @override
  Stream<AlarmEvent> get alarmEvents => const Stream.empty();
  @override
  Future<bool> scheduleAlarm(Map<String, Object?> payload) async {
    scheduleCalls.add(Map.of(payload));
    return true;
  }

  @override
  Future<bool> scheduleTimer(Map<String, Object?> payload) async {
    scheduleCalls.add(Map.of(payload));
    return true;
  }

  @override
  Future<bool> cancelAlarm(int alarmId) async {
    cancelCalls.add(alarmId);
    return true;
  }

  @override
  Future<String?> pickRingtone({String? currentUri}) async => null;
}

Alarm _timeAlarm({int? id, bool isEnabled = true}) {
  final now = DateTime.now().toIso8601String();
  return Alarm(
    id: id,
    label: 'x',
    triggerType: AlarmTriggerType.time,
    timeHour: 7,
    timeMinute: 30,
    isEnabled: isEnabled,
    isArmed: false,
    soundUri: 'content://x',
    vibrate: true,
    snoozeDurationMin: 10,
    maxSnoozeCount: 3,
    createdAt: now,
    updatedAt: now,
  );
}

Alarm _locationAlarm({int? id, bool isEnabled = true}) {
  final now = DateTime.now().toIso8601String();
  return Alarm(
    id: id,
    label: 'x',
    triggerType: AlarmTriggerType.location,
    latitude: 51.5074,
    longitude: -0.1278,
    radiusMeters: 2000,
    isEnabled: isEnabled,
    isArmed: false,
    soundUri: 'content://x',
    vibrate: true,
    snoozeDurationMin: 10,
    maxSnoozeCount: null,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('AlarmScheduler', () {
    test('scheduleAlarm forwards a time alarm payload', () async {
      final bridge = _RecordingAlarmBridge();
      final scheduler = AlarmScheduler(bridge);
      final alarm = _timeAlarm(id: 7);

      final ok = await scheduler.scheduleAlarm(alarm);
      expect(ok, isTrue);
      expect(bridge.scheduleCalls, hasLength(1));
      final payload = bridge.scheduleCalls.single;
      expect(payload['alarmId'], 7);
      expect(payload['timeHour'], 7);
      expect(payload['timeMinute'], 30);
      expect(payload['label'], 'x');
      expect(payload['soundUri'], 'content://x');
      expect(payload['vibrate'], isTrue);
      expect(payload['snoozeDurationMin'], 10);
      expect(payload['maxSnoozeCount'], 3);
    });

    test('scheduleAlarm returns false for a disabled alarm', () async {
      final bridge = _RecordingAlarmBridge();
      final scheduler = AlarmScheduler(bridge);
      final alarm = _timeAlarm(id: 1, isEnabled: false);

      final ok = await scheduler.scheduleAlarm(alarm);
      expect(ok, isFalse);
      expect(bridge.scheduleCalls, isEmpty);
    });

    test('scheduleAlarm returns false for a location alarm', () async {
      final bridge = _RecordingAlarmBridge();
      final scheduler = AlarmScheduler(bridge);
      final alarm = _locationAlarm(id: 1);

      final ok = await scheduler.scheduleAlarm(alarm);
      expect(ok, isFalse);
      expect(bridge.scheduleCalls, isEmpty);
    });

    test('scheduleAlarm returns false when id is null', () async {
      final bridge = _RecordingAlarmBridge();
      final scheduler = AlarmScheduler(bridge);
      final alarm = _timeAlarm(); // id is null

      final ok = await scheduler.scheduleAlarm(alarm);
      expect(ok, isFalse);
      expect(bridge.scheduleCalls, isEmpty);
    });

    test('scheduleAlarm returns false when time fields are null', () async {
      final bridge = _RecordingAlarmBridge();
      final scheduler = AlarmScheduler(bridge);
      // Build a time alarm with null time fields (defensive).
      final now = DateTime.now().toIso8601String();
      final alarm = Alarm(
        id: 1,
        label: 'x',
        triggerType: AlarmTriggerType.time,
        timeHour: null,
        timeMinute: null,
        isEnabled: true,
        isArmed: false,
        soundUri: '',
        vibrate: true,
        snoozeDurationMin: 10,
        createdAt: now,
        updatedAt: now,
      );

      final ok = await scheduler.scheduleAlarm(alarm);
      expect(ok, isFalse);
      expect(bridge.scheduleCalls, isEmpty);
    });

    test('cancelAlarm forwards the id to the bridge', () async {
      final bridge = _RecordingAlarmBridge();
      final scheduler = AlarmScheduler(bridge);

      final ok = await scheduler.cancelAlarm(42);
      expect(ok, isTrue);
      expect(bridge.cancelCalls, [42]);
    });

    test('rescheduleAll schedules every enabled alarm', () async {
      final bridge = _RecordingAlarmBridge();
      final scheduler = AlarmScheduler(bridge);

      await scheduler.rescheduleAll([
        _timeAlarm(id: 1, isEnabled: true),
        _timeAlarm(id: 2, isEnabled: false),
        _timeAlarm(id: 3, isEnabled: true),
        _locationAlarm(id: 4, isEnabled: true), // skipped
      ]);
      expect(bridge.scheduleCalls, hasLength(2));
      final ids = bridge.scheduleCalls
          .map((p) => p['alarmId'])
          .toList();
      expect(ids, containsAll([1, 3]));
      expect(ids, isNot(contains(2)));
      expect(ids, isNot(contains(4)));
    });

    test('rescheduleAll with empty list is a no-op', () async {
      final bridge = _RecordingAlarmBridge();
      final scheduler = AlarmScheduler(bridge);
      await scheduler.rescheduleAll([]);
      expect(bridge.scheduleCalls, isEmpty);
    });
  });
}
