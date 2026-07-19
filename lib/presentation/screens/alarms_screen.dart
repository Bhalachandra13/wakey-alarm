import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/screens/edit_alarm_screen.dart';

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
                    error.toString(),
                    textAlign: TextAlign.center,
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
      // Location alarm
      return Text(
        'Location-based (${alarm.radiusMeters}m radius)',
        style: color == null ? null : TextStyle(color: color),
      );
    }
  }

  Widget _buildTrailing(BuildContext context, WidgetRef ref, Alarm alarm) {
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
        // Toggle enabled/disabled
        Switch(
          value: alarm.isEnabled,
          onChanged: (newValue) {
            final notifier = ref.read(alarmsNotifierProvider.notifier);
            if (alarm.id != null) {
              notifier.toggleEnabled(alarm.id!, newValue);
            }
          },
        ),
      ],
    );
  }
}
