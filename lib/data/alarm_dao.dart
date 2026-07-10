import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/data/wakey_database.dart';

/// Data Access Object for Alarm CRUD operations.
class AlarmDao {
  final WakeyDatabase database;

  AlarmDao(this.database);

  /// Insert a new alarm into the database.
  /// Returns the ID of the inserted alarm.
  Future<int> insert(Alarm alarm) async {
    final db = await database.open();
    return db.insert(
      'alarms',
      alarm.toJson(),
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  /// Fetch an alarm by ID.
  Future<Alarm?> read(int id) async {
    final db = await database.open();
    final result = await db.query('alarms', where: 'id = ?', whereArgs: [id]);

    if (result.isEmpty) {
      return null;
    }
    return Alarm.fromJson(result.first);
  }

  /// Fetch all alarms.
  Future<List<Alarm>> getAll() async {
    final db = await database.open();
    final result = await db.query('alarms');
    return result.map((row) => Alarm.fromJson(row)).toList();
  }

  /// Update an existing alarm.
  /// Returns the number of rows affected.
  Future<int> update(Alarm alarm) async {
    if (alarm.id == null) {
      throw ArgumentError('Alarm must have an ID to be updated');
    }
    final db = await database.open();
    return db.update(
      'alarms',
      alarm.toJson(),
      where: 'id = ?',
      whereArgs: [alarm.id],
    );
  }

  /// Delete an alarm by ID.
  /// Returns the number of rows affected.
  Future<int> delete(int id) async {
    final db = await database.open();
    return db.delete('alarms', where: 'id = ?', whereArgs: [id]);
  }

  /// Fetch all enabled alarms.
  Future<List<Alarm>> getEnabledAlarms() async {
    final db = await database.open();
    final result = await db.query(
      'alarms',
      where: 'is_enabled = ?',
      whereArgs: [1],
    );
    return result.map((row) => Alarm.fromJson(row)).toList();
  }

  /// Update the is_armed flag for an alarm.
  Future<int> updateArmed(int id, bool isArmed) async {
    final db = await database.open();
    return db.update(
      'alarms',
      {
        'is_armed': isArmed ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Update the is_enabled flag for an alarm.
  Future<int> updateEnabled(int id, bool isEnabled) async {
    final db = await database.open();
    return db.update(
      'alarms',
      {
        'is_enabled': isEnabled ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete all alarms.
  Future<int> deleteAll() async {
    final db = await database.open();
    return db.delete('alarms');
  }
}
