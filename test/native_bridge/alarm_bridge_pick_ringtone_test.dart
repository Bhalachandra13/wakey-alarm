import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/native_bridge/alarm_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AlarmBridge.pickRingtone', () {
    final channel = MethodChannel('com.wakeywakey/alarm_bridge');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
    });

    test('returns the URI string from the native picker', () async {
      String? receivedCurrentUri;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'pickRingtone') {
          receivedCurrentUri = call.arguments['currentUri'] as String?;
          return <String, Object?>{
            'uri': 'content://media/system/alarms/picked',
          };
        }
        return null;
      });

      final bridge = const AlarmBridge();
      final result = await bridge.pickRingtone(currentUri: 'content://old');

      expect(result, 'content://media/system/alarms/picked');
      expect(receivedCurrentUri, 'content://old');
    });

    test('returns null when the user cancels the picker', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'pickRingtone') {
          return <String, Object?>{'uri': null};
        }
        return null;
      });

      final bridge = const AlarmBridge();
      final result = await bridge.pickRingtone(currentUri: 'content://old');

      expect(result, isNull);
    });

    test('passes null currentUri when no alarm sound is set yet', () async {
      String? receivedCurrentUri;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'pickRingtone') {
          receivedCurrentUri = call.arguments['currentUri'] as String?;
          return <String, Object?>{'uri': 'content://picked'};
        }
        return null;
      });

      final bridge = const AlarmBridge();
      await bridge.pickRingtone();

      expect(receivedCurrentUri, isNull);
    });
  });
}
