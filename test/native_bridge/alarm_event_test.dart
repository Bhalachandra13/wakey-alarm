import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';

void main() {
  group('AlarmEventType', () {
    test('fromName returns the matching enum value', () {
      expect(AlarmEventType.fromName('fired'), AlarmEventType.fired);
      expect(AlarmEventType.fromName('snoozed'), AlarmEventType.snoozed);
      expect(AlarmEventType.fromName('dismissed'), AlarmEventType.dismissed);
    });

    test('fromName falls back to fired for unknown names', () {
      expect(AlarmEventType.fromName('unknown'), AlarmEventType.fired);
      expect(AlarmEventType.fromName(''), AlarmEventType.fired);
    });
  });

  group('AlarmEvent.fromMap', () {
    test('parses a fired event with a time trigger type', () {
      final event = AlarmEvent.fromMap(<String, Object?>{
        'alarmId': 42,
        'type': 'fired',
        'triggerType': 'time',
      });
      expect(event.alarmId, 42);
      expect(event.type, AlarmEventType.fired);
      expect(event.triggerType, 'time');
    });

    test('parses a fired event with a location trigger type', () {
      final event = AlarmEvent.fromMap(<String, Object?>{
        'alarmId': 7,
        'type': 'fired',
        'triggerType': 'location',
      });
      expect(event.alarmId, 7);
      expect(event.type, AlarmEventType.fired);
      expect(event.triggerType, 'location');
    });

    test('parses a snoozed event with no trigger type', () {
      final event = AlarmEvent.fromMap(<String, Object?>{
        'alarmId': 5,
        'type': 'snoozed',
      });
      expect(event.alarmId, 5);
      expect(event.type, AlarmEventType.snoozed);
      expect(event.triggerType, isNull);
    });

    test('parses a dismissed event with no trigger type', () {
      final event = AlarmEvent.fromMap(<String, Object?>{
        'alarmId': 5,
        'type': 'dismissed',
      });
      expect(event.alarmId, 5);
      expect(event.type, AlarmEventType.dismissed);
      expect(event.triggerType, isNull);
    });

    test('toString includes the type and alarmId', () {
      final event = AlarmEvent.fromMap(<String, Object?>{
        'alarmId': 5,
        'type': 'dismissed',
      });
      expect(event.toString(), contains('alarmId: 5'));
      expect(event.toString(), contains('dismissed'));
    });

    test('coerces alarmId from a long (Int64) sent over the channel', () {
      // The StandardMethodCodec can hand us back a `num` even when
      // the Kotlin side put an `int`. We should not crash.
      final event = AlarmEvent.fromMap(<String, Object?>{
        'alarmId': 42.0, // double, simulates a coerced int
        'type': 'fired',
        'triggerType': 'time',
      });
      expect(event.alarmId, 42);
    });

    test('coerces alarmId from a numeric string', () {
      final event = AlarmEvent.fromMap(<String, Object?>{
        'alarmId': '17',
        'type': 'fired',
      });
      expect(event.alarmId, 17);
    });

    test('throws a clear FormatException for a non-coercible alarmId', () {
      expect(
        () => AlarmEvent.fromMap(<String, Object?>{
          'alarmId': 'not-a-number',
          'type': 'fired',
        }),
        throwsFormatException,
      );
    });

    test('throws a clear FormatException for a missing alarmId', () {
      expect(
        () => AlarmEvent.fromMap(<String, Object?>{'type': 'fired'}),
        throwsFormatException,
      );
    });
  });
}
