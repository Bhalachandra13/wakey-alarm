import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
  });

  Alarm createTestAlarm({
    String label = 'Test Alarm',
    AlarmTriggerType triggerType = AlarmTriggerType.time,
    int? timeHour = 7,
    int? timeMinute = 0,
    bool isEnabled = true,
    bool isArmed = false,
  }) {
    final now = DateTime.now().toIso8601String();
    return Alarm(
      label: label,
      triggerType: triggerType,
      timeHour: timeHour,
      timeMinute: timeMinute,
      isEnabled: isEnabled,
      isArmed: isArmed,
      soundUri: 'system://ringtone',
      vibrate: true,
      snoozeDurationMin: 10,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('Alarms Riverpod providers', () {
    late WakeyDatabase database;
    late ProviderContainer container;
    late _FakeAlarmBridge fakeBridge;

    setUp(() async {
      fakeBridge = _FakeAlarmBridge();
      addTearDown(fakeBridge.eventController.close);

      database = WakeyDatabase(
        databaseFactory: databaseFactoryFfi,
        databasePath: ':memory:',
      );
      await database.open();

      // Override database provider with in-memory instance, and the
      // AlarmBridge with a fake so the notifier's build() can listen
      // to the event stream and the scheduler can call scheduleAlarm /
      // cancelAlarm without hitting the missing native MethodChannel.
      // Also override alarmEventsProvider to emit nothing — the notifier
      // only cares about snoozed/dismissed events and none of these tests
      // exercise that path. A never-completing broadcast stream would
      // otherwise keep the test isolate alive past the test function
      // returning, causing a spurious 30s timeout.
      container = ProviderContainer(
        overrides: [
          databaseProvider.overrideWithValue(database),
          alarmBridgeProvider.overrideWithValue(fakeBridge),
          alarmEventsProvider.overrideWith((ref) => const Stream.empty()),
        ],
      );
    });

    tearDown(() async {
      await database.close();
      container.dispose();
    });

    test('alarmsProvider loads empty list when database is empty', () async {
      final state = container.read(alarmsProvider);

      expect(state.isLoading, isTrue);

      // Wait for async load to complete
      final alarms = await container.read(alarmsNotifierProvider.future);
      expect(alarms, isEmpty);
    });

    test('insertAlarm adds alarm to list', () async {
      final notifier = container.read(alarmsNotifierProvider.notifier);
      final alarm = createTestAlarm(label: 'Morning Alarm');

      final id = await notifier.insertAlarm(alarm);

      expect(id, greaterThan(0));

      // Refresh and check
      final alarms = await container.read(alarmsNotifierProvider.future);
      expect(alarms, hasLength(1));
      expect(alarms[0].label, equals('Morning Alarm'));
    });

    test('updateAlarm modifies existing alarm', () async {
      final notifier = container.read(alarmsNotifierProvider.notifier);
      final alarm = createTestAlarm(label: 'Original');

      final id = await notifier.insertAlarm(alarm);
      final updated = alarm.copyWith(id: id, label: 'Updated');
      await notifier.updateAlarm(updated);

      final alarms = await container.read(alarmsNotifierProvider.future);
      expect(alarms, hasLength(1));
      expect(alarms[0].label, equals('Updated'));
    });

    test('deleteAlarm removes alarm from list', () async {
      final notifier = container.read(alarmsNotifierProvider.notifier);
      final alarm = createTestAlarm();

      final id = await notifier.insertAlarm(alarm);
      await notifier.deleteAlarm(id);

      final alarms = await container.read(alarmsNotifierProvider.future);
      expect(alarms, isEmpty);
    });

    test('toggleEnabled changes isEnabled state', () async {
      final notifier = container.read(alarmsNotifierProvider.notifier);
      final alarm = createTestAlarm(isEnabled: true);

      final id = await notifier.insertAlarm(alarm);
      await notifier.toggleEnabled(id, false);

      final alarms = await container.read(alarmsNotifierProvider.future);
      expect(alarms[0].isEnabled, isFalse);
    });

    test('toggleArmed changes isArmed state', () async {
      final notifier = container.read(alarmsNotifierProvider.notifier);
      final alarm = createTestAlarm(isArmed: false);

      final id = await notifier.insertAlarm(alarm);
      await notifier.toggleArmed(id, true);

      final alarms = await container.read(alarmsNotifierProvider.future);
      expect(alarms[0].isArmed, isTrue);
    });

    test('supports multiple alarms', () async {
      final notifier = container.read(alarmsNotifierProvider.notifier);

      final alarm1 = createTestAlarm(label: 'Alarm 1', timeHour: 7);
      final alarm2 = createTestAlarm(label: 'Alarm 2', timeHour: 8);
      final alarm3 = createTestAlarm(label: 'Alarm 3', timeHour: 9);

      await notifier.insertAlarm(alarm1);
      await notifier.insertAlarm(alarm2);
      await notifier.insertAlarm(alarm3);

      final alarms = await container.read(alarmsNotifierProvider.future);
      expect(alarms, hasLength(3));
      expect(alarms[0].label, equals('Alarm 1'));
      expect(alarms[1].label, equals('Alarm 2'));
      expect(alarms[2].label, equals('Alarm 3'));
    });

    test('enabledAlarmsProvider returns only enabled alarms', () async {
      final dao = container.read(alarmDaoProvider);

      final enabledAlarm = createTestAlarm(label: 'Enabled', isEnabled: true);
      final disabledAlarm = createTestAlarm(
        label: 'Disabled',
        isEnabled: false,
      );

      await dao.insert(enabledAlarm);
      await dao.insert(disabledAlarm);

      final enabled = await container.read(enabledAlarmsProvider.future);
      expect(enabled, hasLength(1));
      expect(enabled[0].label, equals('Enabled'));
    });

    test('alarmByIdProvider retrieves single alarm', () async {
      final notifier = container.read(alarmsNotifierProvider.notifier);
      final alarm = createTestAlarm(label: 'Test Alarm');

      final id = await notifier.insertAlarm(alarm);

      final retrieved = await container.read(alarmByIdProvider(id).future);
      expect(retrieved, isNotNull);
      expect(retrieved!.label, equals('Test Alarm'));
    });

    test('alarmByIdProvider returns null for non-existent ID', () async {
      final retrieved = await container.read(alarmByIdProvider(999).future);
      expect(retrieved, isNull);
    });

    test('refresh reloads from database', () async {
      final dao = container.read(alarmDaoProvider);
      final notifier = container.read(alarmsNotifierProvider.notifier);

      final alarm = createTestAlarm(label: 'Original');
      await dao.insert(alarm);

      // Refresh provider
      await notifier.refresh();

      final alarms = await container.read(alarmsNotifierProvider.future);
      expect(alarms, hasLength(1));
      expect(alarms[0].label, equals('Original'));
    });
  });
}

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
  Future<bool> cancelAlarm(int alarmId) async => true;
  @override
  Future<String?> pickRingtone({String? currentUri}) async => null;
}
