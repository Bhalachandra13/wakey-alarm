import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/domain/geofence_validator.dart';
import 'package:wakey_alarm/native_bridge/geofence_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';

/// Coordinates the "Start Trip" arming flow for a single geofence
/// alarm. See `requirements.md` §5.5 for the full flow:
///
///  1. Check that foreground + background location permissions are
///     granted; surface a UI prompt otherwise.
///  2. Read the user's current location.
///  3. Compute the distance to the geofence center; if already
///     inside, surface a warning and *do not* arm the geofence.
///  4. Register the geofence with the native
///     `GeofencingClient` via the bridge.
///  5. Flip the alarm's `is_armed` flag in sqflite so the UI
///     reflects the new state.
///
/// The reverse (one-shot auto-disarm after the geofence fires and
/// the user dismisses) is handled in [AlarmsNotifier] via the
/// existing `dismissed` event subscription.
class GeofenceArmingController {
  const GeofenceArmingController(this._ref);

  final Ref _ref;

  GeofenceBridge get _bridge => _ref.read(geofenceBridgeProvider);

  /// Run the full arming flow for [alarm]. Returns an
  /// [ArmingResult] describing the outcome so the UI can show
  /// the right message.
  Future<ArmingResult> armAlarm(Alarm alarm) async {
    if (alarm.triggerType != AlarmTriggerType.location) {
      return const ArmingResult.invalidAlarm();
    }
    if (!GeofenceValidator.isAlarmValid(alarm)) {
      return const ArmingResult.invalidAlarm();
    }
    final alarmId = alarm.id;
    if (alarmId == null) {
      return const ArmingResult.invalidAlarm();
    }

    // 0. Already-armed guard. Calling armAlarm on a geofence that's
    // already registered would add a duplicate (the native
    // GeofencingClient replaces, but the replace path is not
    // guaranteed to update all metadata fields). Treat it as a
    // no-op success so the UI doesn't try to "arm" an already-armed
    // alarm and confuse the user.
    if (alarm.isArmed) {
      return const ArmingResult.alreadyArmed();
    }

    // 1. Permission check. The Dart UI is expected to have already
    // prompted the user via the permission flow before calling
    // `armAlarm`; we re-check here as a safety net.
    final perm = await _bridge.getPermissionStatus();
    if (perm != LocationPermissionStatus.grantedForegroundAndBackground) {
      return ArmingResult.permissionMissing(perm);
    }

    // 2. Current location. If we can't get a fix, fall back to
    // allowing the arm and letting the user discover the issue
    // empirically — refusing to arm on a transient location
    // failure would be more annoying than helpful.
    final here = await _bridge.getCurrentLocation();
    if (here != null) {
      // 3. Already-inside check. Compute the actual distance so the
      // UI can tell the user how far they are from the boundary.
      final distance = GeofenceValidator.distanceMeters(
        alarm.latitude!,
        alarm.longitude!,
        here.latitude,
        here.longitude,
      );
      if (distance <= alarm.radiusMeters!) {
        return ArmingResult.alreadyInside(distanceMeters: distance);
      }
    }

    // 4. Register the geofence. Pass the full alarm metadata so
    // the native side can persist it; the ringing UI and boot-time
    // re-arming need label/sound/vibrate/snooze even when the
    // Flutter engine is not running.
    final addResult = await _bridge.addGeofence(
      alarmId: alarmId,
      latitude: alarm.latitude!,
      longitude: alarm.longitude!,
      radiusMeters: alarm.radiusMeters!,
      label: alarm.label,
      soundUri: alarm.soundUri,
      vibrate: alarm.vibrate,
      snoozeDurationMin: alarm.snoozeDurationMin,
      maxSnoozeCount: alarm.maxSnoozeCount ?? -1,
    );
    if (!addResult.ok) {
      return ArmingResult.registrationFailed(message: addResult.error);
    }

    // 5. Flip the armed flag in the DB so the UI shows the
    // alarm as armed.
    final dao = _ref.read(alarmDaoProvider);
    await dao.updateArmed(alarmId, true);
    // Also touch updated_at via a no-op update so the list
    // refreshes; updateArmed already does this.
    _ref.invalidate(alarmsNotifierProvider);
    return const ArmingResult.armed();
  }

  /// Disarm a geofence alarm. Removes the native registration
  /// and flips the flag. Used by the "Stop Trip" button.
  Future<bool> disarmAlarm(Alarm alarm) async {
    if (alarm.triggerType != AlarmTriggerType.location) return false;
    final alarmId = alarm.id;
    if (alarmId == null) return false;
    await _bridge.removeGeofence(alarmId);
    final dao = _ref.read(alarmDaoProvider);
    await dao.updateArmed(alarmId, false);
    _ref.invalidate(alarmsNotifierProvider);
    return true;
  }
}

/// Result of an arming attempt. Encodes all the outcomes the UI
/// needs to render — no exceptions, no error strings. The
/// [message] field carries an optional human-readable detail for
/// the failure outcomes (notably [ArmingOutcome.registrationFailed])
/// so the UI can tell the user *why* the geofence could not be
/// armed instead of just saying "it failed".
class ArmingResult {
  const ArmingResult._({
    required this.outcome,
    this.permissionStatus,
    this.distanceMeters,
    this.message,
  });

  const ArmingResult.armed() : this._(outcome: ArmingOutcome.armed);

  const ArmingResult.alreadyInside({double? distanceMeters})
    : this._(
        outcome: ArmingOutcome.alreadyInside,
        distanceMeters: distanceMeters,
      );

  const ArmingResult.alreadyArmed() : this._(outcome: ArmingOutcome.alreadyArmed);

  const ArmingResult.registrationFailed({String? message})
    : this._(outcome: ArmingOutcome.registrationFailed, message: message);

  const ArmingResult.permissionMissing(LocationPermissionStatus status)
    : this._(
        outcome: ArmingOutcome.permissionMissing,
        permissionStatus: status,
      );

  const ArmingResult.invalidAlarm()
    : this._(outcome: ArmingOutcome.invalidAlarm);

  final ArmingOutcome outcome;
  final LocationPermissionStatus? permissionStatus;
  final double? distanceMeters;
  final String? message;
}

enum ArmingOutcome {
  armed,
  alreadyInside,
  alreadyArmed,
  registrationFailed,
  permissionMissing,
  invalidAlarm,
}

/// Provider for the arming controller. Stateless — call its
/// methods directly.
final geofenceArmingControllerProvider = Provider<GeofenceArmingController>(
  (ref) => GeofenceArmingController(ref),
);
