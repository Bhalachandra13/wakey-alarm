import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/domain/favourite_location.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/providers/favourite_locations_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late WakeyDatabase database;
  late ProviderContainer container;

  setUp(() async {
    database = WakeyDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: ':memory:',
    );
    await database.open();
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(database)],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  group('FavouriteLocationsNotifier', () {
    test('build() returns an empty list for a fresh database', () async {
      final favourites = await container.read(
        favouriteLocationsNotifierProvider.future,
      );
      expect(favourites, isEmpty);
    });

    test('add() persists the favourite and refreshes the list', () async {
      final notifier = container.read(
        favouriteLocationsNotifierProvider.notifier,
      );
      final id = await notifier.add(
        name: 'Home',
        latitude: 51.5074,
        longitude: -0.1278,
        radiusMeters: 1500,
      );
      expect(id, greaterThan(0));
      final favourites = await container.read(
        favouriteLocationsNotifierProvider.future,
      );
      expect(favourites, hasLength(1));
      expect(favourites.first.name, 'Home');
      expect(favourites.first.icon, FavouriteIcon.home); // auto from name
      expect(favourites.first.createdAt, isNotEmpty);
      expect(favourites.first.updatedAt, isNotEmpty);
    });

    test('add() with an explicit icon honours it', () async {
      final notifier = container.read(
        favouriteLocationsNotifierProvider.notifier,
      );
      await notifier.add(
        name: 'Some place',
        latitude: 0,
        longitude: 0,
        radiusMeters: 2000,
        icon: FavouriteIcon.work,
      );
      final favourites = await container.read(
        favouriteLocationsNotifierProvider.future,
      );
      expect(favourites.first.icon, FavouriteIcon.work);
    });

    test('edit() updates name/icon/radius and bumps updated_at', () async {
      final notifier = container.read(
        favouriteLocationsNotifierProvider.notifier,
      );
      final id = await notifier.add(
        name: 'Home',
        latitude: 0,
        longitude: 0,
        radiusMeters: 2000,
      );
      final before = (await container.read(
        favouriteLocationsNotifierProvider.future,
      )).first;
      // Force a measurable difference in updated_at.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await notifier.edit(
        id,
        name: 'Apartment',
        icon: FavouriteIcon.home,
        radiusMeters: 3000,
      );
      final after = (await container.read(
        favouriteLocationsNotifierProvider.future,
      )).first;
      expect(after.name, 'Apartment');
      expect(after.icon, FavouriteIcon.home);
      expect(after.radiusMeters, 3000);
      expect(after.createdAt, before.createdAt); // createdAt unchanged
      expect(after.updatedAt, isNot(before.updatedAt));
    });

    test('move() updates the location fields', () async {
      final notifier = container.read(
        favouriteLocationsNotifierProvider.notifier,
      );
      final id = await notifier.add(
        name: 'Home',
        latitude: 0,
        longitude: 0,
        radiusMeters: 2000,
      );
      await notifier.move(
        id,
        latitude: 48.8584,
        longitude: 2.2945,
        radiusMeters: 5000,
      );
      final after = (await container.read(
        favouriteLocationsNotifierProvider.future,
      )).first;
      expect(after.latitude, closeTo(48.8584, 1e-9));
      expect(after.longitude, closeTo(2.2945, 1e-9));
      expect(after.radiusMeters, 5000);
    });

    test('delete() removes the favourite', () async {
      final notifier = container.read(
        favouriteLocationsNotifierProvider.notifier,
      );
      final id = await notifier.add(
        name: 'Home',
        latitude: 0,
        longitude: 0,
        radiusMeters: 2000,
      );
      await notifier.delete(id);
      final favourites = await container.read(
        favouriteLocationsNotifierProvider.future,
      );
      expect(favourites, isEmpty);
    });

    test('hasFavouritesProvider reflects the current list', () async {
      // Fresh DB -> false.
      expect(container.read(hasFavouritesProvider), isFalse);
      // Add one -> true.
      final notifier = container.read(
        favouriteLocationsNotifierProvider.notifier,
      );
      await notifier.add(
        name: 'Home',
        latitude: 0,
        longitude: 0,
        radiusMeters: 2000,
      );
      // Force the AsyncNotifier to rebuild by reading the future.
      await container.read(favouriteLocationsNotifierProvider.future);
      expect(container.read(hasFavouritesProvider), isTrue);
      // Delete -> false again.
      final id = (await container.read(
        favouriteLocationsNotifierProvider.future,
      )).first.id!;
      await notifier.delete(id);
      await container.read(favouriteLocationsNotifierProvider.future);
      expect(container.read(hasFavouritesProvider), isFalse);
    });
  });
}
