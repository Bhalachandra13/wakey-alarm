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
  });
}
