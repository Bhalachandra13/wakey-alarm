import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/native_bridge/geofence_bridge.dart';
import 'package:wakey_alarm/native_bridge/permission_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/screens/background_location_explanation_screen.dart';

/// One-screen, one-button "Get ready" wizard that walks the user
/// through every permission the app might need: notifications
/// (so the ringing UI can show), exact alarm (so time-based
/// alarms fire on Android 12+), foreground + background
/// location (so geofence alarms work), and battery-optimization
/// exemption (so OEM battery killers don't break alarms in
/// the background).
///
/// Replaces the previous three separate banners on the alarms
/// screen (`NotificationPermissionBanner`,
/// `ExactAlarmPermissionBanner`, `_GeofenceHealthBanner`). The
/// setup screen covers all of them, so the consolidation is
/// behaviour-preserving: every check + request that lived in
/// the individual banners is available here, just surfaced in
/// one place with one primary action.
///
/// Triggers:
///  * Auto-pushed on the first build of [AlarmsScreen] when
///    the `permissions_setup_shown` SharedPreferences flag is
///    false and at least one permission is missing — see
///    [maybeAutoShowOnFirstRun]. After the wizard completes
///    the flag is set so it doesn't auto-push again.
///  * Pushed manually when the user taps "Fix" on the
///    consolidated `_PermissionsHealthBanner`.
class PermissionsSetupScreen extends ConsumerStatefulWidget {
  const PermissionsSetupScreen({super.key});

  /// Show the screen as a pushed route. Returns `true` if the
  /// user completed the setup (tapped "Done" at the end or
  /// every step was already good), `false` if they dismissed
  /// via the close button without finishing.
  static Future<bool> show(BuildContext context) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const PermissionsSetupScreen()),
    );
    return result ?? false;
  }

  @override
  ConsumerState<PermissionsSetupScreen> createState() =>
      _PermissionsSetupScreenState();
}

