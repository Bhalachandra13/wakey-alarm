import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/native_bridge/geofence_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/providers/geofence_arming_controller.dart';
import 'package:wakey_alarm/presentation/screens/background_location_explanation_screen.dart';
import 'package:wakey_alarm/presentation/screens/edit_alarm_screen.dart';
import 'package:wakey_alarm/presentation/widgets/exact_alarm_banner.dart';
import 'package:wakey_alarm/presentation/widgets/notification_permission_banner.dart';

class AlarmsScreen extends ConsumerWidget {
  const AlarmsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        const NotificationPermissionBanner(),
        const ExactAlarmPermissionBanner(),
        const _GeofenceHealthBanner(),
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
class _GeofenceHealthBanner extends ConsumerStatefulWidget {
  const _GeofenceHealthBanner();

  @override
  ConsumerState<_GeofenceHealthBanner> createState() =>
      _GeofenceHealthBannerState();
}

class _GeofenceHealthBannerState extends ConsumerState<_GeofenceHealthBanner> {
  LocationPermissionStatus? _permissionStatus;
  bool? _batteryExempt;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final bridge = ref.read(geofenceBridgeProvider);
    final perm = await bridge.getPermissionStatus();
    final battery = await bridge.isBatteryOptimizationExempt();
    if (mounted) {
      setState(() {
        _permissionStatus = perm;
        _batteryExempt = battery;
      });
    }
  }

  bool _hasIssue(List<Alarm>? alarms) {
    if (alarms == null) return false;
    final hasArmedLocation = alarms.any(
      (a) => a.triggerType == AlarmTriggerType.location && a.isArmed,
    );
    if (!hasArmedLocation) return false;
    if (_permissionStatus !=
            LocationPermissionStatus.grantedForegroundAndBackground ||
        _batteryExempt == false) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final alarms = ref.watch(alarmsProvider).value;
    if (!_hasIssue(alarms)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.tertiaryContainer,
      child: InkWell(
        onTap: () async {
          final flow = LocationPermissionFlow(ref.read(geofenceBridgeProvider));
          await flow.runFlow(context);
          await _refresh();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber,
                color: theme.colorScheme.onTertiaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _batteryExempt == false
                      ? 'Geofence alarms may be killed by battery optimization. Tap to fix.'
                      : 'Background location is required for geofence alarms to fire. Tap to grant.',
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not arm geofence')));
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
