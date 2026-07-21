import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Status of the location permissions the geofence feature needs.
///
/// Background location is a *separate* runtime permission from
/// foreground on Android 10+ — the user has to grant foreground
/// first, then be sent to a system Settings page to grant
/// background. The flow is described in `requirements.md` §4 and
/// is implemented in the [requestBackgroundLocation] call below.
enum LocationPermissionStatus {
  /// Foreground (or, on pre-Android 10, all) location permission
  /// has been granted. The user has *not* yet granted the
  /// background-only permission, which is required for
  /// geofence-triggered alarms to fire when the app is killed.
  grantedForegroundOnly,

  /// Foreground + background location are both granted. Geofences
  /// can be armed and will trigger when the app is in the
  /// background or killed.
  grantedForegroundAndBackground,

  /// The user has denied the location permission request (or it
  /// is permanently denied on Android 11+ after multiple
  /// declines). The geofence feature will not work; the UI should
  /// show a prominent explanation and a button to open Settings.
  denied,

  /// Pre-Android 10 (API 28 and lower). Location is requested via
  /// a single permission, so foreground/background are
  /// indistinguishable. The native side reports this and the UI
  /// can skip the explanation screen.
  notRequired,
}

/// Dart-side wrapper for the native location / geofence pipeline.
///
/// All methods are *best-effort*: they forward to the native side
/// via [MethodChannel] and translate the response. Callers (notably
/// the [LocationPermissionNotifier] and the geofence arming flow)
/// are responsible for surfacing errors to the user.
class GeofenceBridge {
  GeofenceBridge({MethodChannel? methodChannel})
    : _methodChannel =
          methodChannel ?? const MethodChannel('com.wakeywakey/geofence');

  final MethodChannel _methodChannel;

  /// Returns the current foreground/background location permission
  /// state as reported by the native side.
  Future<LocationPermissionStatus> getPermissionStatus() async {
    final result = await _methodChannel.invokeMethod<String>(
      'getLocationPermissionStatus',
    );
    return _parseStatus(result);
  }

  /// Requests the foreground location permission. On Android 10+
  /// this is the first of two steps — the user must additionally
  /// grant the background permission via a system Settings page.
  /// Returns the new permission status after the request.
  ///
  /// No-op on pre-Android 10 — there is no separate foreground
  /// permission to grant (the single location permission covers
  /// both); the native side returns `notRequired` in that case.
  Future<LocationPermissionStatus> requestForegroundLocation() async {
    final result = await _methodChannel.invokeMethod<String>(
      'requestForegroundLocation',
    );
    return _parseStatus(result);
  }

  /// Opens the system Settings page for the app so the user can
  /// grant the "Allow all the time" background location permission.
  /// Returns the new permission status after the user (potentially)
  /// grants it.
  Future<LocationPermissionStatus> requestBackgroundLocation() async {
    final result = await _methodChannel.invokeMethod<String>(
      'requestBackgroundLocation',
    );
    return _parseStatus(result);
  }

  /// Returns the device's current location, or `null` if it could
  /// not be determined (e.g. permission denied, location services
  /// off, no fix yet). Times out after [timeout] on the native
  /// side.
  Future<GeoPoint?> getCurrentLocation({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
      'getCurrentLocation',
      <String, Object?>{'timeoutMs': timeout.inMilliseconds},
    );
    if (result == null) return null;
    final lat = (result['latitude'] as num?)?.toDouble();
    final lon = (result['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    return GeoPoint(latitude: lat, longitude: lon);
  }

  /// Registers a geofence with the native [GeofencingClient]. The
  /// alarm will fire when the user enters the circle of
  /// [radiusMeters] around ([latitude], [longitude]).
  ///
  /// [expirationMillis] is forwarded to the native side; pass
  /// `Geofence.NEVER_EXPIRE` (`Long.MAX_VALUE` in Java) for an
  /// open-ended registration. We default to NEVER_EXPIRE here
  /// because the user's expectation of a one-shot geofence alarm
  /// ("wake me up when I get to X") is that it stays armed until
  /// they disarm it.
  Future<bool> addGeofence({
    required int alarmId,
    required double latitude,
    required double longitude,
    required int radiusMeters,
    int expirationMillis = -1, // -1 == NEVER_EXPIRE on the native side
  }) async {
    final result = await _methodChannel
        .invokeMapMethod<String, Object?>('addGeofence', <String, Object?>{
          'alarmId': alarmId,
          'latitude': latitude,
          'longitude': longitude,
          'radiusMeters': radiusMeters,
          'expirationMillis': expirationMillis,
        });
    return result?['added'] == true;
  }

  /// Removes a previously-registered geofence. Idempotent — calling
  /// it for an alarmId that isn't registered is a no-op.
  Future<bool> removeGeofence(int alarmId) async {
    final result = await _methodChannel.invokeMapMethod<String, Object?>(
      'removeGeofence',
      <String, Object?>{'alarmId': alarmId},
    );
    return result?['removed'] == true;
  }

  /// Returns `true` if the app is currently exempt from battery
  /// optimization (i.e. the user has added it to the "Don't
  /// optimize" list). When `false`, geofence deliveries may be
  /// suppressed by the OEM's battery killer.
  Future<bool> isBatteryOptimizationExempt() async {
    final result = await _methodChannel.invokeMethod<bool>(
      'isBatteryOptimizationExempt',
    );
    return result ?? false;
  }

  /// Opens the system Settings page for the user to add this app
  /// to the battery optimization exemption list. The result is the
  /// new exemption state.
  Future<bool> requestBatteryOptimizationExemption() async {
    final result = await _methodChannel.invokeMethod<bool>(
      'requestBatteryOptimizationExemption',
    );
    return result ?? false;
  }

  LocationPermissionStatus _parseStatus(String? native) {
    switch (native) {
      case 'granted_foreground_only':
        return LocationPermissionStatus.grantedForegroundOnly;
      case 'granted_foreground_and_background':
        return LocationPermissionStatus.grantedForegroundAndBackground;
      case 'denied':
        return LocationPermissionStatus.denied;
      case 'not_required':
        return LocationPermissionStatus.notRequired;
      default:
        return LocationPermissionStatus.denied;
    }
  }
}

/// A simple latitude/longitude pair.
class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  String toString() => 'GeoPoint($latitude, $longitude)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoPoint &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// Singleton bridge provider. Override in tests with a fake.
final geofenceBridgeProvider = Provider<GeofenceBridge>((ref) {
  return GeofenceBridge();
});
