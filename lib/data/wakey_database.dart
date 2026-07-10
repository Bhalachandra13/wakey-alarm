import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart' as sqflite;

class WakeyDatabase {
  WakeyDatabase({sqflite.DatabaseFactory? databaseFactory, this.databasePath})
    : _databaseFactory = databaseFactory ?? sqflite.databaseFactory;

  static const databaseName = 'wakey_wakey.db';
  static const databaseVersion = 1;

  final sqflite.DatabaseFactory _databaseFactory;
  final String? databasePath;

  sqflite.Database? _database;

  Future<sqflite.Database> open() async {
    final existingDatabase = _database;
    if (existingDatabase != null) {
      return existingDatabase;
    }

    final resolvedDatabasePath =
        databasePath ??
        path.join(await _databaseFactory.getDatabasesPath(), databaseName);

    final database = await _databaseFactory.openDatabase(
      resolvedDatabasePath,
      options: sqflite.OpenDatabaseOptions(
        version: databaseVersion,
        onCreate: _createSchema,
        onUpgrade: _migrateSchema,
      ),
    );
    _database = database;
    return database;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  static Future<void> _createSchema(sqflite.Database db, int version) async {
    await db.execute('''
      CREATE TABLE alarms (
        id INTEGER PRIMARY KEY,
        label TEXT NOT NULL,
        trigger_type TEXT NOT NULL,
        time_hour INTEGER,
        time_minute INTEGER,
        repeat_days TEXT,
        latitude REAL,
        longitude REAL,
        radius_meters INTEGER,
        is_enabled INTEGER NOT NULL DEFAULT 1,
        is_armed INTEGER NOT NULL DEFAULT 0,
        sound_uri TEXT NOT NULL,
        vibrate INTEGER NOT NULL DEFAULT 1,
        snooze_duration_min INTEGER NOT NULL DEFAULT 10,
        max_snooze_count INTEGER,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE timers (
        id INTEGER PRIMARY KEY,
        label TEXT NOT NULL,
        duration_seconds INTEGER NOT NULL,
        remaining_seconds INTEGER NOT NULL,
        state TEXT NOT NULL,
        started_at TEXT
      )
    ''');
  }

  static Future<void> _migrateSchema(
    sqflite.Database db,
    int oldVersion,
    int newVersion,
  ) async {
    for (var version = oldVersion + 1; version <= newVersion; version++) {
      switch (version) {
        case databaseVersion:
          break;
        default:
          throw UnsupportedError('No migration registered for v$version');
      }
    }
  }
}
