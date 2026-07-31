import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wakey_alarm/native_bridge/permission_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/widgets/exact_alarm_banner.dart';

void main() {
  group('ExactAlarmPermissionBanner', () {
    testWidgets('shows banner when canScheduleExactAlarms returns false', (
      tester,
    ) async {
      final bridge = _FakePermissionBridge(canSchedule: false);
      addTearDown(bridge.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            permissionBridgeProvider.overrideWithValue(bridge),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ExactAlarmPermissionBanner()),
          ),
        ),
      );
      await _pumpUntilBannerVisible(tester);

      expect(
        find.textContaining('exact alarm'),
        findsOneWidget,
        reason: 'Banner should explain that exact-alarm permission is needed',
      );
      expect(find.byIcon(Icons.alarm), findsOneWidget);
    });

    testWidgets('hides banner when canScheduleExactAlarms returns true', (
      tester,
    ) async {
      final bridge = _FakePermissionBridge(canSchedule: true);
      addTearDown(bridge.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            permissionBridgeProvider.overrideWithValue(bridge),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ExactAlarmPermissionBanner()),
          ),
        ),
      );
      // Pump a few frames to let the banner's _refresh complete.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(
        find.textContaining('exact alarm'),
        findsNothing,
        reason: 'Banner should be hidden when permission is granted',
      );
    });

    testWidgets('tapping the banner calls requestExactAlarmPermission', (
      tester,
    ) async {
      final bridge = _FakePermissionBridge(canSchedule: false);
      addTearDown(bridge.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            permissionBridgeProvider.overrideWithValue(bridge),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ExactAlarmPermissionBanner()),
          ),
        ),
      );
      await _pumpUntilBannerVisible(tester);

      await tester.tap(find.textContaining('exact alarm'));
      await tester.pump();

      expect(
        bridge.requestCount,
        1,
        reason: 'Tapping the banner should request exact-alarm permission',
      );
    });

    testWidgets('re-checks permission when app returns to foreground', (
      tester,
    ) async {
      final bridge = _FakePermissionBridge(canSchedule: false);
      addTearDown(bridge.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            permissionBridgeProvider.overrideWithValue(bridge),
          ],
          child: const MaterialApp(
            home: Scaffold(body: ExactAlarmPermissionBanner()),
          ),
        ),
      );
      await _pumpUntilBannerVisible(tester);
      expect(find.textContaining('exact alarm'), findsOneWidget);

      // Simulate the user granting the permission while in Settings.
      bridge.canSchedule = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await _pumpUntilBannerGone(tester);

      expect(
        find.textContaining('exact alarm'),
        findsNothing,
        reason: 'Banner should disappear after permission is granted on resume',
      );
    });
  });
}

Future<void> _pumpUntilBannerVisible(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.textContaining('exact alarm').evaluate().isNotEmpty) return;
  }
}

Future<void> _pumpUntilBannerGone(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.textContaining('exact alarm').evaluate().isEmpty) return;
  }
}

class _FakePermissionBridge implements PermissionBridge {
  _FakePermissionBridge({required this.canSchedule});

  bool canSchedule;
  int requestCount = 0;

  void dispose() {}

  @override
  Future<bool> canScheduleExactAlarms() async => canSchedule;

  @override
  Future<bool> requestExactAlarmPermission() async {
    requestCount++;
    canSchedule = true;
    return true;
  }

  @override
  Future<NativePermissionStatus> getNotificationPermissionStatus() async =>
      NativePermissionStatus.granted;

  @override
  Future<NativePermissionStatus> requestNotificationPermission() async =>
      NativePermissionStatus.granted;
}
