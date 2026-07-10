import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakey_alarm/data/alarm_dao.dart';
import 'package:wakey_alarm/data/wakey_database.dart';
import 'package:wakey_alarm/domain/alarm.dart';

/// Provides access to the [WakeyDatabase] singleton.
final databaseProvider = Provider<WakeyDatabase>((ref) {
  return WakeyDatabase();
});

/// Provides access to the [AlarmDao] singleton.
final alarmDaoProvider = Provider<AlarmDao>((ref) {
  final database = ref.watch(databaseProvider);
  return AlarmDao(database);
});

/// AsyncNotifier for managing the list of alarms.
class AlarmsNotifier extends AsyncNotifier<List<Alarm>> {
  late AlarmDao _alarmDao;

  @override
  Future<List<Alarm>> build() async {
    _alarmDao = ref.watch(alarmDaoProvider);
    return _alarmDao.getAll();
  }

  /// Insert a new alarm and refresh the list.
  Future<int> insertAlarm(Alarm alarm) async {
    final id = await _alarmDao.insert(alarm);
    // Refresh the list after insert
    ref.invalidateSelf();
    return id;
  }

  /// Update an existing alarm and refresh the list.
  Future<void> updateAlarm(Alarm alarm) async {
    await _alarmDao.update(alarm);
    // Refresh the list after update
    ref.invalidateSelf();
  }

  /// Delete an alarm by ID and refresh the list.
  Future<void> deleteAlarm(int id) async {
    await _alarmDao.delete(id);
    // Refresh the list after delete
    ref.invalidateSelf();
  }

  /// Toggle the enabled state of an alarm.
  Future<void> toggleEnabled(int id, bool newState) async {
    await _alarmDao.updateEnabled(id, newState);
    // Refresh the list after toggle
    ref.invalidateSelf();
  }

  /// Toggle the armed state of an alarm (for location-based alarms).
  Future<void> toggleArmed(int id, bool newState) async {
    await _alarmDao.updateArmed(id, newState);
    // Refresh the list after toggle
    ref.invalidateSelf();
  }

  /// Refresh the alarms list from the database.
  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}

/// Provider for the alarms notifier, which manages the list of alarms
/// and provides CRUD operations.
final alarmsNotifierProvider =
    AsyncNotifierProvider<AlarmsNotifier, List<Alarm>>(AlarmsNotifier.new);

/// Convenience provider to access the current alarms list directly.
/// Use this when you only need to read the alarms, not modify them.
final alarmsProvider = Provider<AsyncValue<List<Alarm>>>((ref) {
  return ref.watch(alarmsNotifierProvider);
});

/// Get a single alarm by ID (derived from the alarms list).
final alarmByIdProvider = FutureProvider.family<Alarm?, int>((ref, id) async {
  final alarmDao = ref.watch(alarmDaoProvider);
  return alarmDao.read(id);
});

/// Get only enabled alarms.
final enabledAlarmsProvider = FutureProvider<List<Alarm>>((ref) async {
  final alarmDao = ref.watch(alarmDaoProvider);
  return alarmDao.getEnabledAlarms();
});
