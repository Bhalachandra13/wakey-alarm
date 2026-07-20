import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wakey_alarm/data/timer_dao.dart';
import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/domain/timer_record.dart';

void main() {
  late WakeyDatabase database;
  late TimerDao dao;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    database = WakeyDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: ':memory:',
    );
    dao = TimerDao(database);
    await database.open();
  });

  tearDown(() async {
    await database.close();
  });

  TimerRecord createRecord({
    String label = 'Test',
    int duration = 300,
    int remaining = 300,
    TimerState state = TimerState.running,
    String? startedAt,
  }) {
    return TimerRecord(
      label: label,
      durationSeconds: duration,
      remainingSeconds: remaining,
      state: state,
      startedAt: startedAt ?? DateTime.now().toIso8601String(),
    );
  }

  test('insert returns a positive id', () async {
    final id = await dao.insert(createRecord());
    expect(id, greaterThan(0));
  });

  test('read returns the inserted record', () async {
    final id = await dao.insert(createRecord(label: 'A'));
    final read = await dao.read(id);
    expect(read, isNotNull);
    expect(read!.label, 'A');
  });

  test('read returns null for non-existent id', () async {
    final read = await dao.read(999);
    expect(read, isNull);
  });

  test('getAll returns every record', () async {
    await dao.insert(createRecord(label: 'A'));
    await dao.insert(createRecord(label: 'B'));
    final all = await dao.getAll();
    expect(all, hasLength(2));
  });

  test('getActive returns only RUNNING and PAUSED records', () async {
    await dao.insert(createRecord(label: 'A', state: TimerState.running));
    await dao.insert(createRecord(label: 'B', state: TimerState.paused));
    await dao.insert(createRecord(label: 'C', state: TimerState.completed));
    await dao.insert(createRecord(label: 'D', state: TimerState.cancelled));
    final active = await dao.getActive();
    expect(active, hasLength(2));
    final labels = active.map((r) => r.label).toSet();
    expect(labels, containsAll({'A', 'B'}));
  });

  test('update modifies the record', () async {
    final id = await dao.insert(createRecord(label: 'A'));
    final updated = createRecord(label: 'A edited').copyWith(id: id);
    final rows = await dao.update(updated);
    expect(rows, 1);
    final read = await dao.read(id);
    expect(read!.label, 'A edited');
  });

  test('update throws ArgumentError if id is null', () async {
    expect(() => dao.update(createRecord()), throwsA(isA<ArgumentError>()));
  });

  test('delete removes the record', () async {
    final id = await dao.insert(createRecord());
    final rows = await dao.delete(id);
    expect(rows, 1);
    final read = await dao.read(id);
    expect(read, isNull);
  });

  test('updateRemaining persists new remaining seconds', () async {
    final id = await dao.insert(createRecord(remaining: 300));
    await dao.updateRemaining(id, 42);
    final read = await dao.read(id);
    expect(read!.remainingSeconds, 42);
    // Other fields unchanged.
    expect(read.durationSeconds, 300);
  });

  test('updateState persists new state', () async {
    final id = await dao.insert(createRecord(state: TimerState.running));
    await dao.updateState(id, TimerState.paused);
    final read = await dao.read(id);
    expect(read!.state, TimerState.paused);
  });

  test('deleteFinished removes COMPLETED and CANCELLED rows', () async {
    await dao.insert(createRecord(label: 'A', state: TimerState.completed));
    await dao.insert(createRecord(label: 'B', state: TimerState.cancelled));
    await dao.insert(createRecord(label: 'C', state: TimerState.running));
    final rows = await dao.deleteFinished();
    expect(rows, 2);
    final all = await dao.getAll();
    expect(all, hasLength(1));
    expect(all.first.label, 'C');
  });
}
