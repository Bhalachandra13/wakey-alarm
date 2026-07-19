import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/domain/alarm.dart';

void main() {
  group('Alarm', () {
    test('creates an alarm with required fields', () {
      final now = DateTime.now().toIso8601String();
      const alarm = Alarm(
        label: 'Morning Alarm',
        triggerType: AlarmTriggerType.time,
        timeHour: 7,
        timeMinute: 30,
        isEnabled: true,
        isArmed: false,
        soundUri: 'content://media/system_alarms/default',
        vibrate: true,
        snoozeDurationMin: 10,
        createdAt: '2026-07-10T07:30:00Z',
        updatedAt: '2026-07-10T07:30:00Z',
      );

      expect(alarm.id, isNull);
      expect(alarm.label, equals('Morning Alarm'));
      expect(alarm.triggerType, equals(AlarmTriggerType.time));
      expect(alarm.timeHour, equals(7));
      expect(alarm.timeMinute, equals(30));
      expect(alarm.isEnabled, isTrue);
      expect(alarm.isArmed, isFalse);
      expect(alarm.vibrate, isTrue);
      expect(alarm.snoozeDurationMin, equals(10));
    });

    test('copyWith creates a new alarm with updated fields', () {
      const original = Alarm(
        id: 1,
        label: 'Morning Alarm',
        triggerType: AlarmTriggerType.time,
        timeHour: 7,
        timeMinute: 30,
        isEnabled: true,
        isArmed: false,
        soundUri: 'content://media/system_alarms/default',
        vibrate: true,
        snoozeDurationMin: 10,
        createdAt: '2026-07-10T07:30:00Z',
        updatedAt: '2026-07-10T07:30:00Z',
      );

      final updated = original.copyWith(
        timeHour: 8,
        isEnabled: false,
        updatedAt: '2026-07-10T08:00:00Z',
      );

      expect(updated.id, equals(1));
      expect(updated.label, equals('Morning Alarm'));
      expect(updated.timeHour, equals(8)); // Updated
      expect(updated.isEnabled, isFalse); // Updated
      expect(updated.updatedAt, equals('2026-07-10T08:00:00Z')); // Updated
      expect(updated.timeMinute, equals(30)); // Unchanged
    });

    test('toJson converts alarm to map with correct types', () {
      const alarm = Alarm(
        id: 1,
        label: 'Morning Alarm',
        triggerType: AlarmTriggerType.time,
        timeHour: 7,
        timeMinute: 30,
        repeatDays: 'MON,TUE,WED',
        isEnabled: true,
        isArmed: false,
        soundUri: 'content://media/system_alarms/default',
        vibrate: true,
        snoozeDurationMin: 10,
        maxSnoozeCount: 3,
        createdAt: '2026-07-10T07:30:00Z',
        updatedAt: '2026-07-10T07:30:00Z',
      );

      final json = alarm.toJson();

      expect(json['id'], equals(1));
      expect(json['label'], equals('Morning Alarm'));
      expect(json['trigger_type'], equals('TIME'));
      expect(json['time_hour'], equals(7));
      expect(json['time_minute'], equals(30));
      expect(json['repeat_days'], equals('MON,TUE,WED'));
      expect(json['is_enabled'], equals(1)); // Boolean to int
      expect(json['is_armed'], equals(0)); // Boolean to int
      expect(json['vibrate'], equals(1)); // Boolean to int
      expect(json['snooze_duration_min'], equals(10));
      expect(json['max_snooze_count'], equals(3));
    });

    test('fromJson creates alarm from map', () {
      final json = {
        'id': 1,
        'label': 'Morning Alarm',
        'trigger_type': 'TIME',
        'time_hour': 7,
        'time_minute': 30,
        'repeat_days': 'MON,TUE,WED',
        'latitude': null,
        'longitude': null,
        'radius_meters': null,
        'is_enabled': 1,
        'is_armed': 0,
        'sound_uri': 'content://media/system_alarms/default',
        'vibrate': 1,
        'snooze_duration_min': 10,
        'max_snooze_count': 3,
        'created_at': '2026-07-10T07:30:00Z',
        'updated_at': '2026-07-10T07:30:00Z',
      };

      final alarm = Alarm.fromJson(json);

      expect(alarm.id, equals(1));
      expect(alarm.label, equals('Morning Alarm'));
      expect(alarm.triggerType, equals(AlarmTriggerType.time));
      expect(alarm.timeHour, equals(7));
      expect(alarm.timeMinute, equals(30));
      expect(alarm.repeatDays, equals('MON,TUE,WED'));
      expect(alarm.isEnabled, isTrue);
      expect(alarm.isArmed, isFalse);
      expect(alarm.vibrate, isTrue);
      expect(alarm.snoozeDurationMin, equals(10));
      expect(alarm.maxSnoozeCount, equals(3));
    });

    test('toJson and fromJson are inverses', () {
      const original = Alarm(
        id: 1,
        label: 'Morning Alarm',
        triggerType: AlarmTriggerType.time,
        timeHour: 7,
        timeMinute: 30,
        repeatDays: 'MON,TUE,WED',
        isEnabled: true,
        isArmed: false,
        soundUri: 'content://media/system_alarms/default',
        vibrate: true,
        snoozeDurationMin: 10,
        maxSnoozeCount: 3,
        createdAt: '2026-07-10T07:30:00Z',
        updatedAt: '2026-07-10T07:30:00Z',
      );

      final json = original.toJson();
      final restored = Alarm.fromJson(json);

      expect(restored, equals(original));
    });

    test('supports location trigger type', () {
      const alarm = Alarm(
        label: 'Get off train',
        triggerType: AlarmTriggerType.location,
        latitude: 51.5074,
        longitude: -0.1278,
        radiusMeters: 2000,
        isEnabled: true,
        isArmed: true,
        soundUri: 'content://media/system_alarms/default',
        vibrate: true,
        snoozeDurationMin: 10,
        createdAt: '2026-07-10T07:30:00Z',
        updatedAt: '2026-07-10T07:30:00Z',
      );

      expect(alarm.triggerType, equals(AlarmTriggerType.location));
      expect(alarm.latitude, equals(51.5074));
      expect(alarm.longitude, equals(-0.1278));
      expect(alarm.radiusMeters, equals(2000));
      expect(alarm.timeHour, isNull); // Not applicable for location alarms
    });

    test('AlarmTriggerType.fromValue parses string correctly', () {
      expect(AlarmTriggerType.fromValue('TIME'), equals(AlarmTriggerType.time));
      expect(
        AlarmTriggerType.fromValue('LOCATION'),
        equals(AlarmTriggerType.location),
      );
    });

    test('AlarmTriggerType.fromValue throws on unknown type', () {
      expect(() => AlarmTriggerType.fromValue('UNKNOWN'), throwsArgumentError);
    });

    test('equality works correctly', () {
      const alarm1 = Alarm(
        id: 1,
        label: 'Morning Alarm',
        triggerType: AlarmTriggerType.time,
        timeHour: 7,
        timeMinute: 30,
        isEnabled: true,
        isArmed: false,
        soundUri: 'content://media/system_alarms/default',
        vibrate: true,
        snoozeDurationMin: 10,
        createdAt: '2026-07-10T07:30:00Z',
        updatedAt: '2026-07-10T07:30:00Z',
      );

      const alarm2 = Alarm(
        id: 1,
        label: 'Morning Alarm',
        triggerType: AlarmTriggerType.time,
        timeHour: 7,
        timeMinute: 30,
        isEnabled: true,
        isArmed: false,
        soundUri: 'content://media/system_alarms/default',
        vibrate: true,
        snoozeDurationMin: 10,
        createdAt: '2026-07-10T07:30:00Z',
        updatedAt: '2026-07-10T07:30:00Z',
      );

      const alarm3 = Alarm(
        id: 2,
        label: 'Morning Alarm',
        triggerType: AlarmTriggerType.time,
        timeHour: 7,
        timeMinute: 30,
        isEnabled: true,
        isArmed: false,
        soundUri: 'content://media/system_alarms/default',
        vibrate: true,
        snoozeDurationMin: 10,
        createdAt: '2026-07-10T07:30:00Z',
        updatedAt: '2026-07-10T07:30:00Z',
      );

      expect(alarm1, equals(alarm2));
      expect(alarm1, isNot(equals(alarm3)));
    });
  });
}