class _PermissionsSetupScreenState
    extends ConsumerState<PermissionsSetupScreen> {
  // Cached statuses. `null` = not yet checked.
  NativePermissionStatus? _notifStatus;
  bool? _canScheduleExactAlarms;
  LocationPermissionStatus? _locationStatus;
  bool? _batteryExempt;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    final perm = ref.read(permissionBridgeProvider);
    final geo = ref.read(geofenceBridgeProvider);
    final results = await Future.wait([
      perm.getNotificationPermissionStatus(),
      perm.canScheduleExactAlarms(),
      geo.getPermissionStatus(),
      geo.isBatteryOptimizationExempt(),
    ]);
    if (!mounted) return;
    setState(() {
      _notifStatus = results[0] as NativePermissionStatus;
      _canScheduleExactAlarms = results[1] as bool;
      _locationStatus = results[2] as LocationPermissionStatus;
      _batteryExempt = results[3] as bool;
    });
  }

  /// True if the user has at least one LOCATION alarm — the
  /// trigger condition that makes the location + battery steps
  /// *required* (rather than "not needed yet"). On a fresh
  /// install with no alarms, location is presented as optional
  /// so the user can defer it until they actually need a
  /// geofence alarm.
  bool _hasLocationAlarm() {
    final alarms = ref.read(alarmsProvider).value ?? const <Alarm>[];
    return alarms.any((a) => a.triggerType == AlarmTriggerType.location);
  }

  bool get _notifOk =>
      _notifStatus == NativePermissionStatus.granted ||
      _notifStatus == NativePermissionStatus.notRequired;
  bool get _exactOk => _canScheduleExactAlarms == true;
  bool get _locationOk =>
      _locationStatus ==
          LocationPermissionStatus.grantedForegroundAndBackground ||
      _locationStatus == LocationPermissionStatus.grantedForegroundOnly ||
      _locationStatus == LocationPermissionStatus.notRequired;
  bool get _locationFullyOk =>
      _locationStatus ==
          LocationPermissionStatus.grantedForegroundAndBackground ||
      _locationStatus == LocationPermissionStatus.notRequired;
  bool get _batteryOk => _batteryExempt == true;

  bool get _locationNeeded => _hasLocationAlarm();
  bool get _batteryNeeded => _hasLocationAlarm();

  bool get _allRequiredOk {
    if (!_notifOk) return false;
    if (!_exactOk) return false;
    if (_locationNeeded && !_locationFullyOk) return false;
    if (_batteryNeeded && !_batteryOk) return false;
    return true;
  }

  Future<void> _runSetup() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      await PermissionsSetupFlow.runAllMissing(
        context: context,
        ref: ref,
        onProgress: () async {
          // After each step, refresh statuses so the
          // checklist updates live.
          await _refreshAll();
        },
        isLocationNeeded: _locationNeeded,
      );
      await _refreshAll();
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _markShownAndClose({required bool completed}) async {
    // Mark the auto-trigger flag so the wizard doesn't auto-push
    // again on subsequent first-builds of the alarms screen.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(permissionsSetupShownKey, true);
    if (!mounted) return;
    Navigator.of(context).pop(completed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        // The auto-trigger flag is set on Done. If the user
        // dismisses via back/close without completing, the flag
        // is NOT set, so the next first-build will re-offer
        // the wizard. This is intentional: a user who closed
        // the wizard before finishing probably wants the
        // next-session reminder.
        if (!didPop) return;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Get ready'),
          leading: IconButton(
            key: const Key('permissionsSetupClose'),
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => _markShownAndClose(completed: false),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Wakey-Wakey needs a few permissions to ring your alarms reliably.',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Grant them all in one go. You can change any of them later from the system Settings.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                _ChecklistRow(
                  icon: Icons.notifications_active_outlined,
                  title: 'Notifications',
                  description:
                      'So the alarm can ring and show on your lock screen.',
                  isOk: _notifOk,
                  isNeeded: true,
                ),
                _ChecklistRow(
                  icon: Icons.alarm_outlined,
                  title: 'Exact alarms',
                  description:
                      'So time-based alarms fire on the dot on Android 12+.',
                  isOk: _exactOk,
                  isNeeded: true,
                ),
                _ChecklistRow(
                  icon: Icons.location_on_outlined,
                  title: 'Location (for geofence alarms)',
                  description: _locationNeeded
                      ? 'Needed for your geofence alarm. Background location lets the alarm fire when the app is closed.'
                      : 'Only needed when you create a geofence alarm. You can grant it later.',
                  isOk: _locationOk,
                  isNeeded: _locationNeeded,
                ),
                _ChecklistRow(
                  icon: Icons.battery_charging_full_outlined,
                  title: 'Battery optimisation',
                  description: _batteryNeeded
                      ? 'Lets the alarm survive aggressive battery savers on some devices.'
                      : 'Only needed when you arm a geofence alarm.',
                  isOk: _batteryOk,
                  isNeeded: _batteryNeeded,
                ),
                const SizedBox(height: 24),
                if (_allRequiredOk)
                  _AllSetCard(
                    onClose: () => _markShownAndClose(completed: true),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('permissionsSetupRunButton'),
                      onPressed: _running ? null : _runSetup,
                      icon: _running
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(_running ? 'Setting up…' : 'Set up'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// SharedPreferences key used to gate the first-run auto-push.
/// `true` means the wizard has been shown at least once (whether
/// completed or not — the next first-build will re-show the
/// banner but won't auto-push the wizard again).
const String permissionsSetupShownKey = 'permissions_setup_shown';

/// Maybe auto-push the [PermissionsSetupScreen] on the first
/// build of the alarms screen. Called from `addPostFrameCallback`
/// so the push happens after the first frame is laid out.
///
/// The push is suppressed if:
///  * The setup has been shown at least once before (flag set), or
///  * Every required permission is already granted (nothing to
///    do, and the consolidated banner is hidden anyway).
///
/// Returns `true` if the wizard was pushed (so the caller can
/// avoid double-pushing if it also handles the banner's "Fix"
/// button).
Future<bool> maybeAutoShowPermissionsSetup(
  BuildContext context,
  WidgetRef ref,
) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(permissionsSetupShownKey) ?? false) {
    return false;
  }
  if (!context.mounted) return false;
  // Only auto-push if the consolidated banner would actually
  // show something — i.e., at least one required permission
  // is missing. The banner itself does the per-status check;
  // here we do a quick "any missing?" so a fully-permissioned
  // user never sees an empty wizard.
  final perm = ref.read(permissionBridgeProvider);
  final geo = ref.read(geofenceBridgeProvider);
  final results = await Future.wait([
    perm.getNotificationPermissionStatus(),
    perm.canScheduleExactAlarms(),
    geo.getPermissionStatus(),
  ]);
  final notifGranted =
      results[0] == NativePermissionStatus.granted ||
      results[0] == NativePermissionStatus.notRequired;
  final exactGranted = results[1] == true;
  final locationGranted =
      results[2] == LocationPermissionStatus.grantedForegroundAndBackground ||
      results[2] == LocationPermissionStatus.grantedForegroundOnly ||
      results[2] == LocationPermissionStatus.notRequired;
  if (notifGranted && exactGranted && locationGranted) {
    // Everything is good — mark the flag so we don't check again
    // on every first-build of the alarms screen.
    await prefs.setBool(permissionsSetupShownKey, true);
    return false;
  }
  if (!context.mounted) return false;
  await PermissionsSetupScreen.show(context);
  return true;
}

/// One row of the setup checklist. Renders the icon, title,
/// description, and a trailing status indicator (green check
/// when OK, grey dash when "not needed yet", warning icon
/// when missing).
class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.isOk,
    required this.isNeeded,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool isOk;
  final bool isNeeded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showOk = isOk;
    final showMissing = !isOk && isNeeded;
    final trailing = showOk
        ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
        : showMissing
        ? Icon(Icons.error_outline, color: theme.colorScheme.error)
        : Icon(
            Icons.remove_circle_outline,
            color: theme.colorScheme.onSurfaceVariant,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          trailing,
        ],
      ),
    );
  }
}

