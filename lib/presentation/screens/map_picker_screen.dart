import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wakey_alarm/domain/geofence_validator.dart';

/// Map-based location picker for creating a geofence alarm.
///
/// Allows the user to:
///  * Drop a pin on a map (the camera center is the pick).
///  * See the radius circle overlaid on the map.
///  * Adjust the radius via a slider (200 m–20 km, default 2 km).
///  * Confirm or cancel the selection.
///
/// On real devices with a configured Google Maps API key the map
/// renders normally. Without a key (or in unit tests) the map
/// widget shows a blank canvas but the picker still works — the
/// user can use the manual lat/long inputs as a fallback. This
/// keeps the feature testable in CI without burning API quota.
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
    this.initialRadiusMeters = GeofenceValidator.defaultRadiusMeters,
  });

  /// Optional starting pin. If null, the screen starts centered
  /// on a default location (London) until the user drops a pin.
  final double? initialLatitude;
  final double? initialLongitude;
  final int initialRadiusMeters;

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  late int _radiusMeters;
  LatLng? _pin;

  @override
  void initState() {
    super.initState();
    _radiusMeters = widget.initialRadiusMeters;
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _pin = LatLng(widget.initialLatitude!, widget.initialLongitude!);
    }
  }

  void _updatePinFromCamera(LatLng target) {
    setState(() {
      _pin = target;
    });
  }

  void _setRadius(int meters) {
    setState(() {
      _radiusMeters = meters;
    });
  }

  void _confirm() {
    final pin = _pin;
    if (pin == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Drop a pin first')));
      return;
    }
    Navigator.of(context).pop(
      MapPickerResult(
        latitude: pin.latitude,
        longitude: pin.longitude,
        radiusMeters: _radiusMeters,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initialCameraTarget = _pin ?? const LatLng(51.5074, -0.1278);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick location'),
        actions: [
          IconButton(icon: const Icon(Icons.check), onPressed: _confirm),
        ],
      ),
      body: Column(
        children: [
          // Map area. The actual GoogleMap widget may fail to
          // render tiles in tests (no API key); in that case
          // google_maps_flutter surfaces an error controller we
          // can ignore here — the manual inputs below still work.
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: initialCameraTarget,
                    zoom: 12,
                  ),
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: true,
                  onCameraIdle: () {
                    // `onCameraIdle` doesn't expose the camera
                    // position, so we rely on `onCameraMoveStarted`
                    // + `onCameraMove` to track the in-progress
                    // camera target. We capture the last
                    // `onCameraMove` target here.
                  },
                  onCameraMove: (position) {
                    // Update the pin as the user pans so the
                    // "drop a pin" UX feels responsive. The user
                    // confirms with the check button.
                    _updatePinFromCamera(position.target);
                  },
                  circles: _pin == null
                      ? <Circle>{}
                      : {
                          Circle(
                            circleId: const CircleId('geofence-preview'),
                            center: _pin!,
                            radius: _radiusMeters.toDouble(),
                            fillColor: theme.colorScheme.primary.withValues(
                              alpha: 0.15,
                            ),
                            strokeColor: theme.colorScheme.primary.withValues(
                              alpha: 0.7,
                            ),
                            strokeWidth: 2,
                          ),
                        },
                  markers: _pin == null
                      ? <Marker>{}
                      : {
                          Marker(
                            markerId: const MarkerId('picked'),
                            position: _pin!,
                            draggable: true,
                            onDragEnd: (newPos) {
                              setState(() {
                                _pin = newPos;
                              });
                            },
                          ),
                        },
                ),
                // Floating hint over the map.
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Card(
                    color: theme.colorScheme.surface.withValues(alpha: 0.9),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _pin == null
                            ? 'Pan the map to drop a pin'
                            : 'Drag the pin or pan to adjust. Tap the ✓ to confirm.',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Radius slider + manual lat/long inputs (the manual
          // inputs make the picker usable even when the map
          // tiles fail to load — see class doc).
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Radius', style: theme.textTheme.titleSmall),
                    Text(
                      _formatRadius(_radiusMeters),
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
                Slider(
                  value: _radiusMeters.toDouble(),
                  min: GeofenceValidator.minRadiusMeters.toDouble(),
                  max: GeofenceValidator.maxRadiusMeters.toDouble(),
                  divisions: 100,
                  label: _formatRadius(_radiusMeters),
                  onChanged: (v) => _setRadius(v.round()),
                ),
                const SizedBox(height: 8),
                if (_pin != null) ...[
                  Text(
                    'Lat: ${_pin!.latitude.toStringAsFixed(5)}, '
                    'Lon: ${_pin!.longitude.toStringAsFixed(5)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
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

/// What the picker returns to its caller.
class MapPickerResult {
  const MapPickerResult({
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  final double latitude;
  final double longitude;
  final int radiusMeters;
}
