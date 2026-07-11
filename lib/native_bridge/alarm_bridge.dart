import 'package:flutter/services.dart';

class AlarmBridge {
  const AlarmBridge({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_methodName),
      _eventChannel = eventChannel ?? const EventChannel(_eventName);

  static const _methodName = 'com.wakeywakey/alarm_bridge';
  static const _eventName = 'com.wakeywakey/alarm_events';

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  /// Stream of native alarm lifecycle events.
  ///
  /// Emits [AlarmEvent]s of type
  /// [AlarmEventType.fired] when an alarm starts ringing,
  /// [AlarmEventType.snoozed] when the user taps snooze, and
  /// [AlarmEventType.dismissed] when the user taps dismiss.
  ///
  /// The stream has no listener by default — Flutter will only
  /// see events when something is actively subscribed. The OS may
  /// cold-start the app to deliver an alarm fire, in which case
  /// there is no Dart isolate listening yet and the native side
  /// drops the event (which is fine, because nothing would have
  /// been able to render it anyway).
  Stream<AlarmEvent> get alarmEvents {
    return _eventChannel.receiveBroadcastStream().map(AlarmEvent.fromMap);
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

/// Discriminator for [AlarmEvent]. Matches the `type` strings
/// emitted by the Kotlin side (see `RingingActivity.emitOutcome`
/// and the alarm-receiver self-reschedule path).
enum AlarmEventType {
  fired,
  snoozed,
  dismissed;

  static AlarmEventType fromName(String name) {
    return AlarmEventType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => AlarmEventType.fired,
    );
  }
}

/// A native alarm lifecycle event.
///
/// * For [AlarmEventType.fired], [triggerType] is one of
///   `"time"` or `"location"` (mirroring `AlarmTriggerType`).
/// * For [AlarmEventType.snoozed] and [AlarmEventType.dismissed],
///   [triggerType] is null — the alarm has already finished
///   ringing and the trigger type is no longer relevant.
class AlarmEvent {
  const AlarmEvent({
    required this.alarmId,
    required this.type,
    this.triggerType,
  });

  factory AlarmEvent.fromMap(Object? value) {
    final map = Map<Object?, Object?>.from(value! as Map<Object?, Object?>);
    return AlarmEvent(
      alarmId: map['alarmId']! as int,
      type: AlarmEventType.fromName(map['type']! as String),
      triggerType: map['triggerType'] as String?,
    );
  }

  final int alarmId;
  final AlarmEventType type;
  final String? triggerType;

  @override
  String toString() =>
      'AlarmEvent(alarmId: $alarmId, type: ${type.name}, '
      'triggerType: $triggerType)';
}
