import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/domain/timer_record.dart';

void main() {
  group('TimerRecord', () {
    test('constructs with required fields', () {
      final now = DateTime.now().toIso8601String();
      const record = TimerRecord(
        id: 1,
        label: 'Boil eggs',
        durationSeconds: 480,
        remainingSeconds: 480,
        state: TimerState.running,
        startedAt: '2026-07-20T10:00:00Z',
      );
      expect(record.id, 1);
      expect(record.label, 'Boil eggs');
      expect(record.durationSeconds, 480);
      expect(record.remainingSeconds, 480);
      expect(record.state, TimerState.running);
      // ignore: unused_local_variable
      final _ = now; // just to keep the variable for a future use
    });

    test('isActive is true for RUNNING and PAUSED, false otherwise', () {
      const running = TimerRecord(
        label: 'a',
        durationSeconds: 60,
        remainingSeconds: 60,
        state: TimerState.running,
      );
      const paused = TimerRecord(
        label: 'a',
        durationSeconds: 60,
        remainingSeconds: 30,
        state: TimerState.paused,
      );
      const completed = TimerRecord(
        label: 'a',
        durationSeconds: 60,
        remainingSeconds: 0,
        state: TimerState.completed,
      );
      const cancelled = TimerRecord(
        label: 'a',
        durationSeconds: 60,
        remainingSeconds: 60,
        state: TimerState.cancelled,
      );
      expect(running.isActive, isTrue);
      expect(paused.isActive, isTrue);
      expect(completed.isActive, isFalse);
      expect(cancelled.isActive, isFalse);
    });

    test('toJson / fromJson round trip', () {
      const original = TimerRecord(
        id: 7,
        label: 'Workout',
        durationSeconds: 1500,
        remainingSeconds: 1500,
        state: TimerState.paused,
        startedAt: '2026-07-20T10:00:00Z',
      );
      final json = original.toJson();
      expect(json['id'], 7);
      expect(json['label'], 'Workout');
      expect(json['duration_seconds'], 1500);
      expect(json['remaining_seconds'], 1500);
      expect(json['state'], 'PAUSED');
      expect(json['started_at'], '2026-07-20T10:00:00Z');

      final restored = TimerRecord.fromJson(json);
      expect(restored, equals(original));
    });

    test('copyWith updates only the named fields', () {
      const original = TimerRecord(
        id: 1,
        label: 'Lunch',
        durationSeconds: 1800,
        remainingSeconds: 1800,
        state: TimerState.running,
        startedAt: '2026-07-20T10:00:00Z',
      );
      final updated = original.copyWith(remainingSeconds: 600);
      expect(updated.remainingSeconds, 600);
      expect(updated.label, 'Lunch');
      expect(updated.durationSeconds, 1800);
      expect(updated.state, TimerState.running);
    });

    test('equality is value-based', () {
      const a = TimerRecord(
        id: 1,
        label: 'A',
        durationSeconds: 60,
        remainingSeconds: 60,
        state: TimerState.running,
      );
      const b = TimerRecord(
        id: 1,
        label: 'A',
        durationSeconds: 60,
        remainingSeconds: 60,
        state: TimerState.running,
      );
      const c = TimerRecord(
        id: 2,
        label: 'A',
        durationSeconds: 60,
        remainingSeconds: 60,
        state: TimerState.running,
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('snoozeDurationMin defaults to defaultSnoozeDurationMin', () {
      const record = TimerRecord(
        label: 'Lunch',
        durationSeconds: 1800,
        remainingSeconds: 1800,
        state: TimerState.running,
      );
      expect(record.snoozeDurationMin, TimerRecord.defaultSnoozeDurationMin);
    });

    test('toJson / fromJson round trip includes snoozeDurationMin', () {
      const original = TimerRecord(
        id: 7,
        label: 'Workout',
        durationSeconds: 1500,
        remainingSeconds: 1500,
        state: TimerState.paused,
        startedAt: '2026-07-20T10:00:00Z',
        snoozeDurationMin: 12,
      );
      final json = original.toJson();
      expect(json['snooze_duration_min'], 12);

      final restored = TimerRecord.fromJson(json);
      expect(restored.snoozeDurationMin, 12);
      expect(restored, equals(original));
    });

    test('fromJson falls back to default for legacy v1 rows', () {
      // Pre-v2 timers table has no snooze_duration_min column.
      // The fromJson path should still produce a usable record.
      final legacy = <String, Object?>{
        'id': 1,
        'label': 'Legacy',
        'duration_seconds': 60,
        'remaining_seconds': 30,
        'state': 'PAUSED',
        'started_at': null,
      };
      final restored = TimerRecord.fromJson(legacy);
      expect(restored.snoozeDurationMin, TimerRecord.defaultSnoozeDurationMin);
    });

    test('copyWith updates snoozeDurationMin without touching other fields', () {
      const original = TimerRecord(
        id: 1,
        label: 'Lunch',
        durationSeconds: 1800,
        remainingSeconds: 1800,
        state: TimerState.running,
        startedAt: '2026-07-20T10:00:00Z',
        snoozeDurationMin: 5,
      );
      final updated = original.copyWith(snoozeDurationMin: 15);
      expect(updated.snoozeDurationMin, 15);
      expect(updated.label, 'Lunch');
      expect(updated.state, TimerState.running);
    });
  });

  group('TimerState', () {
    test('value matches the canonical uppercase string', () {
      expect(TimerState.running.value, 'RUNNING');
      expect(TimerState.paused.value, 'PAUSED');
      expect(TimerState.completed.value, 'COMPLETED');
      expect(TimerState.cancelled.value, 'CANCELLED');
    });

    test('fromValue parses the canonical strings', () {
      expect(TimerState.fromValue('RUNNING'), TimerState.running);
      expect(TimerState.fromValue('PAUSED'), TimerState.paused);
      expect(TimerState.fromValue('COMPLETED'), TimerState.completed);
      expect(TimerState.fromValue('CANCELLED'), TimerState.cancelled);
    });

    test('fromValue throws on unknown value', () {
      expect(() => TimerState.fromValue('UNKNOWN'), throwsArgumentError);
    });
  });
}
