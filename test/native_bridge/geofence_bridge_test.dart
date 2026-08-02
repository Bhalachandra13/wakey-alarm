import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/native_bridge/geofence_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GeofenceBridge', () {
    const channel = MethodChannel('com.wakeywakey/geofence');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('getPermissionStatus parses native response correctly', () async {
      for (final entry in {
        'granted_foreground_only':
            LocationPermissionStatus.grantedForegroundOnly,
        'granted_foreground_and_background':
            LocationPermissionStatus.grantedForegroundAndBackground,
        'denied': LocationPermissionStatus.denied,
        'not_required': LocationPermissionStatus.notRequired,
      }.entries) {
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getLocationPermissionStatus') return entry.key;
          return null;
        });
        final bridge = GeofenceBridge();
        final status = await bridge.getPermissionStatus();
        expect(status, entry.value, reason: 'for native=${entry.key}');
      }
    });

    test(
      'getPermissionStatus returns denied for unknown native values',
      () async {
        messenger.setMockMethodCallHandler(channel, (call) async => 'banana');
        final bridge = GeofenceBridge();
        expect(
          await bridge.getPermissionStatus(),
          LocationPermissionStatus.denied,
        );
      },
    );

    test('getCurrentLocation returns a GeoPoint on success', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getCurrentLocation') {
          return <String, Object?>{'latitude': 51.5074, 'longitude': -0.1278};
        }
        return null;
      });
      final bridge = GeofenceBridge();
      final point = await bridge.getCurrentLocation();
      expect(point, isNotNull);
      expect(point!.latitude, 51.5074);
      expect(point.longitude, -0.1278);
    });

    test('getCurrentLocation returns null on null native response', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getCurrentLocation') return null;
        return null;
      });
      final bridge = GeofenceBridge();
      expect(await bridge.getCurrentLocation(), isNull);
    });

    test(
      'getCurrentLocation returns null on missing latitude/longitude',
      () async {
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getCurrentLocation') return <String, Object?>{};
          return null;
        });
        final bridge = GeofenceBridge();
        expect(await bridge.getCurrentLocation(), isNull);
      },
    );

    test('addGeofence forwards the payload and reports added=true', () async {
      Map<String, Object?>? captured;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'addGeofence') {
          captured = Map<String, Object?>.from(
            call.arguments as Map<Object?, Object?>,
          );
          return <String, Object?>{'added': true};
        }
        return null;
      });
      final bridge = GeofenceBridge();
      final result = await bridge.addGeofence(
        alarmId: 7,
        latitude: 51.5074,
        longitude: -0.1278,
        radiusMeters: 2000,
      );
      expect(result.ok, isTrue);
      expect(captured, isNotNull);
      // ignore: null_check_on_nullable_type_parameter
      final payload = captured!;
      expect(payload['alarmId'], 7);
      expect(payload['latitude'], 51.5074);
      expect(payload['longitude'], -0.1278);
      expect(payload['radiusMeters'], 2000);
      // Default expiration is NEVER_EXPIRE (-1).
      expect(payload['expirationMillis'], -1);
    });

    test('addGeofence reports a humanized error on failure', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'addGeofence') {
          return <String, Object?>{
            'added': false,
            'error': 'Location services are off. Turn on Location in system Settings.',
            'code': 1004,
          };
        }
        return null;
      });
      final bridge = GeofenceBridge();
      final result = await bridge.addGeofence(
        alarmId: 1,
        latitude: 0,
        longitude: 0,
        radiusMeters: 500,
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('Location services are off'));
      expect(result.code, 1004);
    });

    test('addGeofence converts a PlatformException into a GeofenceResult', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'addGeofence') {
          throw PlatformException(code: 'native_error', message: 'channel gone');
        }
        return null;
      });
      final bridge = GeofenceBridge();
      final result = await bridge.addGeofence(
        alarmId: 1,
        latitude: 0,
        longitude: 0,
        radiusMeters: 500,
      );
      expect(result.ok, isFalse);
      expect(result.error, 'channel gone');
    });

    test('removeGeofence reports removed=true on success', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'removeGeofence') {
          return <String, Object?>{'removed': true};
        }
        return null;
      });
      final bridge = GeofenceBridge();
      final result = await bridge.removeGeofence(7);
      expect(result.ok, isTrue);
    });

    test('removeGeofence reports failure with error string', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'removeGeofence') {
          return <String, Object?>{'removed': false, 'error': 'not_found'};
        }
        return null;
      });
      final bridge = GeofenceBridge();
      final result = await bridge.removeGeofence(7);
      expect(result.ok, isFalse);
      expect(result.error, 'not_found');
    });

    test('isBatteryOptimizationExempt forwards the boolean', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'isBatteryOptimizationExempt') return true;
        return null;
      });
      final bridge = GeofenceBridge();
      expect(await bridge.isBatteryOptimizationExempt(), isTrue);
    });
  });

  group('GeoPoint', () {
    test('equality is value-based', () {
      const a = GeoPoint(latitude: 1, longitude: 2);
      const b = GeoPoint(latitude: 1, longitude: 2);
      const c = GeoPoint(latitude: 1, longitude: 3);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('toString includes both coordinates', () {
      const p = GeoPoint(latitude: 51.5, longitude: -0.1);
      expect(p.toString(), contains('51.5'));
      expect(p.toString(), contains('-0.1'));
    });
  });
}
