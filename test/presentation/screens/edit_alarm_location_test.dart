import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakey_alarm/data/location_search_service.dart';
import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/screens/edit_alarm_screen.dart';

class _FakeAlarmBridge implements AlarmBridge {
  _FakeAlarmBridge()
    : eventController = StreamController<AlarmEvent>.broadcast();
  final StreamController<AlarmEvent> eventController;
  @override
  Stream<AlarmEvent>? eventStream;
  @override
  Stream<AlarmEvent> get alarmEvents => eventController.stream;
  @override
  Future<bool> scheduleAlarm(Map<String, Object?> payload) async => true;
  @override
  Future<bool> scheduleTimer(Map<String, Object?> payload) async => true;
  @override
  Future<bool> cancelAlarm(int alarmId) async => true;
  @override
  Future<String?> pickRingtone({String? currentUri}) async => null;
}

/// Test double for [LocationSearchService] that returns a canned
/// list of results (or throws) instead of hitting Nominatim. The
/// test is in control of the outcome so we can assert on each
/// branch of the UI.
class _FakeLocationSearchService extends LocationSearchService {
  _FakeLocationSearchService();

  List<LocationSearchResult> results = const [];
  LocationSearchException? error;

  /// Records every query so tests can assert the UI fired the
  /// search with the expected text.
  final List<String> queries = [];

  @override
  Future<List<LocationSearchResult>> search(String query) async {
    queries.add(query);
    if (error != null) throw error!;
    return results;
  }
}

class _MockAlarmsNotifier extends AlarmsNotifier {
  final List<Alarm> savedAlarms = [];
  int _nextId = 1;

  @override
  Future<List<Alarm>> build() async {
    return savedAlarms;
  }

  @override
  Future<({int id, bool scheduled})> insertAlarm(Alarm alarm) async {
    final id = _nextId++;
    savedAlarms.add(alarm.copyWith(id: id));
    ref.invalidateSelf();
    return (id: id, scheduled: true);
  }

  @override
  Future<bool> updateAlarm(Alarm alarm) async {
    final index = savedAlarms.indexWhere((a) => a.id == alarm.id);
    if (index != -1) {
      savedAlarms[index] = alarm;
    }
    ref.invalidateSelf();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late WakeyDatabase database;
  late _FakeAlarmBridge fakeBridge;
  late _MockAlarmsNotifier mockNotifier;
  late _FakeLocationSearchService fakeSearchService;

  setUp(() async {
    fakeBridge = _FakeAlarmBridge();
    addTearDown(fakeBridge.eventController.close);

    mockNotifier = _MockAlarmsNotifier();
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
        alarmEventsProvider.overrideWith(
          (ref) => fakeBridge.eventController.stream,
        ),
        alarmsNotifierProvider.overrideWith(() => mockNotifier),
        locationSearchServiceProvider.overrideWithValue(fakeSearchService),
      ],
      child: MaterialApp(home: child ?? const EditAlarmScreen()),
    );
  }

  group('EditAlarmScreen with location trigger', () {
    testWidgets('default mode shows time-based UI', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      // The default is TIME. The exact label depends on locale
      // (12-hour vs 24-hour), but the literal "Tap to change time"
      // hint is locale-independent.
      expect(find.text('Tap to change time'), findsOneWidget);
      expect(find.text('REPEAT'), findsOneWidget);
      // The TRIGGER segment is shown.
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('Location'), findsOneWidget);
    });

