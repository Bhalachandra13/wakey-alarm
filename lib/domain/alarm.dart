import 'package:flutter/foundation.dart';

/// Represents an alarm in the system.
///
/// Supports both time-based and location-based triggers.
/// See requirements.md §3.1 for full specification.
@immutable
class Alarm {
  const Alarm({
    this.id,
    required this.label,
    required this.triggerType,
    this.timeHour,
    this.timeMinute,
    this.repeatDays,
    this.latitude,
    this.longitude,
    this.radiusMeters,
    required this.isEnabled,
    required this.isArmed,
    required this.soundUri,
    required this.vibrate,
    required this.snoozeDurationMin,
    this.maxSnoozeCount,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Unique identifier (auto-increment from DB).
  final int? id;

  /// User-facing name, e.g. "Wake up" or "Get off train".
  final String label;

  /// Either [AlarmTriggerType.time] or [AlarmTriggerType.location].
  final AlarmTriggerType triggerType;

  /// Hour of day (0–23) for time-based alarms. Null for location alarms.
  final int? timeHour;

  /// Minute (0–59) for time-based alarms. Null for location alarms.
  final int? timeMinute;

  /// Comma-separated weekdays, e.g. "MON,TUE,WED", or null for one-time.
  final String? repeatDays;

  /// Latitude for location-based alarms. Null for time alarms.
  final double? latitude;

  /// Longitude for location-based alarms. Null for time alarms.
  final double? longitude;

  /// Radius in meters (200–20,000) for location-based alarms. Null for time alarms.
  final int? radiusMeters;

  /// Master on/off toggle.
  final bool isEnabled;

  /// Relevant only to location alarms; tracks whether geofence is registered.
  final bool isArmed;

  /// URI of the selected alarm tone.
  final String soundUri;

  /// Whether to vibrate when alarm fires.
  final bool vibrate;

  /// Default snooze duration in minutes (e.g. 5 or 10).
  final int snoozeDurationMin;

  /// Maximum number of times the alarm can be snoozed, or null for unlimited.
  final int? maxSnoozeCount;

  /// ISO 8601 timestamp when the alarm was created.
  final String createdAt;

  /// ISO 8601 timestamp of the last update.
  final String updatedAt;

  /// Returns a copy of this alarm with the specified fields replaced.
  Alarm copyWith({
    int? id,
    String? label,
    AlarmTriggerType? triggerType,
    int? timeHour,
    int? timeMinute,
    String? repeatDays,
    double? latitude,
    double? longitude,
    int? radiusMeters,
    bool? isEnabled,
    bool? isArmed,
    String? soundUri,
    bool? vibrate,
    int? snoozeDurationMin,
    int? maxSnoozeCount,
    String? createdAt,
    String? updatedAt,
  }) {
    return Alarm(
      id: id ?? this.id,
      label: label ?? this.label,
      triggerType: triggerType ?? this.triggerType,
      timeHour: timeHour ?? this.timeHour,
      timeMinute: timeMinute ?? this.timeMinute,
      repeatDays: repeatDays ?? this.repeatDays,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      isEnabled: isEnabled ?? this.isEnabled,
      isArmed: isArmed ?? this.isArmed,
      soundUri: soundUri ?? this.soundUri,
      vibrate: vibrate ?? this.vibrate,
      snoozeDurationMin: snoozeDurationMin ?? this.snoozeDurationMin,
      maxSnoozeCount: maxSnoozeCount ?? this.maxSnoozeCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Converts this alarm to a JSON map for DB storage or transmission.
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'label': label,
      'trigger_type': triggerType.value,
      'time_hour': timeHour,
      'time_minute': timeMinute,
      'repeat_days': repeatDays,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
      'is_enabled': isEnabled ? 1 : 0,
      'is_armed': isArmed ? 1 : 0,
      'sound_uri': soundUri,
      'vibrate': vibrate ? 1 : 0,
      'snooze_duration_min': snoozeDurationMin,
      'max_snooze_count': maxSnoozeCount,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// Creates an alarm from a JSON map (e.g., from DB row).
  factory Alarm.fromJson(Map<String, Object?> json) {
    return Alarm(
      id: json['id'] as int?,
      label: json['label'] as String,
      triggerType: AlarmTriggerType.fromValue(json['trigger_type'] as String),
      timeHour: json['time_hour'] as int?,
      timeMinute: json['time_minute'] as int?,
      repeatDays: json['repeat_days'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      radiusMeters: json['radius_meters'] as int?,
      isEnabled: (json['is_enabled'] as int?) != 0,
      isArmed: (json['is_armed'] as int?) != 0,
      soundUri: json['sound_uri'] as String,
      vibrate: (json['vibrate'] as int?) != 0,
      snoozeDurationMin: json['snooze_duration_min'] as int,
      maxSnoozeCount: json['max_snooze_count'] as int?,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Alarm &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label &&
          triggerType == other.triggerType &&
          timeHour == other.timeHour &&
          timeMinute == other.timeMinute &&
          repeatDays == other.repeatDays &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          radiusMeters == other.radiusMeters &&
          isEnabled == other.isEnabled &&
          isArmed == other.isArmed &&
          soundUri == other.soundUri &&
          vibrate == other.vibrate &&
          snoozeDurationMin == other.snoozeDurationMin &&
          maxSnoozeCount == other.maxSnoozeCount &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      label.hashCode ^
      triggerType.hashCode ^
      timeHour.hashCode ^
      timeMinute.hashCode ^
      repeatDays.hashCode ^
      latitude.hashCode ^
      longitude.hashCode ^
      radiusMeters.hashCode ^
      isEnabled.hashCode ^
      isArmed.hashCode ^
      soundUri.hashCode ^
      vibrate.hashCode ^
      snoozeDurationMin.hashCode ^
      maxSnoozeCount.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode;

  @override
  String toString() {
    return 'Alarm(id: $id, label: $label, triggerType: $triggerType, '
        'enabled: $isEnabled, armed: $isArmed)';
  }
}

/// Enumerates the types of alarm triggers.
enum AlarmTriggerType {
  /// Time-based alarm (wall-clock time).
  time('TIME'),

  /// Location-based alarm (geofence).
  location('LOCATION');

  const AlarmTriggerType(this.value);

  /// The string value used in the database.
  final String value;

  /// Parses a string value to an [AlarmTriggerType].
  /// Throws [ArgumentError] if the value is not recognized.
  static AlarmTriggerType fromValue(String value) {
    switch (value) {
      case 'TIME':
        return AlarmTriggerType.time;
      case 'LOCATION':
        return AlarmTriggerType.location;
      default:
        throw ArgumentError('Unknown trigger type: $value');
    }
  }
}
