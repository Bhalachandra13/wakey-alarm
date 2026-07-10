import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakey_alarm/data/wakey_database.dart';

void main() {
  late WakeyDatabase wakeyDatabase;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    wakeyDatabase = WakeyDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
  });

  tearDown(() async {
    await wakeyDatabase.close();
  });

  test('creates alarms and timers schema at version 1', () async {
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
      ]),
    );
  });
}

Future<List<String>> _columnNames(Database database, String tableName) async {
  final rows = await database.rawQuery('PRAGMA table_info($tableName)');
  return rows.map((row) => row['name']! as String).toList();
}
