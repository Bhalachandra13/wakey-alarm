import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/native_bridge/geofence_bridge.dart';
import 'package:wakey_alarm/native_bridge/permission_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/providers/favourite_locations_provider.dart';
import 'package:wakey_alarm/presentation/providers/geofence_arming_controller.dart';
import 'package:wakey_alarm/presentation/screens/background_location_explanation_screen.dart';
import 'package:wakey_alarm/presentation/screens/edit_alarm_screen.dart';
import 'package:wakey_alarm/presentation/screens/favourites_screen.dart';
import 'package:wakey_alarm/presentation/screens/permissions_setup_screen.dart';

class AlarmsScreen extends ConsumerStatefulWidget {
  const AlarmsScreen({super.key});

  @override
  ConsumerState<AlarmsScreen> createState() => _AlarmsScreenState();
}

class _AlarmsScreenState extends ConsumerState<AlarmsScreen> {
  bool _autoTriggered = false;

  @override
  void initState() {
    super.initState();
    // Auto-push the permissions setup wizard on the first
    // build when the user hasn't seen it yet and at least one
    // permission is missing. The flag is gated on SharedPreferences
    // inside the helper, so the push only happens on the very
    // first eligible mount.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _autoTriggered) return;
      _autoTriggered = true;
      maybeAutoShowPermissionsSetup(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final alarmsAsyncValue = ref.watch(alarmsNotifierProvider);
    final ringingId = ref.watch(ringingAlarmIdProvider).value;
    final ringingLabel = ringingId == null
        ? null
        : alarmsAsyncValue.whenOrNull(
            data: (alarms) => alarms
                .firstWhere(
                  (a) => a.id == ringingId,
                  orElse: () => const Alarm(
                    label: 'Unknown alarm',
                    triggerType: AlarmTriggerType.time,
                    isEnabled: true,
                    isArmed: false,
                    soundUri: '',
                    vibrate: false,
                    snoozeDurationMin: 0,
                    createdAt: '',
                    updatedAt: '',
                  ),
                )
                .label,
          );

    return Column(
      children: [
        if (ringingId != null)
          _RingingBanner(alarmLabel: ringingLabel ?? 'Alarm'),
        const _PermissionsHealthBanner(),
        const _SavedPlacesRow(),
        Expanded(
          child: alarmsAsyncValue.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error loading alarms'),
                  const SizedBox(height: 8),
                  Text(
                    error.toString().split('\n').first,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            data: (alarms) => alarms.isEmpty
                ? const _EmptyAlarmsView()
                : _AlarmsList(alarms: alarms, ringingAlarmId: ringingId),
          ),
        ),
      ],
    );
  }
}

/// Health-check banner shown above the alarm list when one or
/// more location alarms are armed but the user is missing a
/// required permission (background location, battery optimization
/// exemption, etc.). Tapping the banner opens the relevant
/// Settings page.
/// Consolidated "permissions needed" banner that replaces the
/// three separate banners that previously lived on this screen
/// (`NotificationPermissionBanner`, `ExactAlarmPermissionBanner`,
/// and the old geofence-only `_GeofenceHealthBanner`).
///
/// The banner checks every permission the alarms feature might
/// need — notifications, exact alarm, foreground/background
/// location (only if a geofence alarm exists), and battery
/// optimization (only if an armed geofence exists) — and shows
/// a single card listing the missing items with one "Fix"
/// button. Tapping it opens the unified [PermissionsSetupScreen]
/// wizard, which handles every missing permission in one pass.
class _PermissionsHealthBanner extends ConsumerStatefulWidget {
  const _PermissionsHealthBanner();

