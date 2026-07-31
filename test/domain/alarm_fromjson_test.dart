import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/domain/alarm.dart';

void main() {
  group('Alarm.fromJson null-safety', () {
    // Regression: the previous implementation used `(json['is_enabled']
    // as int?) != 0` which returned `true` for a null column. The
    // schema marks these columns NOT NULL, but a defensive `== 1`
    // ensures a null reads as `false` (the safe default for an
    // "off" state).

    Alarm fromMap(Map<String, Object?> json) => Alarm.fromJson(json);

    test('isEnabled is false when column is null', () {
      final alarm = fromMap({
        'id': 1,
        'label': 'x',
        'trigger_type': 'TIME',
        'time_hour': 7,
        'time_minute': 0,
        'repeat_days': null,
        'latitude': null,
        'longitude': null,
        'radius_meters': null,
        'is_enabled': null,
        'is_armed': null,
        'sound_uri': '',
        'vibrate': null,
        'snooze_duration_min': 10,
        'max_snooze_count': null,
        'created_at': '2026-07-20T10:00:00Z',
        'updated_at': '2026-07-20T10:00:00Z',
      });
      expect(alarm.isEnabled, isFalse);
      expect(alarm.isArmed, isFalse);
      expect(alarm.vibrate, isFalse);
    });

    test('isEnabled is true when column is 1', () {
      final alarm = fromMap({
        'id': 1,
        'label': 'x',
        'trigger_type': 'TIME',
        'time_hour': 7,
        'time_minute': 0,
        'repeat_days': null,
        'latitude': null,
        'longitude': null,
        'radius_meters': null,
        'is_enabled': 1,
        'is_armed': 1,
        'sound_uri': '',
        'vibrate': 1,
        'snooze_duration_min': 10,
        'max_snooze_count': null,
        'created_at': '2026-07-20T10:00:00Z',
        'updated_at': '2026-07-20T10:00:00Z',
      });
      expect(alarm.isEnabled, isTrue);
      expect(alarm.isArmed, isTrue);
      expect(alarm.vibrate, isTrue);
    });

    test('isEnabled is false when column is 0', () {
      final alarm = fromMap({
        'id': 1,
        'label': 'x',
        'trigger_type': 'TIME',
        'time_hour': 7,
        'time_minute': 0,
        'repeat_days': null,
        'latitude': null,
        'longitude': null,
        'radius_meters': null,
        'is_enabled': 0,
        'is_armed': 0,
        'sound_uri': '',
        'vibrate': 0,
        'snooze_duration_min': 10,
        'max_snooze_count': null,
        'created_at': '2026-07-20T10:00:00Z',
        'updated_at': '2026-07-20T10:00:00Z',
      });
      expect(alarm.isEnabled, isFalse);
      expect(alarm.isArmed, isFalse);
      expect(alarm.vibrate, isFalse);
    });

    test('isEnabled is false for any non-1 integer (e.g. 2, -1)', () {
      // Defensive: the column is BOOLEAN stored as 0/1, but if a
      // future migration or a hand-edited row stores a different
      // integer, the parser should not treat it as true.
      for (final v in [2, -1, 100, 9999]) {
        final alarm = fromMap({
          'id': 1,
          'label': 'x',
          'trigger_type': 'TIME',
          'time_hour': 7,
          'time_minute': 0,
          'repeat_days': null,
          'latitude': null,
          'longitude': null,
          'radius_meters': null,
          'is_enabled': v,
          'is_armed': v,
          'sound_uri': '',
          'vibrate': v,
          'snooze_duration_min': 10,
          'max_snooze_count': null,
          'created_at': '2026-07-20T10:00:00Z',
          'updated_at': '2026-07-20T10:00:00Z',
        });
        expect(alarm.isEnabled, isFalse, reason: 'for v=$v');
        expect(alarm.isArmed, isFalse, reason: 'for v=$v');
        expect(alarm.vibrate, isFalse, reason: 'for v=$v');
      }
    });
  });

  group('Alarm toJson/fromJson round trip', () {
    test('preserves every field for a time alarm', () {
      const original = Alarm(
        id: 7,
        label: 'Wake up',
        triggerType: AlarmTriggerType.time,
        timeHour: 6,
        timeMinute: 45,
        repeatDays: 'MON,WED,FRI',
        isEnabled: true,
        isArmed: false,
        soundUri: 'content://x',
        vibrate: true,
        snoozeDurationMin: 15,
        maxSnoozeCount: 3,
        createdAt: '2026-07-01T00:00:00Z',
        updatedAt: '2026-07-02T00:00:00Z',
      );
      final restored = Alarm.fromJson(original.toJson());
      expect(restored, equals(original));
    });

    test('preserves every field for a location alarm', () {
      const original = Alarm(
        id: 9,
        label: 'Train stop',
        triggerType: AlarmTriggerType.location,
        latitude: 51.5074,
        longitude: -0.1278,
        radiusMeters: 2500,
        isEnabled: true,
        isArmed: true,
        soundUri: '',
        vibrate: false,
        snoozeDurationMin: 10,
        maxSnoozeCount: null,
        createdAt: '2026-07-01T00:00:00Z',
        updatedAt: '2026-07-02T00:00:00Z',
      );
      final restored = Alarm.fromJson(original.toJson());
      expect(restored, equals(original));
    });
  });

  group('Alarm.copyWith null-handling', () {
    // copyWith uses `?? this.field` so it can never set a field to
    // null explicitly. Document the behavior with a regression test
    // so a future refactor doesn't accidentally let `null` overwrite
    // a non-null value.

    const original = Alarm(
      label: 'x',
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

    test('passing null to copyWith leaves the field unchanged', () {
      final updated = original.copyWith(
        repeatDays: null,
        maxSnoozeCount: null,
      );
      expect(updated.repeatDays, original.repeatDays);
      expect(updated.maxSnoozeCount, original.maxSnoozeCount);
    });
  });
}
