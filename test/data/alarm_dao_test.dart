import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakey_alarm/data/alarm_dao.dart';
import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/domain/alarm.dart';

void main() {
  late WakeyDatabase database;
  late AlarmDao alarmDao;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    database = WakeyDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: ':memory:',
    );
    alarmDao = AlarmDao(database);
    await database.open();
  });

  tearDown(() async {
    await database.close();
  });

  Alarm createTestAlarm({
    String label = 'Test Alarm',
    AlarmTriggerType triggerType = AlarmTriggerType.time,
    int? timeHour = 7,
    int? timeMinute = 0,
    bool isEnabled = true,
    bool isArmed = false,
    double? latitude,
    double? longitude,
    int? radiusMeters,
  }) {
    final now = DateTime.now().toIso8601String();
    return Alarm(
      label: label,
      triggerType: triggerType,
      timeHour: timeHour,
      timeMinute: timeMinute,
      isEnabled: isEnabled,
      isArmed: isArmed,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      soundUri: 'system://ringtone',
      vibrate: true,
      snoozeDurationMin: 10,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('AlarmDao', () {
    test('insert creates a new alarm and returns its ID', () async {
      final alarm = createTestAlarm();

      final id = await alarmDao.insert(alarm);

      expect(id, isNotNull);
      expect(id, greaterThan(0));
    });

    test('read retrieves an alarm by ID', () async {
      final alarm = createTestAlarm(label: 'Morning Alarm', timeHour: 7);

      final id = await alarmDao.insert(alarm);
      final retrieved = await alarmDao.read(id);

      expect(retrieved, isNotNull);
      expect(retrieved!.label, equals('Morning Alarm'));
      expect(retrieved.timeHour, equals(7));
    });

    test('read returns null for non-existent alarm', () async {
      final retrieved = await alarmDao.read(999);
      expect(retrieved, isNull);
    });

    test('getAll retrieves all alarms', () async {
      final alarm1 = createTestAlarm(label: 'Morning Alarm');
      final alarm2 = createTestAlarm(label: 'Evening Alarm', timeHour: 18);

      await alarmDao.insert(alarm1);
      await alarmDao.insert(alarm2);
      final allAlarms = await alarmDao.getAll();

      expect(allAlarms, hasLength(2));
      expect(allAlarms[0].label, equals('Morning Alarm'));
      expect(allAlarms[1].label, equals('Evening Alarm'));
    });

    test('update modifies an existing alarm', () async {
      final alarm = createTestAlarm(label: 'Morning Alarm');

      final id = await alarmDao.insert(alarm);
      final updatedAlarm = alarm.copyWith(
        id: id,
        label: 'Updated Morning Alarm',
      );
      final rowsAffected = await alarmDao.update(updatedAlarm);

      expect(rowsAffected, equals(1));
      final retrieved = await alarmDao.read(id);
      expect(retrieved!.label, equals('Updated Morning Alarm'));
    });

    test('update throws ArgumentError if alarm has no ID', () async {
      final alarm = createTestAlarm();

      expect(() => alarmDao.update(alarm), throwsA(isA<ArgumentError>()));
    });

    test('delete removes an alarm', () async {
      final alarm = createTestAlarm();

      final id = await alarmDao.insert(alarm);
      final rowsAffected = await alarmDao.delete(id);

      expect(rowsAffected, equals(1));
      final retrieved = await alarmDao.read(id);
      expect(retrieved, isNull);
    });

    test('deleteAll removes all alarms', () async {
      final alarm1 = createTestAlarm(label: 'Alarm 1');
      final alarm2 = createTestAlarm(label: 'Alarm 2', timeHour: 8);

      await alarmDao.insert(alarm1);
      await alarmDao.insert(alarm2);
      final rowsAffected = await alarmDao.deleteAll();

      expect(rowsAffected, equals(2));
      final allAlarms = await alarmDao.getAll();
      expect(allAlarms, isEmpty);
    });

    test('getEnabledAlarms retrieves only enabled alarms', () async {
      final enabledAlarm = createTestAlarm(
        label: 'Enabled Alarm',
        isEnabled: true,
      );
      final disabledAlarm = createTestAlarm(
        label: 'Disabled Alarm',
        isEnabled: false,
      );

      await alarmDao.insert(enabledAlarm);
      await alarmDao.insert(disabledAlarm);
      final enabledAlarms = await alarmDao.getEnabledAlarms();

      expect(enabledAlarms, hasLength(1));
      expect(enabledAlarms[0].label, equals('Enabled Alarm'));
    });

    test('updateArmed updates is_armed flag', () async {
      final alarm = createTestAlarm(isArmed: false);

      final id = await alarmDao.insert(alarm);
      final rowsAffected = await alarmDao.updateArmed(id, true);

      expect(rowsAffected, equals(1));
      final retrieved = await alarmDao.read(id);
      expect(retrieved!.isArmed, isTrue);
    });

    test('updateEnabled updates is_enabled flag', () async {
      final alarm = createTestAlarm(isEnabled: true);

      final id = await alarmDao.insert(alarm);
      final rowsAffected = await alarmDao.updateEnabled(id, false);

      expect(rowsAffected, equals(1));
      final retrieved = await alarmDao.read(id);
      expect(retrieved!.isEnabled, isFalse);
    });

    test('location trigger alarm CRUD works', () async {
      final locationAlarm = createTestAlarm(
        label: 'Home Alarm',
        triggerType: AlarmTriggerType.location,
        timeHour: null,
        timeMinute: null,
        latitude: 40.7128,
        longitude: -74.0060,
        radiusMeters: 500,
      );

      final id = await alarmDao.insert(locationAlarm);
      final retrieved = await alarmDao.read(id);

      expect(retrieved, isNotNull);
      expect(retrieved!.triggerType, equals(AlarmTriggerType.location));
      expect(retrieved.latitude, equals(40.7128));
      expect(retrieved.longitude, equals(-74.0060));
      expect(retrieved.radiusMeters, equals(500));
    });
  });
}
