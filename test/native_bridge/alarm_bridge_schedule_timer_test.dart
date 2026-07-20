import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AlarmBridge.scheduleTimer', () {
    final channel = MethodChannel('com.wakeywakey/alarm_bridge');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    test(
      'sends the payload on the scheduleAlarm method with triggerType=TIMER',
      () async {
        MethodCall? captured;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'scheduleAlarm') {
            captured = call;
            return <String, Object?>{'scheduled': true};
          }
          return null;
        });

        final bridge = const AlarmBridge();
        final ok = await bridge.scheduleTimer({
          'alarmId': 7,
          'triggerAtMillis': 1700000000000,
          'label': 'Boil eggs',
        });

        expect(ok, isTrue);
        expect(captured, isNotNull);
        expect(captured!.method, 'scheduleAlarm');
        final args = Map<String, Object?>.from(captured!.arguments as Map);
        expect(args['triggerType'], 'TIMER');
        expect(args['alarmId'], 7);
        expect(args['triggerAtMillis'], 1700000000000);
        expect(args['label'], 'Boil eggs');
      },
    );

    test('returns false when native side reports scheduled=false', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'scheduleAlarm') {
          return <String, Object?>{'scheduled': false, 'error': 'nope'};
        }
        return null;
      });

      final bridge = const AlarmBridge();
      final ok = await bridge.scheduleTimer({
        'alarmId': 1,
        'triggerAtMillis': 1,
        'label': 'x',
      });
      expect(ok, isFalse);
    });
  });
}
