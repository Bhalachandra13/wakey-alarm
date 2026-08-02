import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakey_alarm/domain/alarm.dart';
import 'package:wakey_alarm/domain/geofence_validator.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/screens/map_picker_screen.dart';

class EditAlarmScreen extends ConsumerStatefulWidget {
  const EditAlarmScreen({super.key, this.alarm});

  final Alarm? alarm;

  @override
  ConsumerState<EditAlarmScreen> createState() => _EditAlarmScreenState();
}

class _EditAlarmScreenState extends ConsumerState<EditAlarmScreen> {
  AlarmTriggerType _triggerType = AlarmTriggerType.time;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 7, minute: 0);
  TextEditingController _labelController = TextEditingController(text: 'Alarm');
  Set<String> _selectedDays = {};
  String _selectedSound = '';
  bool _vibrate = true;
  int _snoozeDuration = 10;

  // Location-trigger fields. Search-by-name lives inside the
  // map picker now, so the edit screen only needs to remember
  // the picked lat/lon + radius.
  double? _latitude;
  double? _longitude;
  int _radiusMeters = GeofenceValidator.defaultRadiusMeters;

  bool _isPickingRingtone = false;
  bool _isPickingLocation = false;

  final List<String> _weekdays = [
    'MON',
    'TUE',
    'WED',
    'THU',
    'FRI',
    'SAT',
    'SUN',
  ];

  @override
  void initState() {
    super.initState();
    final alarm = widget.alarm;
    if (alarm != null) {
      _triggerType = alarm.triggerType;
      _selectedTime = TimeOfDay(
        hour: alarm.timeHour ?? 7,
        minute: alarm.timeMinute ?? 0,
      );
      _labelController = TextEditingController(text: alarm.label);
      _selectedDays = alarm.repeatDays?.split(',').toSet() ?? {};
      _selectedSound = alarm.soundUri;
      _vibrate = alarm.vibrate;
      _snoozeDuration = alarm.snoozeDurationMin;
      _latitude = alarm.latitude;
      _longitude = alarm.longitude;
      _radiusMeters =
          alarm.radiusMeters ?? GeofenceValidator.defaultRadiusMeters;
    } else {
      _labelController = TextEditingController(text: 'Alarm');
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

  String _soundDisplayName(String uri) {
    if (uri.isEmpty) return 'Default alarm sound';
    return 'Custom: ...${uri.length > 24 ? uri.substring(uri.length - 24) : uri}';
  }

  Future<void> _pickRingtone() async {
    setState(() => _isPickingRingtone = true);
    try {
      final bridge = ref.read(alarmBridgeProvider);
      final picked = await bridge.pickRingtone(currentUri: _selectedSound);
      if (!mounted) return;
      setState(() {
        if (picked != null && picked.isNotEmpty) {
          _selectedSound = picked;
        }
      });
    } finally {
      if (mounted) {
        setState(() => _isPickingRingtone = false);
      }
    }
  }

  void _resetRingtone() {
    setState(() => _selectedSound = '');
  }

  Future<void> _pickLocation() async {
    setState(() => _isPickingLocation = true);
    try {
      final result = await Navigator.of(context).push<MapPickerResult>(
        MaterialPageRoute(
          builder: (_) => MapPickerScreen(
            initialLatitude: _latitude,
            initialLongitude: _longitude,
            initialRadiusMeters: _radiusMeters,
          ),
        ),
      );
      if (!mounted) return;
      if (result != null) {
        setState(() {
          _latitude = result.latitude;
          _longitude = result.longitude;
          _radiusMeters = result.radiusMeters;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isPickingLocation = false);
      }
    }
  }

  void _clearLocation() {
    setState(() {
      _latitude = null;
      _longitude = null;
    });
  }

  Future<void> _save() async {
    final label = _labelController.text.trim().isEmpty
        ? 'Alarm'
        : _labelController.text.trim();
    final nowIso = DateTime.now().toIso8601String();
    final repeatDaysStr = _selectedDays.isEmpty
        ? null
        : _weekdays.where((d) => _selectedDays.contains(d)).join(',');

    final isLocation = _triggerType == AlarmTriggerType.location;

    Alarm alarm;
    if (isLocation) {
      if (_latitude == null || _longitude == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Pick a location first')));
        return;
      }
      alarm = Alarm(
        id: widget.alarm?.id,
        label: label,
        triggerType: AlarmTriggerType.location,
        latitude: _latitude,
        longitude: _longitude,
        radiusMeters: _radiusMeters,
        isEnabled: widget.alarm?.isEnabled ?? true,
        isArmed: widget.alarm?.isArmed ?? false,
        soundUri: _selectedSound,
        vibrate: _vibrate,
        snoozeDurationMin: _snoozeDuration,
        createdAt: widget.alarm?.createdAt ?? nowIso,
        updatedAt: nowIso,
      );
    } else {
      alarm = Alarm(
        id: widget.alarm?.id,
        label: label,
        triggerType: AlarmTriggerType.time,
        timeHour: _selectedTime.hour,
        timeMinute: _selectedTime.minute,
        repeatDays: repeatDaysStr,
        isEnabled: widget.alarm?.isEnabled ?? true,
        isArmed: false,
        soundUri: _selectedSound,
        vibrate: _vibrate,
        snoozeDurationMin: _snoozeDuration,
        createdAt: widget.alarm?.createdAt ?? nowIso,
        updatedAt: nowIso,
      );
    }

    final notifier = ref.read(alarmsNotifierProvider.notifier);
    final scheduleOk = widget.alarm == null
        ? (await notifier.insertAlarm(alarm)).scheduled
        : await notifier.updateAlarm(alarm);

    if (!scheduleOk && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Alarm saved, but it could not be scheduled. Grant the '
            '"Alarms & reminders" permission, then toggle it off and on.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.alarm != null;
    final isLocation = _triggerType == AlarmTriggerType.location;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Alarm' : 'Add Alarm'),
        actions: [IconButton(icon: const Icon(Icons.check), onPressed: _save)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Trigger type selector.
            Text(
              'TRIGGER',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<AlarmTriggerType>(
              segments: const [
                ButtonSegment(
                  value: AlarmTriggerType.time,
                  label: Text('Time'),
                  icon: Icon(Icons.access_time),
                ),
                ButtonSegment(
                  value: AlarmTriggerType.location,
                  label: Text('Location'),
                  icon: Icon(Icons.location_on),
                ),
              ],
              selected: {_triggerType},
              onSelectionChanged: (s) {
                setState(() {
                  _triggerType = s.first;
                });
              },
            ),
            const SizedBox(height: 24),

            if (!isLocation)
              _buildTimeSection(theme)
            else
              _buildLocationSection(theme),

            const SizedBox(height: 24),
            // Weekday repeat selector (only for time-based alarms;
            // location alarms are one-shot by design).
            if (!isLocation) ...[
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
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        day[0],
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isSelected
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],

            // Label
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
                hintText: isLocation
                    ? 'e.g. Wake me up before the train stop'
                    : 'e.g. Wake up!',
                prefixIcon: const Icon(Icons.label_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.music_note),
                    title: const Text('Sound'),
                    subtitle: Text(_soundDisplayName(_selectedSound)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_selectedSound.isNotEmpty)
                          TextButton(
                            onPressed: _isPickingRingtone
                                ? null
                                : _resetRingtone,
                            child: const Text('Reset'),
                          ),
                        TextButton(
                          onPressed: _isPickingRingtone ? null : _pickRingtone,
                          child: const Text('Change'),
                        ),
                      ],
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

            // Snooze
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
            const SizedBox(height: 8),
          ],
        ),
      ),
      persistentFooterButtons: _buildActionButtons(),
    );
  }

  List<Widget> _buildActionButtons() {
    final theme = Theme.of(context);
    return [
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text('Cancel'),
      ),
      ElevatedButton(
        onPressed: _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: const Text('Save'),
      ),
    ];
  }

  Widget _buildTimeSection(ThemeData theme) {
    return Center(
      child: GestureDetector(
        onTap: _pickTime,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 36),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primaryContainer,
                theme.colorScheme.secondaryContainer,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withValues(alpha: 0.1),
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
                  Icon(
                    Icons.edit,
                    size: 16,
                    color: theme.colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.7,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Tap to change time',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationSection(ThemeData theme) {
    final hasLocation = _latitude != null && _longitude != null;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.location_on, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasLocation
                        ? 'Lat: ${_latitude!.toStringAsFixed(5)}\n'
                              'Lon: ${_longitude!.toStringAsFixed(5)}'
                        : 'No location picked yet',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            // Address search lives inside [MapPickerScreen] now —
            // the user taps the button below to open the picker,
            // which has a search field with live suggestions and
            // the map for dropping a pin. Keeping the two together
            // means the user never has to context-switch between
            // a text form and a map.
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isPickingLocation ? null : _pickLocation,
                    icon: const Icon(Icons.map),
                    label: Text(hasLocation ? 'Change on map' : 'Pick on map'),
                  ),
                ),
                if (hasLocation) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _clearLocation,
                    child: const Text('Clear'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Radius', style: theme.textTheme.bodyMedium),
                Text(
                  _formatRadius(_radiusMeters),
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
            Slider(
              value: _radiusMeters.toDouble(),
              min: GeofenceValidator.minRadiusMeters.toDouble(),
              max: GeofenceValidator.maxRadiusMeters.toDouble(),
              divisions: 100,
              label: _formatRadius(_radiusMeters),
              onChanged: hasLocation
                  ? (v) => setState(() => _radiusMeters = v.round())
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  String _formatRadius(int meters) {
    if (meters >= 1000) {
      final km = meters / 1000.0;
      return '${km.toStringAsFixed(km == km.truncate() ? 0 : 1)} km';
    }
    return '$meters m';
  }
}
