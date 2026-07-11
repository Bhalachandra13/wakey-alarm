import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';

class EditAlarmScreen extends ConsumerStatefulWidget {
  const EditAlarmScreen({super.key, this.alarm});

  final Alarm? alarm;

  @override
  ConsumerState<EditAlarmScreen> createState() => _EditAlarmScreenState();
}

class _EditAlarmScreenState extends ConsumerState<EditAlarmScreen> {
  late TimeOfDay _selectedTime;
  late TextEditingController _labelController;
  late Set<String> _selectedDays;
  late String _selectedSound;
  late bool _vibrate;
  late int _snoozeDuration;

  final List<String> _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  final List<Map<String, String>> _sounds = [
    {'name': 'Default Ringtone', 'uri': 'system://default'},
    {'name': 'Gentle Breeze', 'uri': 'system://gentle_breeze'},
    {'name': 'Digital Alarm', 'uri': 'system://digital'},
    {'name': 'Wakey Theme', 'uri': 'system://wakey_theme'},
  ];

  @override
  void initState() {
    super.initState();
    final alarm = widget.alarm;
    if (alarm != null) {
      _selectedTime = TimeOfDay(
        hour: alarm.timeHour ?? 7,
        minute: alarm.timeMinute ?? 0,
      );
      _labelController = TextEditingController(text: alarm.label);
      _selectedDays = alarm.repeatDays?.split(',').toSet() ?? {};
      _selectedSound = alarm.soundUri;
      _vibrate = alarm.vibrate;
      _snoozeDuration = alarm.snoozeDurationMin;
    } else {
      _selectedTime = const TimeOfDay(hour: 7, minute: 0);
      _labelController = TextEditingController(text: 'Alarm');
      _selectedDays = {};
      _selectedSound = 'system://default';
      _vibrate = true;
      _snoozeDuration = 10;
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (time != null) {
      setState(() {
        _selectedTime = time;
      });
    }
  }

  void _toggleDay(String day) {
    setState(() {
      if (_selectedDays.contains(day)) {
        _selectedDays.remove(day);
      } else {
        _selectedDays.add(day);
      }
    });
  }

  Future<void> _save() async {
    final label = _labelController.text.trim().isEmpty ? 'Alarm' : _labelController.text.trim();
    final nowIso = DateTime.now().toIso8601String();
    
    // Convert repeat days set to comma-separated string, or null if empty
    final repeatDaysStr = _selectedDays.isEmpty ? null : _weekdays.where((d) => _selectedDays.contains(d)).join(',');

    final alarm = widget.alarm;
    final updatedAlarm = Alarm(
      id: alarm?.id,
      label: label,
      triggerType: AlarmTriggerType.time,
      timeHour: _selectedTime.hour,
      timeMinute: _selectedTime.minute,
      repeatDays: repeatDaysStr,
      isEnabled: alarm?.isEnabled ?? true,
      isArmed: false,
      soundUri: _selectedSound,
      vibrate: _vibrate,
      snoozeDurationMin: _snoozeDuration,
      createdAt: alarm?.createdAt ?? nowIso,
      updatedAt: nowIso,
    );

    final notifier = ref.read(alarmsNotifierProvider.notifier);
    if (alarm == null) {
      await notifier.insertAlarm(updatedAlarm);
    } else {
      await notifier.updateAlarm(updatedAlarm);
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.alarm != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Alarm' : 'Add Alarm'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _save,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time selection panel
            Center(
              child: GestureDetector(
                onTap: _pickTime,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 36),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [theme.colorScheme.primaryContainer, theme.colorScheme.secondaryContainer],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: theme.shadowColor.withAlpha(26),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        _selectedTime.format(context),
                        style: theme.textTheme.displayMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit, size: 16, color: theme.colorScheme.onPrimaryContainer.withAlpha(178)),
                          const SizedBox(width: 4),
                          Text(
                            'Tap to change time',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer.withAlpha(178),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Weekday repeat selector
            Text(
              'REPEAT',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _weekdays.map((day) {
                final isSelected = _selectedDays.contains(day);
                return GestureDetector(
                  onTap: () => _toggleDay(day),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: isSelected ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: theme.colorScheme.primary.withAlpha(100),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      day[0],
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Label text field
            Text(
              'LABEL',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _labelController,
              decoration: InputDecoration(
                hintText: 'e.g. Wake up!',
                prefixIcon: const Icon(Icons.label_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 24),

            // Sound and Vibration
            Text(
              'SOUND & VIBRATION',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.music_note),
                    title: const Text('Sound'),
                    trailing: DropdownButton<String>(
                      value: _sounds.any((s) => s['uri'] == _selectedSound) ? _selectedSound : 'system://default',
                      underline: const SizedBox(),
                      items: _sounds.map((sound) {
                        return DropdownMenuItem<String>(
                          value: sound['uri'],
                          child: Text(sound['name']!),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedSound = val;
                          });
                        }
                      },
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    secondary: const Icon(Icons.vibration),
                    title: const Text('Vibrate'),
                    value: _vibrate,
                    onChanged: (val) {
                      setState(() {
                        _vibrate = val;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Snooze Configuration
            Text(
              'SNOOZE',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                leading: const Icon(Icons.snooze),
                title: const Text('Snooze Duration'),
                trailing: DropdownButton<int>(
                  value: _snoozeDuration,
                  underline: const SizedBox(),
                  items: [5, 10, 15, 20, 30].map((duration) {
                    return DropdownMenuItem<int>(
                      value: duration,
                      child: Text('$duration minutes'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _snoozeDuration = val;
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