  @override
  ConsumerState<_PermissionsHealthBanner> createState() =>
      _PermissionsHealthBannerState();
}

class _PermissionsHealthBannerState
    extends ConsumerState<_PermissionsHealthBanner>
    with WidgetsBindingObserver {
  NativePermissionStatus? _notifStatus;
  bool? _canScheduleExactAlarms;
  LocationPermissionStatus? _locationStatus;
  bool? _batteryExempt;

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

  /// Re-check when the app returns to the foreground: the user
  /// may have just granted permissions from the system Settings
  /// page launched by tapping the banner / wizard.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
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

  /// Build the list of "missing" items to show in the banner.
  /// Returns an empty list when everything is good (banner hides).
  List<String> _missingItems(List<Alarm> alarms) {
    final missing = <String>[];
    final notifGranted =
        _notifStatus == NativePermissionStatus.granted ||
        _notifStatus == NativePermissionStatus.notRequired;
    if (!notifGranted) missing.add('Notifications');
    if (_canScheduleExactAlarms == false) missing.add('Exact alarms');
    final hasLocationAlarm = alarms.any(
      (a) => a.triggerType == AlarmTriggerType.location,
    );
    if (hasLocationAlarm) {
      final locationFullyGranted =
          _locationStatus ==
              LocationPermissionStatus.grantedForegroundAndBackground ||
          _locationStatus == LocationPermissionStatus.notRequired;
      if (!locationFullyGranted) missing.add('Background location');
      if (_batteryExempt == false) missing.add('Battery optimisation');
    }
    return missing;
  }

  @override
  Widget build(BuildContext context) {
    final alarms = ref.watch(alarmsProvider).value ?? const <Alarm>[];
    final missing = _missingItems(alarms);
    if (missing.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Material(
      key: const Key('permissionsHealthBanner'),
      color: theme.colorScheme.tertiaryContainer,
      child: InkWell(
        onTap: () async {
          await PermissionsSetupScreen.show(context);
          await _refresh();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber,
                color: theme.colorScheme.onTertiaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Permissions needed',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      missing.join(' • '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Fix',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingingBanner extends StatelessWidget {
  const _RingingBanner({required this.alarmLabel});

  final String alarmLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.notifications_active, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Ringing now: $alarmLabel',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyAlarmsView extends StatelessWidget {
  const _EmptyAlarmsView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.alarm_off,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('No alarms yet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Tap the + button to create your first alarm',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _AlarmsList extends ConsumerWidget {
  const _AlarmsList({required this.alarms, this.ringingAlarmId});

  final List<Alarm> alarms;
  final int? ringingAlarmId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.builder(
      itemCount: alarms.length,
      itemBuilder: (context, index) {
        final alarm = alarms[index];
        return _AlarmListTile(
          alarm: alarm,
          isRinging: alarm.id == ringingAlarmId,
        );
      },
    );
  }
}

class _AlarmListTile extends ConsumerWidget {
  const _AlarmListTile({required this.alarm, this.isRinging = false});

  final Alarm alarm;
  final bool isRinging;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: ValueKey(alarm.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) {
        final notifier = ref.read(alarmsNotifierProvider.notifier);
        if (alarm.id != null) {
          notifier.deleteAlarm(alarm.id!);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Alarm deleted'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () {
                  // In a real app, you'd re-insert the alarm
                },
              ),
            ),
          );
        }
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: isRinging ? scheme.errorContainer : null,
        child: ListTile(
          leading: Icon(
            alarm.triggerType == AlarmTriggerType.time
                ? Icons.access_time
                : Icons.location_on,
            color: isRinging ? scheme.onErrorContainer : scheme.primary,
          ),
          title: Text(
            alarm.label,
            style: TextStyle(
              color: isRinging ? scheme.onErrorContainer : null,
              fontWeight: isRinging ? FontWeight.bold : null,
            ),
          ),
          subtitle: _buildSubtitle(
            alarm,
            isRinging ? scheme.onErrorContainer : null,
          ),
          trailing: _buildTrailing(context, ref, alarm),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => EditAlarmScreen(alarm: alarm),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget? _buildSubtitle(Alarm alarm, [Color? color]) {
    if (alarm.triggerType == AlarmTriggerType.time) {
      final hour = alarm.timeHour ?? 0;
      final minute = alarm.timeMinute ?? 0;
      final timeStr =
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

      if (alarm.repeatDays != null && alarm.repeatDays!.isNotEmpty) {
        return Text(
          '$timeStr • ${alarm.repeatDays}',
          style: color == null ? null : TextStyle(color: color),
        );
      }
      return Text(
        timeStr,
        style: color == null ? null : TextStyle(color: color),
      );
    } else {
      // Location alarm.
      final radius = alarm.radiusMeters ?? 0;
      final radiusText = radius >= 1000
          ? '${(radius / 1000).toStringAsFixed(radius % 1000 == 0 ? 0 : 1)} km'
          : '$radius m';
      return Text(
        alarm.isArmed
            ? 'Armed • $radiusText radius'
            : 'Disarmed • $radiusText radius',
        style: color == null ? null : TextStyle(color: color),
      );
    }
  }

  Widget _buildTrailing(BuildContext context, WidgetRef ref, Alarm alarm) {
    final isLocation = alarm.triggerType == AlarmTriggerType.location;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Edit button
        IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => EditAlarmScreen(alarm: alarm),
              ),
            );
          },
        ),
        if (isLocation)
          // Arm/disarm toggle for location alarms. The "isEnabled"
          // switch is intentionally hidden because geofence alarms
          // are armed, not enabled — see the geofence arming flow.
          IconButton(
            tooltip: alarm.isArmed ? 'Stop trip' : 'Start trip',
            icon: Icon(alarm.isArmed ? Icons.stop_circle : Icons.play_circle),
            onPressed: alarm.id == null
                ? null
                : () => _onArmToggle(context, ref, alarm),
          )
        else
          // Toggle enabled/disabled for time-based alarms. The
          // onChanged is async because the native schedule call
          // can fail (e.g. when SCHEDULE_EXACT_ALARM is not
          // granted); we surface that failure to the user via
          // a SnackBar pointing at the permission banner.
          Switch(
            value: alarm.isEnabled,
            onChanged: (newValue) async {
              final notifier = ref.read(alarmsNotifierProvider.notifier);
              if (alarm.id == null) return;
              final ok = await notifier.toggleEnabled(alarm.id!, newValue);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Could not schedule the alarm. Grant the '
                      '"Alarms & reminders" permission, then try again.',
                    ),
                    duration: Duration(seconds: 5),
                  ),
                );
              }
            },
          ),
      ],
    );
  }

  Future<void> _onArmToggle(
    BuildContext context,
    WidgetRef ref,
    Alarm alarm,
  ) async {
    final controller = ref.read(geofenceArmingControllerProvider);
    if (alarm.isArmed) {
      await controller.disarmAlarm(alarm);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Geofence disarmed')));
      }
      return;
    }
    final result = await controller.armAlarm(alarm);
    if (!context.mounted) return;
    switch (result.outcome) {
      case ArmingOutcome.armed:
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Geofence armed')));
      case ArmingOutcome.alreadyInside:
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("You're already inside"),
            content: const Text(
              "You're already within the alarm's radius. Move outside "
              'the circle first, or adjust the radius to make it smaller.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      case ArmingOutcome.alreadyArmed:
        // Defensive: the UI hides the arm button for already-armed
        // alarms, but a race (e.g. another arming flow) could land
        // us here. Treat it as a no-op success.
        break;
      case ArmingOutcome.registrationFailed:
        // Show the human-readable detail from the native side when
        // available (e.g. "Location services are off…", "Too many
        // geofences…"). Fall back to a generic message for
        // defensive cases where the bridge returned no detail.
        final detail = result.message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              detail != null && detail.isNotEmpty
                  ? 'Could not arm geofence: $detail'
                  : 'Could not arm geofence',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      case ArmingOutcome.permissionMissing:
        // Walk the user through the permission flow.
        final bridge = ref.read(geofenceBridgeProvider);
        final flow = LocationPermissionFlow(bridge);
        await flow.runFlow(context);
      case ArmingOutcome.invalidAlarm:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alarm configuration is invalid')),
        );
    }
  }
}

/// Compact entry point to the [FavouritesScreen] shown above the
/// alarm list. Acts as both navigation and a discoverability
/// signal — the user sees "Saved places · N" on the alarms tab
/// and learns that frequent places can be reused for geofence
/// alarms without having to re-pick them every time.
///
/// The row is intentionally thin (a single InkWell, no card) so
/// it doesn't compete with the permission banners above it or
/// the alarm list below. The bookmark icon + chevron make the
/// affordance obvious; the count is the "social proof" that
/// the feature is in use (and a quick way to check whether any
/// favourites exist without opening the screen).
class _SavedPlacesRow extends ConsumerWidget {
  const _SavedPlacesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favourites = ref.watch(favouriteLocationsProvider).value ?? const [];
    final count = favourites.length;
    final theme = Theme.of(context);
    return Material(
      key: const Key('savedPlacesRow'),
      color: theme.colorScheme.surface,
      child: InkWell(
        onTap: () => FavouritesScreen.show(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Icon(Icons.bookmark_outline, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Saved places', style: theme.textTheme.titleSmall),
              ),
              if (count > 0) ...[
                Text(
                  '$count',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
