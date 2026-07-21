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
      // 3. Already-inside check.
      final inside = GeofenceValidator.isPointInsideGeofence(
        centerLat: alarm.latitude!,
        centerLon: alarm.longitude!,
        pointLat: here.latitude,
        pointLon: here.longitude,
        radiusMeters: alarm.radiusMeters!,
      );
      if (inside) {
        return ArmingResult.alreadyInside(distanceMeters: null);
      }
    }

    // 4. Register the geofence.
    final added = await _bridge.addGeofence(
      alarmId: alarmId,
      latitude: alarm.latitude!,
      longitude: alarm.longitude!,
      radiusMeters: alarm.radiusMeters!,
    );
    if (!added) {
      return const ArmingResult.registrationFailed();
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
/// needs to render — no exceptions, no error strings.
class ArmingResult {
  const ArmingResult._({
    required this.outcome,
    this.permissionStatus,
    this.distanceMeters,
  });

  const ArmingResult.armed() : this._(outcome: ArmingOutcome.armed);

  const ArmingResult.alreadyInside({double? distanceMeters})
    : this._(
        outcome: ArmingOutcome.alreadyInside,
        distanceMeters: distanceMeters,
      );

  const ArmingResult.registrationFailed()
    : this._(outcome: ArmingOutcome.registrationFailed);

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
}

enum ArmingOutcome {
  armed,
  alreadyInside,
  registrationFailed,
  permissionMissing,
  invalidAlarm,
}

/// Provider for the arming controller. Stateless — call its
/// methods directly.
final geofenceArmingControllerProvider = Provider<GeofenceArmingController>(
  (ref) => GeofenceArmingController(ref),
);
