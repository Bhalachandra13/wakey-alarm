import 'dart:math' as math;

import 'package:wakey_alarm/domain/alarm.dart';

/// Validation + geometry helpers for location-based alarms.
///
/// Pure functions — no I/O, no Riverpod, no native calls. Everything
/// here is unit-testable in isolation and used by the geofence
/// arming flow, the radius selector UI, and the in-app health check
/// banner.
class GeofenceValidator {
  /// Lower bound on the geofence radius, in meters. Below this,
  /// Android's native geofence accuracy of ~100–150 m makes the
  /// alarm unreliable — the user can be at the boundary and the
  /// device still reports them outside, or vice versa. See
  /// `requirements.md` §5.5.
  static const int minRadiusMeters = 200;

  /// Upper bound on the geofence radius, in meters. Android's
  /// GeofencingClient doesn't enforce this, but practical UX
  /// considerations do — 20 km is far enough for "wake me up before
  /// I get to X" use cases without crossing into "I want a
  /// city-scale alarm" territory.
  static const int maxRadiusMeters = 20000;

  /// Default radius if the user doesn't pick one.
  static const int defaultRadiusMeters = 2000;

  /// Earth radius in meters — used by [distanceMeters] for the
  /// Haversine formula. Mean Earth radius per IUGG.
  static const double earthRadiusMeters = 6371000;

  /// Returns `true` if [meters] is within the allowed
  /// [minRadiusMeters]–[maxRadiusMeters] range. The boundary values
  /// are themselves valid.
  static bool isRadiusInBounds(int meters) {
    return meters >= minRadiusMeters && meters <= maxRadiusMeters;
  }

  /// Throws [ArgumentError] if [meters] is out of the allowed
  /// radius range. Returns [meters] otherwise — useful for fluent
  /// validation in the geofence creation path.
  static int requireRadiusInBounds(int meters) {
    if (!isRadiusInBounds(meters)) {
      throw ArgumentError(
        'Geofence radius $meters m is out of the allowed range '
        '[$minRadiusMeters m, $maxRadiusMeters m]',
      );
    }
    return meters;
  }

  /// Returns `true` if [latitude] and [longitude] are valid WGS-84
  /// coordinates. Latitudes outside ±90° and longitudes outside
  /// ±180° are obviously invalid; we also reject NaN and infinite
  /// values, which can sneak in from a misbehaving map widget.
  static bool isCoordinateValid(double latitude, double longitude) {
    if (latitude.isNaN ||
        latitude.isInfinite ||
        longitude.isNaN ||
        longitude.isInfinite) {
      return false;
    }
    if (latitude < -90.0 || latitude > 90.0) return false;
    if (longitude < -180.0 || longitude > 180.0) return false;
    return true;
  }

  /// Returns `true` if [alarm] is structurally a valid location
  /// alarm — i.e. it has a `LOCATION` trigger, valid coordinates,
  /// and a radius in bounds. This is a *static* check; it does not
  /// compare the alarm to the user's current location.
  static bool isAlarmValid(Alarm alarm) {
    if (alarm.triggerType != AlarmTriggerType.location) return false;
    final lat = alarm.latitude;
    final lon = alarm.longitude;
    final radius = alarm.radiusMeters;
    if (lat == null || lon == null || radius == null) return false;
    if (!isCoordinateValid(lat, lon)) return false;
    if (!isRadiusInBounds(radius)) return false;
    return true;
  }

  /// Great-circle distance between two lat/long points, in meters,
  /// via the Haversine formula. Used by the "Start Trip" arming
  /// check to decide whether the user is already inside the
  /// geofence radius.
  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final phi1 = _toRadians(lat1);
    final phi2 = _toRadians(lat2);
    final dPhi = _toRadians(lat2 - lat1);
    final dLambda = _toRadians(lon2 - lon1);
    final sinHalfPhi = math.sin(dPhi / 2);
    final sinHalfLambda = math.sin(dLambda / 2);
    final a =
        sinHalfPhi * sinHalfPhi +
        math.cos(phi1) * math.cos(phi2) * sinHalfLambda * sinHalfLambda;
    // Clamp `a` to the valid range [0, 1]. Floating-point rounding can
    // push it slightly outside (notably for antipodal points, where
    // the true value is exactly 1), which would make `sqrt(1 - a)`
    // return NaN. Clamping keeps the result finite and well-defined.
    final clampedA = a < 0.0 ? 0.0 : (a > 1.0 ? 1.0 : a);
    final c = 2 * math.atan2(math.sqrt(clampedA), math.sqrt(1 - clampedA));
    return earthRadiusMeters * c;
  }

  /// True if [point] is inside the circle of [radiusMeters] centered
  /// at [centerLat]/[centerLon]. Used by the arming flow to warn
  /// the user when they are already within the geofence's radius.
  static bool isPointInsideGeofence({
    required double centerLat,
    required double centerLon,
    required double pointLat,
    required double pointLon,
    required int radiusMeters,
  }) {
    final d = distanceMeters(centerLat, centerLon, pointLat, pointLon);
    return d <= radiusMeters;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180.0;
}
