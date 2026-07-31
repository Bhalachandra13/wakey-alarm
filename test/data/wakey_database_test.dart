import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakey_alarm/data/wakey_database.dart';

void main() {
  late WakeyDatabase wakeyDatabase;
  late String tempDir;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wakey_db_test_').path;
    wakeyDatabase = WakeyDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: p.join(tempDir, 'wakey.db'),
    );
  });

  tearDown(() async {
    await wakeyDatabase.close();
    try {
      Directory(tempDir).deleteSync(recursive: true);
    } on FileSystemException {
      // Best-effort cleanup; the OS will reap /tmp eventually.
    }
  });

  test('creates alarms and timers schema at the current version', () async {
    final database = await wakeyDatabase.open();

    expect(await database.getVersion(), WakeyDatabase.databaseVersion);
    expect(
      await _columnNames(database, 'alarms'),
      containsAll(<String>[
        'id',
        'label',
        'trigger_type',
        'time_hour',
        'time_minute',
        'repeat_days',
        'latitude',
        'longitude',
        'radius_meters',
        'is_enabled',
        'is_armed',
        'sound_uri',
        'vibrate',
        'snooze_duration_min',
        'max_snooze_count',
        'created_at',
        'updated_at',
      ]),
    );
    expect(
      await _columnNames(database, 'timers'),
      containsAll(<String>[
        'id',
        'label',
        'duration_seconds',
        'remaining_seconds',
        'state',
        'started_at',
        // v2 added this column so a timer's snooze can survive a
        // pause/resume cycle.
        'snooze_duration_min',
      ]),
    );
  });

  test('migration from v1 to v2 adds snooze_duration_min to timers', () async {
    // Open the database at v1 with a hand-written schema to simulate
    // a pre-existing v1 install. Then re-open at the current version
    // to trigger the migration and verify the new column was added.
    final factory = databaseFactoryFfi;
    final v1Path = p.join(tempDir, 'migration.db');
    final v1Db = await factory.openDatabase(
      v1Path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          // Minimal v1 schema — only the timers table is needed for
          // this migration test.
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
        },
      ),
    );
    await v1Db.insert('timers', {
      'id': 1,
      'label': 'legacy',
      'duration_seconds': 60,
      'remaining_seconds': 30,
      'state': 'PAUSED',
      'started_at': '2026-07-31T08:00:00.000Z',
    });
    await v1Db.close();

    final migrated = WakeyDatabase(
      databaseFactory: factory,
      databasePath: v1Path,
    );
    final database = await migrated.open();

    expect(await database.getVersion(), WakeyDatabase.databaseVersion);
    // The new column should be present, and legacy rows should have
    // it populated with the migration default (5).
    final rows = await database.query('timers');
    expect(rows, hasLength(1));
    expect(rows.first['snooze_duration_min'], 5);
  });
}

Future<List<String>> _columnNames(Database database, String tableName) async {
  final rows = await database.rawQuery('PRAGMA table_info($tableName)');
  return rows.map((row) => row['name']! as String).toList();
}