    testWidgets('switching to location reveals map picker section', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      // The Location segment in the trigger selector.
      await tester.tap(find.text('Location'));
      await tester.pumpAndSettle();

      // The time-based UI is hidden.
      expect(find.text('Tap to change time'), findsNothing);
      // The location UI is shown.
      expect(find.text('No location picked yet'), findsOneWidget);
      expect(find.text('Pick on map'), findsOneWidget);
      // REPEAT is hidden for location alarms (they're one-shot).
      expect(find.text('REPEAT'), findsNothing);
      // The radius slider is disabled until a location is picked.
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNull);
    });

    testWidgets('shows validation error when saving without a location', (
      tester,
    ) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      // Switch to location.
      await tester.tap(find.text('Location'));
      await tester.pumpAndSettle();

      // Try to save via the AppBar check icon button. The bottom
      // Save button can sit off-screen on the 800x600 test
      // surface, so use the AppBar action.
      await tester.tap(find.widgetWithIcon(IconButton, Icons.check));
      await tester.pump();

      // The SnackBar should appear.
      expect(find.text('Pick a location first'), findsOneWidget);
    });

    testWidgets('editing an existing location alarm pre-fills the form', (
      tester,
    ) async {
      const existing = Alarm(
        id: 1,
        label: 'Train stop',
        triggerType: AlarmTriggerType.location,
        latitude: 51.5074,
        longitude: -0.1278,
        radiusMeters: 5000,
        isEnabled: true,
        isArmed: false,
        soundUri: '',
        vibrate: true,
        snoozeDurationMin: 10,
        createdAt: '2026-07-20T10:00:00Z',
        updatedAt: '2026-07-20T10:00:00Z',
      );
      await tester.pumpWidget(
        wrap(child: const EditAlarmScreen(alarm: existing)),
      );
      await tester.pumpAndSettle();

      // Title is "Edit Alarm" (not "Add Alarm").
      expect(find.text('Edit Alarm'), findsOneWidget);
      // Label is pre-filled.
      expect(find.text('Train stop'), findsOneWidget);
      // Location is shown with lat/long.
      expect(find.textContaining('51.50740'), findsOneWidget);
      expect(find.textContaining('-0.12780'), findsOneWidget);
      // The radius is 5 km (formatted without decimal for whole
      // kilometers).
      expect(find.text('5 km'), findsOneWidget);
    });
  });

  group('EditAlarmScreen address search', () {
    Future<void> switchToLocationMode(WidgetTester tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Location'));
      await tester.pumpAndSettle();
    }

    testWidgets('search field is visible in location mode', (tester) async {
      await switchToLocationMode(tester);
      // The search field is in the location card and has the
      // "Search for a place" hint.
      expect(find.byKey(const Key('locationSearchField')), findsOneWidget);
      expect(find.text('Search for a place'), findsOneWidget);
      // No results card yet.
      expect(find.byKey(const Key('locationSearchResults')), findsNothing);
    });

    testWidgets('search field is not visible in time mode', (tester) async {
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();
      // Default mode is time-based; the search field belongs to
      // the location section.
      expect(find.byKey(const Key('locationSearchField')), findsNothing);
    });

    testWidgets('tapping search with results renders the result list', (
      tester,
    ) async {
      fakeSearchService.results = const [
        LocationSearchResult(
          displayName: 'Eiffel Tower, Paris, France',
          latitude: 48.8584,
          longitude: 2.2945,
        ),
        LocationSearchResult(
          displayName: 'Eiffel Tower replica, Paris, Texas, USA',
          latitude: 33.6618,
          longitude: -95.5555,
        ),
      ];
      await switchToLocationMode(tester);

      await tester.enterText(
        find.byKey(const Key('locationSearchField')),
        'eiffel tower',
      );
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      // Both results render.
      expect(find.textContaining('Eiffel Tower, Paris, France'), findsOneWidget);
      expect(
        find.textContaining('Eiffel Tower replica, Paris, Texas, USA'),
        findsOneWidget,
      );
      // The service was called once with the trimmed query.
      expect(fakeSearchService.queries, ['eiffel tower']);
      // No location picked yet — the lat/lon text still says
      // "No location picked yet" because the user hasn't tapped a
      // result.
      expect(find.text('No location picked yet'), findsOneWidget);
    });

    testWidgets('selecting a search result sets the location', (tester) async {
      fakeSearchService.results = const [
        LocationSearchResult(
          displayName: 'Eiffel Tower, Paris, France',
          latitude: 48.8584,
          longitude: 2.2945,
        ),
      ];
      await switchToLocationMode(tester);

      await tester.enterText(
        find.byKey(const Key('locationSearchField')),
        'eiffel',
      );
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('locationSearchResult_0')));
      await tester.pumpAndSettle();

      // The picked location is now displayed.
      expect(find.textContaining('48.85840'), findsOneWidget);
      expect(find.textContaining('2.29450'), findsOneWidget);
      // Picking collapses the results and the search field so the
      // user can see the picked location clearly.
      expect(find.byKey(const Key('locationSearchResults')), findsNothing);
      // The radius slider is now enabled.
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNotNull);
    });

    testWidgets('submitting the keyboard search action runs the search', (
      tester,
    ) async {
      fakeSearchService.results = const [
        LocationSearchResult(
          displayName: 'Big Ben, London, UK',
          latitude: 51.5007,
          longitude: -0.1246,
        ),
      ];
      await switchToLocationMode(tester);

      await tester.enterText(
        find.byKey(const Key('locationSearchField')),
        'big ben',
      );
      // Press the keyboard "search" action.
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(fakeSearchService.queries, ['big ben']);
      expect(find.textContaining('Big Ben, London, UK'), findsOneWidget);
    });

    testWidgets('an empty query is ignored', (tester) async {
      await switchToLocationMode(tester);
      // The default text is empty; tapping the search icon should
      // not fire the service.
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(fakeSearchService.queries, isEmpty);
      expect(find.byKey(const Key('locationSearchResults')), findsNothing);
    });

    testWidgets('a search error is rendered to the user', (tester) async {
      fakeSearchService.error = const LocationSearchException(
        'Search returned status 503',
      );
      await switchToLocationMode(tester);

      await tester.enterText(
        find.byKey(const Key('locationSearchField')),
        'paris',
      );
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      // Error message is shown; no results card.
      expect(find.text('Search returned status 503'), findsOneWidget);
      expect(find.byKey(const Key('locationSearchResults')), findsNothing);
    });

    testWidgets('a no-match response renders the empty-results message', (
      tester,
    ) async {
      fakeSearchService.results = const [];
      await switchToLocationMode(tester);

      await tester.enterText(
        find.byKey(const Key('locationSearchField')),
        'asdfghjkl',
      );
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();

      expect(find.text('No matches for "asdfghjkl"'), findsOneWidget);
    });

    testWidgets('clearing the location resets the search state', (
      tester,
    ) async {
      fakeSearchService.results = const [
        LocationSearchResult(
          displayName: 'Eiffel Tower, Paris, France',
          latitude: 48.8584,
          longitude: 2.2945,
        ),
      ];
      await switchToLocationMode(tester);

      // Pick a result so the "Clear" button is visible.
      await tester.enterText(
        find.byKey(const Key('locationSearchField')),
        'eiffel',
      );
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('locationSearchResult_0')));
      await tester.pumpAndSettle();

      // Now tap "Clear" (the location, not the search). The
      // search input should be reset to empty, the results
      // dismissed, and the lat/lon text back to the empty state.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Clear'));
      await tester.pumpAndSettle();

      expect(find.text('No location picked yet'), findsOneWidget);
      // The search TextField is now empty. Reset the recorded
      // queries and run a fresh search; the only call after the
      // clear should be the new one.
      fakeSearchService.queries.clear();
      await tester.enterText(
        find.byKey(const Key('locationSearchField')),
        'london',
      );
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(fakeSearchService.queries, ['london']);
    });
  });
}
