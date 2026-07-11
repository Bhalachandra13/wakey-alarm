import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';

/// Bridges [Alarm] domain objects to the native [AlarmBridge].
///
/// Translates an [Alarm] into the primitive payload map the Kotlin side
/// expects, and decides when to schedule or cancel based on alarm state.
class AlarmScheduler {
  const AlarmScheduler(this._bridge);

  final AlarmBridge _bridge;

  /// Schedule a single enabled time-based alarm via the native AlarmManager.
  ///
  /// Only [AlarmTriggerType.time] alarms are forwarded here.
  /// Location-based alarms are handled by GeofencingClient (Iteration 4).
  Future<bool> scheduleAlarm(Alarm alarm) async {
    if (!alarm.isEnabled) return false;
    if (alarm.triggerType != AlarmTriggerType.time) return false;

    final id = alarm.id;
    final hour = alarm.timeHour;
    final minute = alarm.timeMinute;

    // Guard against missing required time fields – defensive check
    // rather than letting a null propagate into native code and crash.
    if (id == null || hour == null || minute == null) return false;

    final payload = <String, Object?>{
      'alarmId': id,
      'timeHour': hour,
      'timeMinute': minute,
      'repeatDays': alarm.repeatDays,
      'label': alarm.label,
      'soundUri': alarm.soundUri,
      'vibrate': alarm.vibrate,
      'snoozeDurationMin': alarm.snoozeDurationMin,
      'maxSnoozeCount': alarm.maxSnoozeCount,
    };

    return _bridge.scheduleAlarm(payload);
  }

  /// Cancel the native alarm for the given [alarmId].
  Future<bool> cancelAlarm(int alarmId) async {
    return _bridge.cancelAlarm(alarmId);
  }

  /// Re-schedule all enabled alarms from [alarms].
  ///
  /// The Kotlin [BootReceiver] handles boot re-scheduling natively.
  /// This method is for Dart-side re-sync (e.g. after a permission grant).
  Future<void> rescheduleAll(List<Alarm> alarms) async {
    for (final alarm in alarms) {
      if (alarm.isEnabled) {
        await scheduleAlarm(alarm);
      }
    }
  }
}
