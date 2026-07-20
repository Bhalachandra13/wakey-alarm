import 'package:flutter/foundation.dart';

/// The lifecycle states a [TimerRecord] can be in.
///
/// * [running] — counting down toward the fire time. `remainingSeconds`
///   is updated periodically by the Dart side for UI continuity.
/// * [paused] — frozen at `remainingSeconds`. Resuming continues from
///   that value.
/// * [completed] — fired and acknowledged by the user. Cleared from
///   the list by the next [TimersNotifier] refresh; kept in the DB
///   for the current session only.
/// * [cancelled] — cancelled by the user before firing. Cleared the
///   same way as [completed].
enum TimerState {
  running,
  paused,
  completed,
  cancelled;

  /// The string value stored in the `state` column. Kept uppercase to
  /// match the requirements.md §3.2 wording.
  String get value {
    switch (this) {
      case TimerState.running:
        return 'RUNNING';
      case TimerState.paused:
        return 'PAUSED';
      case TimerState.completed:
        return 'COMPLETED';
      case TimerState.cancelled:
        return 'CANCELLED';
    }
  }

  static TimerState fromValue(String value) {
    switch (value) {
      case 'RUNNING':
        return TimerState.running;
      case 'PAUSED':
        return TimerState.paused;
      case 'COMPLETED':
        return TimerState.completed;
      case 'CANCELLED':
        return TimerState.cancelled;
      default:
        throw ArgumentError('Unknown timer state: $value');
    }
  }
}

/// A countdown timer.
///
/// A timer's "fire time" is conceptually [startedAt] + [durationSeconds],
/// but the actual native schedule lives in the OS-level AlarmManager
/// (see `requirements.md` §5.4 — timers reuse the alarm pipeline). The
/// Dart side keeps [remainingSeconds] updated so the UI can show a
/// live countdown without round-tripping to the native side every
/// frame.
@immutable
class TimerRecord {
  const TimerRecord({
    this.id,
    required this.label,
    required this.durationSeconds,
    required this.remainingSeconds,
    required this.state,
    this.startedAt,
  });

  /// Auto-increment DB id. Null for a not-yet-inserted record.
  final int? id;

  /// User-facing label, e.g. "Boil eggs".
  final String label;

  /// The total duration the user originally set, in seconds. Immutable
  /// after creation — pause/resume only affect [remainingSeconds].
  final int durationSeconds;

  /// How much time is left as of the last DB write. For a
  /// [TimerState.running] timer this is the *persisted* value; the
  /// UI computes the live value as
  /// `(startedAt + durationSeconds) - now`. For a paused timer this
  /// is the exact value to show.
  final int remainingSeconds;

  final TimerState state;

  /// ISO 8601 timestamp of when the current run started, or null if
  /// the timer has never been started (shouldn't happen for
  /// user-visible timers, but defensively nullable per the schema).
  final String? startedAt;

  bool get isActive =>
      state == TimerState.running || state == TimerState.paused;

  TimerRecord copyWith({
    int? id,
    String? label,
    int? durationSeconds,
    int? remainingSeconds,
    TimerState? state,
    String? startedAt,
  }) {
    return TimerRecord(
      id: id ?? this.id,
      label: label ?? this.label,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      state: state ?? this.state,
      startedAt: startedAt ?? this.startedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'label': label,
      'duration_seconds': durationSeconds,
      'remaining_seconds': remainingSeconds,
      'state': state.value,
      'started_at': startedAt,
    };
  }

  factory TimerRecord.fromJson(Map<String, Object?> json) {
    return TimerRecord(
      id: json['id'] as int?,
      label: json['label'] as String,
      durationSeconds: json['duration_seconds'] as int,
      remainingSeconds: json['remaining_seconds'] as int,
      state: TimerState.fromValue(json['state'] as String),
      startedAt: json['started_at'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimerRecord &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label &&
          durationSeconds == other.durationSeconds &&
          remainingSeconds == other.remainingSeconds &&
          state == other.state &&
          startedAt == other.startedAt;

  @override
  int get hashCode => Object.hash(
    id,
    label,
    durationSeconds,
    remainingSeconds,
    state,
    startedAt,
  );

  @override
  String toString() =>
      'TimerRecord(id: $id, label: $label, '
      'remaining: ${remainingSeconds}s, state: ${state.value})';
}
