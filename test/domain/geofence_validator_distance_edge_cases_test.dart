import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/domain/geofence_validator.dart';

void main() {
  group('GeofenceValidator.distanceMeters', () {
    test('returns 0 for the same point', () {
      expect(
        GeofenceValidator.distanceMeters(0, 0, 0, 0),
        closeTo(0, 1e-3),
      );
    });

    test('returns ~343 km for London to Paris', () {
      final d = GeofenceValidator.distanceMeters(
        51.5074,
        -0.1278,
        48.8566,
        2.3522,
      );
      expect(d / 1000, closeTo(343, 10));
    });

    test('returns a finite value for antipodal points (no NaN)', () {
      // Antipodal points: the true great-circle distance is exactly
      // pi * R ≈ 20015 km. The un-clamped Haversine formula produces
      // a `a` value that rounds slightly above 1, which yields
      // sqrt(1 - a) = NaN. The clamped implementation should still
      // return a finite, well-defined value.
      final d = GeofenceValidator.distanceMeters(
        0,
        0,
        0,
        180,
      );
      expect(d, isNotNull);
      expect(d.isFinite, isTrue, reason: 'must not produce NaN or infinity');
      expect(d / 1000, closeTo(20015, 5));
    });

    test('returns a finite value for nearly antipodal points', () {
      final d = GeofenceValidator.distanceMeters(
        0,
        0,
        0,
        179.9999999,
      );
      expect(d.isFinite, isTrue);
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

    test('handles north pole to south pole', () {
      final d = GeofenceValidator.distanceMeters(90, 0, -90, 0);
      // Half the Earth's circumference.
      expect(d / 1000, closeTo(20015, 5));
    });
  });
}