class _AllSetCard extends StatelessWidget {
  const _AllSetCard({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('permissionsSetupAllSet'),
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.celebration_outlined,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  'All set!',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Every required permission is granted. Your alarms will ring reliably.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('permissionsSetupDoneButton'),
                onPressed: onClose,
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Walks the user through every missing permission in a single
/// pass. Each step is gated on "is this actually missing?" so
/// it's safe to call unconditionally. Used by the setup screen's
/// "Set up" button.
class PermissionsSetupFlow {
  const PermissionsSetupFlow._();

  /// Runs the canonical order: notifications → exact alarms →
  /// foreground location → background location explanation →
  /// background location → battery optimization (nudge).
  /// `onProgress` is awaited after each individual request so
  /// the caller can refresh its checklist.
  /// `isLocationNeeded` controls whether the location + battery
  /// steps are treated as required (true) or skipped as
  /// "not needed yet" (false).
  static Future<void> runAllMissing({
    required BuildContext context,
    required WidgetRef ref,
    required Future<void> Function() onProgress,
    required bool isLocationNeeded,
  }) async {
    final perm = ref.read(permissionBridgeProvider);
    final geo = ref.read(geofenceBridgeProvider);

    // 1. Notifications.
    var notif = await perm.getNotificationPermissionStatus();
    if (notif == NativePermissionStatus.denied) {
      notif = await perm.requestNotificationPermission();
      await onProgress();
    }

    // 2. Exact alarms.
    var canExact = await perm.canScheduleExactAlarms();
    if (!canExact) {
      await perm.requestExactAlarmPermission();
      canExact = await perm.canScheduleExactAlarms();
      await onProgress();
    }

    if (!isLocationNeeded) return;

    // 3. Foreground location.
    var loc = await geo.getPermissionStatus();
    if (loc == LocationPermissionStatus.denied) {
      loc = await geo.requestForegroundLocation();
      await onProgress();
    }

    // 4. Background location (only after foreground is granted;
    //    and the user has to accept the explanation first).
    if (loc == LocationPermissionStatus.grantedForegroundOnly &&
        context.mounted) {
      final accepted = await BackgroundLocationExplanationScreen.show(context);
      if (accepted) {
        loc = await geo.requestBackgroundLocation();
        await onProgress();
      }
    }

    // 5. Battery optimization nudge. Only ask if we got to
    //    this point (i.e., the user has or is about to have a
    //    geofence alarm) — otherwise the nudge is premature.
    final batteryExempt = await geo.isBatteryOptimizationExempt();
    if (!batteryExempt && context.mounted) {
      // Soft ask: a confirm dialog, then open battery settings.
      // The user can decline — the consolidated banner will keep
      // reminding them.
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Battery optimisation'),
          content: const Text(
            'On some devices, aggressive battery savers can stop '
            'alarms from firing. Adding Wakey-Wakey to the '
            'battery-optimisation exception list prevents this. '
            'Open the system Settings to add the exception?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      if (accepted == true) {
        await geo.requestBatteryOptimizationExemption();
        await onProgress();
      }
    }
  }
}
