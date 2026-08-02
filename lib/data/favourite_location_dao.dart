import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/domain/favourite_location.dart';

/// Data Access Object for [FavouriteLocation] CRUD operations.
///
/// The DAO is intentionally narrow — it does not enforce
/// duplicate-name rules or soft-delete semantics. Two favourites
/// with the same name are allowed (a user might have two "Home"
/// locations if they move); deletion is hard so the user
/// always has a clear "gone" signal in the UI.
class FavouriteLocationDao {
  FavouriteLocationDao(this.database);

  final WakeyDatabase database;

  /// Insert a new favourite. Returns the inserted row id.
  Future<int> insert(FavouriteLocation fav) async {
    final db = await database.open();
    return db.insert('favourite_locations', fav.toJson());
  }

  /// Read a single favourite by id. Returns `null` if not found.
  Future<FavouriteLocation?> read(int id) async {
    final db = await database.open();
    final rows = await db.query(
      'favourite_locations',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return FavouriteLocation.fromJson(rows.first);
  }

  /// Read every favourite, oldest-first. The favourites list is
  /// short (handful of items in normal use) so a simple stable
  /// order is fine; sorting by `created_at` keeps the user's
  /// mental model — "Home" added today still appears before
  /// "Gym" added tomorrow.
  Future<List<FavouriteLocation>> getAll() async {
    final db = await database.open();
    final rows = await db.query(
      'favourite_locations',
      orderBy: 'created_at ASC',
    );
    return rows.map(FavouriteLocation.fromJson).toList();
  }

  /// Update an existing favourite in place. The caller is
  /// responsible for bumping [FavouriteLocation.updatedAt] before
  /// calling.
  Future<int> update(FavouriteLocation fav) async {
    if (fav.id == null) {
      throw ArgumentError('FavouriteLocation must have an ID to be updated');
    }
    final db = await database.open();
    return db.update(
      'favourite_locations',
      fav.toJson(),
      where: 'id = ?',
      whereArgs: [fav.id],
    );
  }

  /// Delete a favourite by id. Returns the number of rows affected
  /// (0 if the id didn't exist — a safe no-op).
  Future<int> delete(int id) async {
    final db = await database.open();
    return db.delete('favourite_locations', where: 'id = ?', whereArgs: [id]);
  }

  /// Delete every favourite. Used by tests for cleanup; not
  /// currently called from production code.
  Future<int> deleteAll() async {
    final db = await database.open();
    return db.delete('favourite_locations');
  }

  /// Count of saved favourites. Cheaper than [getAll] when the
  /// caller only needs the badge number on the "Saved places"
  /// entry on the alarms screen.
  Future<int> count() async {
    final db = await database.open();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM favourite_locations',
    );
    return (rows.first['c'] as int?) ?? 0;
  }
}
