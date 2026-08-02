import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakey_alarm/data/favourite_location_dao.dart';
import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/domain/favourite_location.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';
import 'package:wakey_alarm/native_bridge/geofence_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/screens/favourites_screen.dart';

class _FakeAlarmBridge implements AlarmBridge {
  @override
  Stream<AlarmEvent>? eventStream;
  @override
  Stream<AlarmEvent> get alarmEvents => const Stream<AlarmEvent>.empty();
  @override
  Future<bool> scheduleAlarm(Map<String, Object?> payload) async => true;
  @override
  Future<bool> scheduleTimer(Map<String, Object?> payload) async => true;
  @override
  Future<bool> cancelAlarm(int alarmId) async => true;
  @override
  Future<String?> pickRingtone({String? currentUri}) async => null;
}

class _FakeGeofenceBridge implements GeofenceBridge {
  @override
  Future<LocationPermissionStatus> getPermissionStatus() async =>
      LocationPermissionStatus.notRequired;
  @override
  Future<LocationPermissionStatus> requestForegroundLocation() async =>
      LocationPermissionStatus.notRequired;
  @override
  Future<LocationPermissionStatus> requestBackgroundLocation() async =>
      LocationPermissionStatus.notRequired;
  @override
  Future<GeoPoint?> getCurrentLocation({
    Duration timeout = const Duration(seconds: 10),
  }) async => null;
  @override
  Future<GeofenceResult> addGeofence({
    required int alarmId,
    required double latitude,
    required double longitude,
    required int radiusMeters,
    int expirationMillis = -1,
    String label = 'Alarm',
    String soundUri = '',
    bool vibrate = true,
    int snoozeDurationMin = 10,
    int maxSnoozeCount = -1,
  }) async => const GeofenceResult.ok();
  @override
  Future<GeofenceResult> removeGeofence(int alarmId) async =>
      const GeofenceResult.ok();
  @override
  Future<bool> isBatteryOptimizationExempt() async => true;
  @override
  Future<bool> requestBatteryOptimizationExemption() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late WakeyDatabase database;
  late _FakeAlarmBridge fakeBridge;
  late _FakeGeofenceBridge fakeGeofence;
  late FavouriteLocationDao dao;

  setUp(() async {
    database = WakeyDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: ':memory:',
    );
    await database.open();
    fakeBridge = _FakeAlarmBridge();
    fakeGeofence = _FakeGeofenceBridge();
    dao = FavouriteLocationDao(database);
  });

  tearDown(() async {
    await database.close();
  });

  Widget wrap({Widget? child}) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        alarmBridgeProvider.overrideWithValue(fakeBridge),
        geofenceBridgeProvider.overrideWithValue(fakeGeofence),
      ],
      child: MaterialApp(home: child ?? const FavouritesScreen()),
    );
  }

  Future<void> seed({
    String name = 'Home',
    FavouriteIcon? icon,
    double latitude = 51.5074,
    double longitude = -0.1278,
    int radiusMeters = 2000,
  }) {
    return dao.insert(
      FavouriteLocation(
        name: name,
        icon: icon ?? FavouriteIcon.fromName(name),
        latitude: latitude,
        longitude: longitude,
        radiusMeters: radiusMeters,
        createdAt: '2026-01-01T00:00:00.000',
        updatedAt: '2026-01-01T00:00:00.000',
      ),
    );
  }

  group('FavouritesScreen empty state', () {
    testWidgets('shows the Add Home / Add Work affordances', (tester) async {
      await tester.pumpWidget(wrap());
      // sqflite_ffi runs its operations on a real background
      // isolate, so the AsyncNotifier's `build()` future only
      // resolves in real time — not in the fake-async clock that
      // `tester.pump` advances. We hop out of fake-async with
      // `runAsync` to let the isolate respond, then pump a frame
      // to rebuild with the resolved data.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.text('No saved places yet'), findsOneWidget);
      expect(find.byKey(const Key('emptyStateAddHome')), findsOneWidget);
      expect(find.byKey(const Key('emptyStateAddWork')), findsOneWidget);
      expect(find.byKey(const Key('emptyStateAddCustom')), findsOneWidget);
    });

    testWidgets('Add Home pushes the map picker', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.tap(find.byKey(const Key('emptyStateAddHome')));
      // The picker route push is driven by real-async Navigator
      // state; pumpAndSettle would work here (the picker has no
      // indefinite-progress indicator), but the navigation
      // animation + the real-isolate map initialisation need a
      // real-time tick first.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Pick location'), findsOneWidget);
      expect(find.byKey(const Key('mapPickerSearchField')), findsOneWidget);
    });
  });

  group('FavouritesScreen populated list', () {
    testWidgets('renders one row per saved favourite', (tester) async {
      // Seed inside runAsync so the sqflite_ffi real-isolate
      // inserts complete — a plain `await seed(...)` in fake-async
      // would hang waiting for the isolate to respond.
      await tester.runAsync(() async {
        await seed(name: 'Home');
        await seed(name: 'Work');
      });
      await tester.pumpWidget(wrap());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(find.byKey(const Key('favouritesList')), findsOneWidget);
      expect(find.byKey(const Key('favouriteRow_0')), findsOneWidget);
      expect(find.byKey(const Key('favouriteRow_1')), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.byKey(const Key('favouriteDelete_0')), findsOneWidget);
      expect(find.byKey(const Key('favouriteDelete_1')), findsOneWidget);
    });

    testWidgets('delete button shows a confirmation dialog', (tester) async {
      await tester.runAsync(() async {
        await seed(name: 'Home');
      });
      await tester.pumpWidget(wrap());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.tap(find.byKey(const Key('favouriteDelete_0')));
      await tester.pumpAndSettle();
      expect(find.text('Delete saved place?'), findsOneWidget);
      // Cancel keeps the row.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('favouriteRow_0')), findsOneWidget);
    });

    testWidgets('tapping a row pushes the map picker pre-filled', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await seed(name: 'Home');
      });
      await tester.pumpWidget(wrap());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.tap(find.byKey(const Key('favouriteRow_0')));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Pick location'), findsOneWidget);
    });

    testWidgets('+ button in the app bar pushes the map picker', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.tap(find.byKey(const Key('favouritesAddButton')));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Pick location'), findsOneWidget);
    });
  });
}
