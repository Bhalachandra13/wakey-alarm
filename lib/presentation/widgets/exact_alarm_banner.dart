import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';

/// Banner shown when the app is missing the `SCHEDULE_EXACT_ALARM`
/// permission. Without it, Android 12+ will reject every
/// `setAlarmClock` call with a `SecurityException`, and the alarm or
/// timer will never fire — even though the user's toggle is ON.
///
/// Tapping the banner launches the system Settings page that lets
/// the user grant the permission; afterwards the banner re-checks
/// and disappears if the user has enabled it.
///
/// This widget is shared between the Alarms and Timer tabs because
/// both tabs use the same `AlarmManager.setAlarmClock` pipeline.
class ExactAlarmPermissionBanner extends ConsumerStatefulWidget {
  const ExactAlarmPermissionBanner({super.key});

  @override
  ConsumerState<ExactAlarmPermissionBanner> createState() =>
      _ExactAlarmPermissionBannerState();
}

class _ExactAlarmPermissionBannerState
    extends ConsumerState<ExactAlarmPermissionBanner>
    with WidgetsBindingObserver {
  bool? _canSchedule;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Re-check when the app returns to the foreground: the user may
  /// have just granted the permission from the system Settings page
  /// launched by tapping the banner.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final bridge = ref.read(permissionBridgeProvider);
    final can = await bridge.canScheduleExactAlarms();
    if (mounted) {
      setState(() => _canSchedule = can);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_canSchedule != false) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.tertiaryContainer,
      child: InkWell(
        onTap: () async {
          final bridge = ref.read(permissionBridgeProvider);
          await bridge.requestExactAlarmPermission();
          await _refresh();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.alarm, color: theme.colorScheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Wakey-Wakey needs exact alarm permission to fire alarms and timers. Tap to grant.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
