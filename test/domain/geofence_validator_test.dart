import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/domain/geofence_validator.dart';

void main() {
  group('GeofenceValidator.isRadiusInBounds', () {
    test('accepts the lower bound', () {
      expect(GeofenceValidator.isRadiusInBounds(200), isTrue);
    });

    test('accepts the upper bound', () {
      expect(GeofenceValidator.isRadiusInBounds(20000), isTrue);
    });

    test('accepts values in the middle', () {
      expect(GeofenceValidator.isRadiusInBounds(2000), isTrue);
    });

    test('rejects values below the lower bound', () {
      expect(GeofenceValidator.isRadiusInBounds(199), isFalse);
      expect(GeofenceValidator.isRadiusInBounds(0), isFalse);
    });

    test('rejects values above the upper bound', () {
      expect(GeofenceValidator.isRadiusInBounds(20001), isFalse);
      expect(GeofenceValidator.isRadiusInBounds(1000000), isFalse);
    });
  });

  group('GeofenceValidator.requireRadiusInBounds', () {
    test('returns the radius when in bounds', () {
      expect(GeofenceValidator.requireRadiusInBounds(2000), 2000);
    });

    test('throws ArgumentError when out of bounds', () {
      expect(
        () => GeofenceValidator.requireRadiusInBounds(100),
        throwsArgumentError,
      );
      expect(
        () => GeofenceValidator.requireRadiusInBounds(50000),
        throwsArgumentError,
      );
    });
  });

  group('GeofenceValidator.isCoordinateValid', () {
    test('accepts coordinates within range', () {
      expect(GeofenceValidator.isCoordinateValid(0, 0), isTrue);
      expect(GeofenceValidator.isCoordinateValid(51.5074, -0.1278), isTrue);
      expect(GeofenceValidator.isCoordinateValid(90, 180), isTrue);
      expect(GeofenceValidator.isCoordinateValid(-90, -180), isTrue);
    });

    test('rejects latitudes out of range', () {
      expect(GeofenceValidator.isCoordinateValid(91, 0), isFalse);
      expect(GeofenceValidator.isCoordinateValid(-91, 0), isFalse);
    });

    test('rejects longitudes out of range', () {
      expect(GeofenceValidator.isCoordinateValid(0, 181), isFalse);
      expect(GeofenceValidator.isCoordinateValid(0, -181), isFalse);
    });

    test('rejects NaN and infinite values', () {
      expect(GeofenceValidator.isCoordinateValid(double.nan, 0), isFalse);
      expect(GeofenceValidator.isCoordinateValid(0, double.nan), isFalse);
      expect(GeofenceValidator.isCoordinateValid(double.infinity, 0), isFalse);
      expect(
        GeofenceValidator.isCoordinateValid(0, double.negativeInfinity),
        isFalse,
      );
    });
  });

  group('GeofenceValidator.isAlarmValid', () {
    Alarm makeAlarm({
      AlarmTriggerType triggerType = AlarmTriggerType.location,
      double? latitude,
      double? longitude,
      int? radiusMeters,
    }) {
      return Alarm(
        label: 'Test',
        triggerType: triggerType,
        latitude: latitude,
        longitude: longitude,
        radiusMeters: radiusMeters,
        isEnabled: true,
        isArmed: false,
        soundUri: '',
        vibrate: true,
        snoozeDurationMin: 10,
        createdAt: '2026-07-20T10:00:00Z',
        updatedAt: '2026-07-20T10:00:00Z',
      );
    }

    test('accepts a valid location alarm', () {
      final alarm = makeAlarm(
        latitude: 51.5074,
        longitude: -0.1278,
        radiusMeters: 2000,
      );
      expect(GeofenceValidator.isAlarmValid(alarm), isTrue);
    });

    test('rejects a time-based alarm', () {
      final alarm = makeAlarm(triggerType: AlarmTriggerType.time);
      expect(GeofenceValidator.isAlarmValid(alarm), isFalse);
    });

    test('rejects a location alarm with missing coordinates', () {
      final alarm = makeAlarm(radiusMeters: 2000);
      expect(GeofenceValidator.isAlarmValid(alarm), isFalse);
    });

    test('rejects a location alarm with missing radius', () {
      final alarm = makeAlarm(latitude: 51.5074, longitude: -0.1278);
      expect(GeofenceValidator.isAlarmValid(alarm), isFalse);
    });

    test('rejects a location alarm with out-of-range radius', () {
      final alarm = makeAlarm(
        latitude: 51.5074,
        longitude: -0.1278,
        radiusMeters: 100,
      );
      expect(GeofenceValidator.isAlarmValid(alarm), isFalse);
    });
  });

  group('GeofenceValidator.distanceMeters', () {
    test('distance from a point to itself is 0', () {
      expect(
        GeofenceValidator.distanceMeters(51.5074, -0.1278, 51.5074, -0.1278),
        closeTo(0, 1e-3),
      );
    });

    test('London to Paris is roughly 343 km', () {
      // London (51.5074, -0.1278) → Paris (48.8566, 2.3522).
      const expectedKm = 343;
      final d = GeofenceValidator.distanceMeters(
        51.5074,
        -0.1278,
        48.8566,
        2.3522,
      );
      expect(d / 1000, closeTo(expectedKm, 10)); // within 10 km
    });

    test('symmetric: d(A,B) == d(B,A)', () {
      final ab = GeofenceValidator.distanceMeters(
        40.7128,
        -74.0060,
        34.0522,
        -118.2437,
      );
      final ba = GeofenceValidator.distanceMeters(
        34.0522,
        -118.2437,
        40.7128,
        -74.0060,
      );
      expect(ab, closeTo(ba, 1e-6));
    });
  });

  group('GeofenceValidator.isPointInsideGeofence', () {
    test('a point at the center is inside', () {
      expect(
        GeofenceValidator.isPointInsideGeofence(
          centerLat: 51.5074,
          centerLon: -0.1278,
          pointLat: 51.5074,
          pointLon: -0.1278,
          radiusMeters: 1000,
        ),
        isTrue,
      );
    });

    test('a point comfortably inside the radius is inside', () {
      // 0.008° of latitude is ~889 m, well inside the 1 km
      // radius. The original "0.009° ≈ 1 km" value sat right
      // on the boundary and tripped the < vs <= comparison
      // depending on latitude scaling.
      expect(
        GeofenceValidator.isPointInsideGeofence(
          centerLat: 0.0,
          centerLon: 0.0,
          pointLat: 0.008,
          pointLon: 0.0,
          radiusMeters: 1000,
        ),
        isTrue,
      );
    });

    test('a point well outside the radius is outside', () {
      expect(
        GeofenceValidator.isPointInsideGeofence(
          centerLat: 0.0,
          centerLon: 0.0,
          pointLat: 10.0,
          pointLon: 10.0,
          radiusMeters: 1000,
        ),
        isFalse,
      );
    });
  });
}
