import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';

/// Test double for [AlarmBridge] that exposes a controllable event
/// stream and records every native method call.
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

/// Polls the provider's value until [predicate] returns true, or times out.
/// Returns the value of [predicate] at the end.
Future<bool> _waitFor(
  ProviderContainer container,
  bool Function(int? value) predicate, {
  Duration step = const Duration(milliseconds: 20),
  int maxIterations = 50,
}) async {
  for (var i = 0; i < maxIterations; i++) {
    final value = container.read(ringingAlarmIdProvider).value;
    if (predicate(value)) return true;
    await Future<void>.delayed(step);
  }
  return predicate(container.read(ringingAlarmIdProvider).value);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ringingAlarmIdProvider', () {
    late _FakeAlarmBridge fakeBridge;
    late ProviderContainer container;
    late ProviderSubscription<AsyncValue<int?>> subscription;

    setUp(() {
      fakeBridge = _FakeAlarmBridge();
      container = ProviderContainer(
        overrides: [alarmBridgeProvider.overrideWithValue(fakeBridge)],
      );
      // Start the async generator before any events are added so the
      // stream subscription is wired up. (Broadcast streams do not
      // replay missed events.)
      subscription = container.listen<AsyncValue<int?>>(
        ringingAlarmIdProvider,
        (prev, next) {},
      );
    });

    tearDown(() async {
      subscription.close();
      container.dispose();
      await fakeBridge.eventController.close();
    });

    test('starts with null when no alarm is ringing', () async {
      final settled = await _waitFor(container, (v) => v == null);
      expect(settled, isTrue);
      expect(container.read(ringingAlarmIdProvider).value, isNull);
    });

    test('emits alarmId when a fired event arrives', () async {
      final initialSettled = await _waitFor(container, (v) => v == null);
      expect(initialSettled, isTrue);

      fakeBridge.eventController.add(
        const AlarmEvent(
          alarmId: 42,
          type: AlarmEventType.fired,
          triggerType: 'time',
        ),
      );
      final settled = await _waitFor(container, (v) => v == 42);
      expect(
        settled,
        isTrue,
        reason: 'fired event should propagate to provider',
      );
      expect(container.read(ringingAlarmIdProvider).value, 42);
    });

    test('emits null when a dismissed event arrives', () async {
      await _waitFor(container, (v) => v == null);

      fakeBridge.eventController.add(
        const AlarmEvent(
          alarmId: 7,
          type: AlarmEventType.fired,
          triggerType: 'time',
        ),
      );
      final firedSettled = await _waitFor(container, (v) => v == 7);
      expect(firedSettled, isTrue);

      fakeBridge.eventController.add(
        const AlarmEvent(alarmId: 7, type: AlarmEventType.dismissed),
      );
      final settled = await _waitFor(container, (v) => v == null);
      expect(
        settled,
        isTrue,
        reason: 'dismissed event should clear ringing state',
      );
      expect(container.read(ringingAlarmIdProvider).value, isNull);
    });

    test('emits null when a snoozed event arrives', () async {
      await _waitFor(container, (v) => v == null);

      fakeBridge.eventController.add(
        const AlarmEvent(
          alarmId: 9,
          type: AlarmEventType.fired,
          triggerType: 'time',
        ),
      );
      final firedSettled = await _waitFor(container, (v) => v == 9);
      expect(firedSettled, isTrue);

      fakeBridge.eventController.add(
        const AlarmEvent(alarmId: 9, type: AlarmEventType.snoozed),
      );
      final settled = await _waitFor(container, (v) => v == null);
      expect(
        settled,
        isTrue,
        reason: 'snoozed event should clear ringing state',
      );
      expect(container.read(ringingAlarmIdProvider).value, isNull);
    });

    test(
      'tracks the latest firing when a new alarm fires after a dismiss',
      () async {
        await _waitFor(container, (v) => v == null);

        fakeBridge.eventController.add(
          const AlarmEvent(
            alarmId: 1,
            type: AlarmEventType.fired,
            triggerType: 'time',
          ),
        );
        await _waitFor(container, (v) => v == 1);

        fakeBridge.eventController.add(
          const AlarmEvent(alarmId: 1, type: AlarmEventType.dismissed),
        );
        await _waitFor(container, (v) => v == null);

        fakeBridge.eventController.add(
          const AlarmEvent(
            alarmId: 2,
            type: AlarmEventType.fired,
            triggerType: 'time',
          ),
        );
        final settled = await _waitFor(container, (v) => v == 2);
        expect(
          settled,
          isTrue,
          reason: 'second alarm should overwrite the first',
        );
        expect(container.read(ringingAlarmIdProvider).value, 2);
      },
    );
  });
}
