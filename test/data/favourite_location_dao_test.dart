import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakey_alarm/data/favourite_location_dao.dart';
import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/domain/favourite_location.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  late WakeyDatabase database;
  late FavouriteLocationDao dao;

  setUp(() async {
    database = WakeyDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: ':memory:',
    );
    await database.open();
    dao = FavouriteLocationDao(database);
  });

  tearDown(() async {
    await database.close();
  });

  FavouriteLocation sample({
    int? id,
    String name = 'Home',
    FavouriteIcon icon = FavouriteIcon.home,
    double latitude = 51.5074,
    double longitude = -0.1278,
    int radiusMeters = 2000,
    String? createdAt,
    String? updatedAt,
  }) {
    return FavouriteLocation(
      id: id,
      name: name,
      icon: icon,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      createdAt: createdAt ?? '2026-01-01T00:00:00.000',
      updatedAt: updatedAt ?? '2026-01-01T00:00:00.000',
    );
  }

  group('FavouriteLocationDao', () {
    test('insert assigns an id and round-trips through read', () async {
      final id = await dao.insert(sample());
      expect(id, greaterThan(0));
      final loaded = await dao.read(id);
      expect(loaded, isNotNull);
      expect(loaded!.name, 'Home');
      expect(loaded.icon, FavouriteIcon.home);
      expect(loaded.latitude, 51.5074);
      expect(loaded.longitude, -0.1278);
      expect(loaded.radiusMeters, 2000);
    });

    test('read returns null for an unknown id', () async {
      expect(await dao.read(9999), isNull);
    });

    test('getAll returns favourites oldest-first', () async {
      await dao.insert(
        sample(name: 'First', createdAt: '2026-01-01T00:00:00.000'),
      );
      await dao.insert(
        sample(name: 'Second', createdAt: '2026-01-02T00:00:00.000'),
      );
      await dao.insert(
        sample(name: 'Third', createdAt: '2026-01-03T00:00:00.000'),
      );
      final all = await dao.getAll();
      expect(all.map((f) => f.name).toList(), ['First', 'Second', 'Third']);
    });

    test('getAll on an empty table returns an empty list', () async {
      expect(await dao.getAll(), isEmpty);
    });

    test('update replaces the row in place', () async {
      final id = await dao.insert(sample(name: 'Home'));
      final original = await dao.read(id);
      final updated = original!.copyWith(
        name: 'Apartment',
        updatedAt: '2026-02-01T00:00:00.000',
      );
      await dao.update(updated);
      final reloaded = await dao.read(id);
      expect(reloaded!.name, 'Apartment');
      expect(reloaded.updatedAt, '2026-02-01T00:00:00.000');
      expect(reloaded.latitude, original.latitude);
    });

    test('update without an id throws', () async {
      expect(() => dao.update(sample()), throwsArgumentError);
    });

    test('delete removes the row', () async {
      final id = await dao.insert(sample());
      expect(await dao.delete(id), 1);
      expect(await dao.read(id), isNull);
    });

    test('delete on a missing id is a no-op (returns 0)', () async {
      expect(await dao.delete(9999), 0);
    });

    test('deleteAll clears every favourite', () async {
      await dao.insert(sample(name: 'A'));
      await dao.insert(sample(name: 'B'));
      expect(await dao.deleteAll(), 2);
      expect(await dao.getAll(), isEmpty);
    });

    test('count returns the number of saved favourites', () async {
      expect(await dao.count(), 0);
      await dao.insert(sample(name: 'A'));
      await dao.insert(sample(name: 'B'));
      await dao.insert(sample(name: 'C'));
      expect(await dao.count(), 3);
    });

    test('icon_code round-trips and fromCode falls back to place', () async {
      final id = await dao.insert(
        sample(name: 'Mystery', icon: FavouriteIcon.place),
      );
      final loaded = await dao.read(id);
      expect(loaded!.icon, FavouriteIcon.place);
      // fromCode with an unknown code should defensively fall back
      // to .place rather than throw, so a future migration adding
      // a new icon doesn't crash old builds.
      expect(FavouriteIcon.fromCode('unknown_code'), FavouriteIcon.place);
    });

    test('latitude and longitude survive a numeric round-trip', () async {
      final id = await dao.insert(sample(latitude: 48.8584, longitude: 2.2945));
      final loaded = await dao.read(id);
      expect(loaded!.latitude, closeTo(48.8584, 1e-9));
      expect(loaded.longitude, closeTo(2.2945, 1e-9));
    });
  });

  group('FavouriteIcon.fromName', () {
    test('maps common place names to their category icons', () {
      expect(FavouriteIcon.fromName('Home'), FavouriteIcon.home);
      expect(FavouriteIcon.fromName('My Home'), FavouriteIcon.home);
      expect(FavouriteIcon.fromName('House'), FavouriteIcon.home);
      expect(FavouriteIcon.fromName('Work'), FavouriteIcon.work);
      expect(FavouriteIcon.fromName('Office'), FavouriteIcon.work);
      expect(FavouriteIcon.fromName('School'), FavouriteIcon.school);
      expect(FavouriteIcon.fromName('Gym'), FavouriteIcon.favorite);
    });

    test('falls back to place for unknown names', () {
      expect(FavouriteIcon.fromName('Random cafe'), FavouriteIcon.place);
      expect(FavouriteIcon.fromName(''), FavouriteIcon.place);
    });

    test('matching is case-insensitive and whitespace-trimmed', () {
      expect(FavouriteIcon.fromName('  HOME  '), FavouriteIcon.home);
    });
  });
}
