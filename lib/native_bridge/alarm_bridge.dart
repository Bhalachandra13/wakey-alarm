import 'package:flutter/services.dart';

class AlarmBridge {
  AlarmBridge({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_methodName),
      _eventChannel = eventChannel ?? const EventChannel(_eventName);

  static const _methodName = 'com.wakeywakey/alarm_bridge';
  static const _eventName = 'com.wakeywakey/alarm_events';

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  Stream<AlarmFiredEvent> get alarmFiredEvents {
    return _eventChannel.receiveBroadcastStream().map(AlarmFiredEvent.fromMap);
  }

  Future<bool> scheduleAlarm(Map<String, Object?> payload) async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
      'scheduleAlarm',
      payload,
    );
    return result?['scheduled'] == true;
  }

  Future<bool> cancelAlarm(int alarmId) async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
      'cancelAlarm',
      <String, Object?>{'alarmId': alarmId},
    );
    return result?['cancelled'] == true;
  }
}

class AlarmFiredEvent {
  const AlarmFiredEvent({required this.alarmId, required this.triggerType});

  factory AlarmFiredEvent.fromMap(Object? value) {
    final map = Map<Object?, Object?>.from(value! as Map<Object?, Object?>);
    return AlarmFiredEvent(
      alarmId: map['alarmId']! as int,
      triggerType: map['triggerType']! as String,
    );
  }

  final int alarmId;
  final String triggerType;
}
