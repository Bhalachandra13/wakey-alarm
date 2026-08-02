import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakey_alarm/data/location_search_service.dart';
import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/domain/favourite_location.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';
import 'package:wakey_alarm/native_bridge/geofence_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/providers/favourite_locations_provider.dart';
import 'package:wakey_alarm/presentation/screens/map_picker_screen.dart';

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

/// Minimal fake of the geofence bridge. The map picker calls
/// [GeofenceBridge.getCurrentLocation] on first frame; we return
/// `null` so the picker stays where the test placed it.
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

/// Test double for [LocationSearchService] that returns a canned
/// list of results (or throws) instead of hitting Nominatim.
class _FakeLocationSearchService extends LocationSearchService {
  _FakeLocationSearchService();

  List<LocationSearchResult> results = const [];
  LocationSearchException? error;
  Duration delay = Duration.zero;

  /// Records every query so tests can assert the UI fired the
  /// search with the expected text.
  final List<String> queries = [];

  @override
  Future<List<LocationSearchResult>> search(String query) async {
    queries.add(query);
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (error != null) throw error!;
    return results;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late WakeyDatabase database;
  late _FakeAlarmBridge fakeBridge;
  late _FakeGeofenceBridge fakeGeofence;
  late _FakeLocationSearchService fakeSearchService;

  setUp(() async {
    fakeBridge = _FakeAlarmBridge();
    fakeGeofence = _FakeGeofenceBridge();
    fakeSearchService = _FakeLocationSearchService();
    database = WakeyDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: ':memory:',
    );
    await database.open();
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
        locationSearchServiceProvider.overrideWithValue(fakeSearchService),
      ],
      child: MaterialApp(home: child ?? const MapPickerScreen()),
    );
  }

  group('MapPickerScreen search', () {
    testWidgets('search field is visible on first paint', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pump();
      expect(find.byKey(const Key('mapPickerSearchField')), findsOneWidget);
      expect(find.text('Search for a place'), findsOneWidget);
      // No results card yet.
      expect(find.byKey(const Key('mapPickerSearchResults')), findsNothing);
    });

    testWidgets(
      'typing in the search field debounces and then fires the service',
      (tester) async {
        fakeSearchService.results = const [
          LocationSearchResult(
            displayName: 'Eiffel Tower, Paris, France',
            latitude: 48.8584,
            longitude: 2.2945,
          ),
        ];
        await tester.pumpWidget(wrap());
        await tester.pump();

        // Simulate the user typing. We feed one character at a
        // time so we can verify only the *final* query hits the
        // service after the debounce window.
        await tester.enterText(
          find.byKey(const Key('mapPickerSearchField')),
          'e',
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(
          find.byKey(const Key('mapPickerSearchField')),
          'ei',
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(
          find.byKey(const Key('mapPickerSearchField')),
          'eif',
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(
          find.byKey(const Key('mapPickerSearchField')),
          'eiffel',
        );
        // Advance past the debounce (400ms) plus a tick for the
        // async result to render.
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();

        // The debounce collapsed the rapid keystrokes into a single
        // call with the final text. (The exact implementation may
        // fire one call per debounce window — we don't pin that,
        // but it must end up with the final query in the list.)
        expect(fakeSearchService.queries, isNotEmpty);
        expect(fakeSearchService.queries.last, 'eiffel');
        // The result rendered.
        expect(
          find.textContaining('Eiffel Tower, Paris, France'),
          findsOneWidget,
        );
      },
    );

    testWidgets('selecting a suggestion pops back with the chosen coords', (
      tester,
    ) async {
      fakeSearchService.results = const [
        LocationSearchResult(
          displayName: 'Big Ben, London, UK',
          latitude: 51.5007,
          longitude: -0.1246,
        ),
      ];
      MapPickerResult? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            alarmBridgeProvider.overrideWithValue(fakeBridge),
            geofenceBridgeProvider.overrideWithValue(fakeGeofence),
            locationSearchServiceProvider.overrideWithValue(fakeSearchService),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      result = await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const MapPickerScreen(),
                        ),
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Type a query, wait for the debounce, tap the result.
      await tester.enterText(
        find.byKey(const Key('mapPickerSearchField')),
        'big ben',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('mapPickerSearchResult_0')));
      await tester.pumpAndSettle();

      // Confirm the pick.
      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.latitude, closeTo(51.5007, 1e-6));
      expect(result!.longitude, closeTo(-0.1246, 1e-6));
    });

    testWidgets('an empty query clears the suggestions', (tester) async {
      fakeSearchService.results = const [
        LocationSearchResult(
          displayName: 'Eiffel Tower, Paris, France',
          latitude: 48.8584,
          longitude: 2.2945,
        ),
      ];
      await tester.pumpWidget(wrap());
      await tester.pump();

      // Type and wait for results.
      await tester.enterText(
        find.byKey(const Key('mapPickerSearchField')),
        'eiffel',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mapPickerSearchResults')), findsOneWidget);

      // Clear the field via the clear button. The service should
      // not be called for an empty query.
      fakeSearchService.queries.clear();
      await tester.tap(find.byKey(const Key('mapPickerSearchClear')));
      await tester.pumpAndSettle();

      expect(fakeSearchService.queries, isEmpty);
      expect(find.byKey(const Key('mapPickerSearchResults')), findsNothing);
    });

    testWidgets('a search error is rendered as a hint in the panel', (
      tester,
    ) async {
      fakeSearchService.error = const LocationSearchException(
        'Search returned status 503',
      );
      await tester.pumpWidget(wrap());
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('mapPickerSearchField')),
        'paris',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Search returned status 503'), findsOneWidget);
      expect(find.byKey(const Key('mapPickerSearchResults')), findsNothing);
    });

    testWidgets('a no-match response renders the empty-results message', (
      tester,
    ) async {
      fakeSearchService.results = const [];
      await tester.pumpWidget(wrap());
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('mapPickerSearchField')),
        'asdfghjkl',
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('No matches for "asdfghjkl"'), findsOneWidget);
    });

    testWidgets('stale in-flight searches do not overwrite the latest result', (
      tester,
    ) async {
      // First call is slow, second is fast. The slow one must
      // not land in the UI after the fast one has already
      // rendered — otherwise the user sees old results behind
      // their fresh query.
      fakeSearchService.delay = const Duration(milliseconds: 200);
      fakeSearchService.results = const [
        LocationSearchResult(
          displayName: 'Slow result',
          latitude: 1,
          longitude: 1,
        ),
      ];
      await tester.pumpWidget(wrap());
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('mapPickerSearchField')),
        'first',
      );
      // Don't wait the full debounce + delay yet — switch
      // results to a different (fast) response before the
      // first one completes.
      await tester.pump(const Duration(milliseconds: 400));
      // The first search is now in flight. Swap the canned
      // results and trigger a second search.
      fakeSearchService.delay = Duration.zero;
      fakeSearchService.results = const [
        LocationSearchResult(
          displayName: 'Fast result',
          latitude: 2,
          longitude: 2,
        ),
      ];
      await tester.enterText(
        find.byKey(const Key('mapPickerSearchField')),
        'second',
      );
      // Let the second search resolve.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      // The fast result is visible; the slow one is not.
      expect(find.textContaining('Fast result'), findsOneWidget);
      expect(find.textContaining('Slow result'), findsNothing);
    });
  });

  group('MapPickerScreen favourite chips', () {
    FavouriteLocation stubFav({
      required String name,
      required double lat,
      required double lon,
      required int radius,
    }) {
      return FavouriteLocation(
        name: name,
        icon: FavouriteIcon.fromName(name),
        latitude: lat,
        longitude: lon,
        radiusMeters: radius,
        createdAt: '2026-01-01T00:00:00.000',
        updatedAt: '2026-01-01T00:00:00.000',
      );
    }

    /// Wrap that overrides [favouriteLocationsProvider] with a
    /// pre-built list. Bypassing the notifier (and therefore the
    /// sqflite_ffi real-isolate read) is deliberate: the map
    /// picker's GoogleMap widget throws on a platform-view create
    /// when we use `runAsync` to wait for the isolate, so we
    /// supply the data synchronously instead.
    Widget wrapWithFavourites(List<FavouriteLocation> favourites) {
      return ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          alarmBridgeProvider.overrideWithValue(fakeBridge),
          geofenceBridgeProvider.overrideWithValue(fakeGeofence),
          locationSearchServiceProvider.overrideWithValue(fakeSearchService),
          favouriteLocationsProvider.overrideWith(
            (ref) => AsyncValue<List<FavouriteLocation>>.data(favourites),
          ),
        ],
        child: const MaterialApp(home: MapPickerScreen()),
      );
    }

    testWidgets('renders a chip per saved favourite', (tester) async {
      final favourites = [
        stubFav(name: 'Home', lat: 51.5, lon: -0.12, radius: 1500),
        stubFav(name: 'Work', lat: 51.5, lon: -0.13, radius: 500),
      ];
      await tester.pumpWidget(wrapWithFavourites(favourites));
      await tester.pump();
      expect(find.byKey(const Key('mapPickerFavouriteChips')), findsOneWidget);
      expect(find.byKey(const Key('mapPickerFavouriteChip_0')), findsOneWidget);
      expect(find.byKey(const Key('mapPickerFavouriteChip_1')), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      // The empty hint must not render when there are favourites.
      expect(
        find.byKey(const Key('mapPickerFavouritesEmptyHint')),
        findsNothing,
      );
    });

    testWidgets(
      'tapping a chip drops the pin and adopts the favourite radius',
      (tester) async {
        final favourites = [
          stubFav(name: 'Home', lat: 48.8584, lon: 2.2945, radius: 2500),
        ];
        // Drive the picker via a Navigator so we can confirm with
        // the ✓ and read back the MapPickerResult.
        MapPickerResult? result;
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseProvider.overrideWithValue(database),
              alarmBridgeProvider.overrideWithValue(fakeBridge),
              geofenceBridgeProvider.overrideWithValue(fakeGeofence),
              locationSearchServiceProvider.overrideWithValue(
                fakeSearchService,
              ),
              favouriteLocationsProvider.overrideWith(
                (ref) => AsyncValue<List<FavouriteLocation>>.data(favourites),
              ),
            ],
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        result = await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const MapPickerScreen(),
                          ),
                        );
                      },
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('Open'));
        // The route push needs a real-time tick for the platform
        // channel init before pumpAndSettle can settle on the
        // picker.
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        // Tap the Home chip and confirm.
        await tester.tap(find.byKey(const Key('mapPickerFavouriteChip_0')));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
        await tester.pumpAndSettle();
        expect(result, isNotNull);
        expect(result!.latitude, closeTo(48.8584, 1e-6));
        expect(result!.longitude, closeTo(2.2945, 1e-6));
        expect(result!.radiusMeters, 2500);
      },
    );

    testWidgets('shows the empty-state nudge when no favourites are saved', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      // No favourites in the DB, so the empty hint shows as soon
      // as the panel renders. A single pump is enough — there's
      // no DB read waiting on the real isolate (the empty result
      // is what the panel defaults to while loading anyway).
      await tester.pump();
      expect(
        find.byKey(const Key('mapPickerFavouritesEmptyHint')),
        findsOneWidget,
      );
      expect(
        find.text('Tip: save frequent places for one-tap picking'),
        findsOneWidget,
      );
      // The chip strip itself is not rendered in the empty case.
      expect(find.byKey(const Key('mapPickerFavouriteChips')), findsNothing);
    });
  });
}
