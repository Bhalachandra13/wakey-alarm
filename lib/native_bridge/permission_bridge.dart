import 'package:flutter/services.dart';

class PermissionBridge {
  PermissionBridge({MethodChannel? methodChannel})
    : _methodChannel =
          methodChannel ?? const MethodChannel('com.wakeywakey/permissions');

  final MethodChannel _methodChannel;

  Future<NativePermissionStatus> getNotificationPermissionStatus() async {
    final status = await _methodChannel.invokeMethod<String>(
      'getNotificationPermissionStatus',
    );
    return NativePermissionStatus.fromNativeValue(status);
  }

  Future<NativePermissionStatus> requestNotificationPermission() async {
    final status = await _methodChannel.invokeMethod<String>(
      'requestNotificationPermission',
    );
    return NativePermissionStatus.fromNativeValue(status);
  }

  Future<bool> canScheduleExactAlarms() async {
    return await _methodChannel.invokeMethod<bool>('canScheduleExactAlarms') ??
        false;
  }

  Future<bool> requestExactAlarmPermission() async {
    return await _methodChannel.invokeMethod<bool>(
          'requestExactAlarmPermission',
        ) ??
        false;
  }
}

enum NativePermissionStatus {
  granted,
  denied,
  notRequired,
  unknown;

  static NativePermissionStatus fromNativeValue(String? value) {
    return switch (value) {
      'granted' => NativePermissionStatus.granted,
      'denied' => NativePermissionStatus.denied,
      'notRequired' => NativePermissionStatus.notRequired,
      _ => NativePermissionStatus.unknown,
    };
  }
}
