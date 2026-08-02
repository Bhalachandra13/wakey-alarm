import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/domain/timer_record.dart';

/// Data Access Object for [TimerRecord] CRUD operations.
class TimerDao {
  TimerDao(this.database);

  final WakeyDatabase database;

  /// Insert a new timer. Returns the inserted row id.
  Future<int> insert(TimerRecord record) async {
    final db = await database.open();
    return db.insert(
      'timers',
      record.toJson(),
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  /// Read a single timer by id.
  Future<TimerRecord?> read(int id) async {
    final db = await database.open();
    final rows = await db.query('timers', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return TimerRecord.fromJson(rows.first);
  }

  /// Read every timer. Ordering is by `started_at` descending so the
  /// most recently-started timer appears first in the UI.
  Future<List<TimerRecord>> getAll() async {
    final db = await database.open();
    final rows = await db.query('timers', orderBy: 'started_at DESC');
    return rows.map(TimerRecord.fromJson).toList();
  }

  /// Read only active timers (RUNNING or PAUSED). Used by the UI to
  /// render the live list, which doesn't need the historical
  /// COMPLETED/CANCELLED rows.
  Future<List<TimerRecord>> getActive() async {
    final db = await database.open();
    final rows = await db.query(
      'timers',
      where: 'state IN (?, ?)',
      whereArgs: ['RUNNING', 'PAUSED'],
      orderBy: 'started_at DESC',
    );
    return rows.map(TimerRecord.fromJson).toList();
  }

  Future<int> update(TimerRecord record) async {
    if (record.id == null) {
      throw ArgumentError('TimerRecord must have an ID to be updated');
    }
    final db = await database.open();
    return db.update(
      'timers',
      record.toJson(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await database.open();
    return db.delete('timers', where: 'id = ?', whereArgs: [id]);
  }

  /// Update only the persisted `remaining_seconds` for a timer.
  /// Used when the native ringing/snooze flow takes over a timer
  /// (the row is pinned to 0 so the UI fallback shows 00:00 rather
  /// than the run's base value). The countdown ticker itself never
  /// writes — while RUNNING, `remaining_seconds` is the immutable
  /// base the live countdown is derived from.
  Future<int> updateRemaining(int id, int remainingSeconds) async {
    final db = await database.open();
    return db.update(
      'timers',
      {'remaining_seconds': remainingSeconds},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Update the [TimerState.state] of a timer.
  Future<int> updateState(int id, TimerState state) async {
    final db = await database.open();
    return db.update(
      'timers',
      {'state': state.value},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Remove every completed/cancelled timer. Used by the cleanup
  /// pass on app startup so the list doesn't grow unbounded.
  Future<int> deleteFinished() async {
    final db = await database.open();
    return db.delete(
      'timers',
      where: 'state IN (?, ?)',
      whereArgs: ['COMPLETED', 'CANCELLED'],
    );
  }
}
