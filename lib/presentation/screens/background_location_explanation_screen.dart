import 'package:flutter/material.dart';
import 'package:wakey_alarm/native_bridge/geofence_bridge.dart';

/// Pre-explanation screen shown before the system Settings page is
/// opened to grant the "Allow all the time" background location
/// permission. The user has to accept the explanation here before
/// we send them to the system Settings — without this, the grant
/// rate is dramatically lower (per `requirements.md` §4).
class BackgroundLocationExplanationScreen extends StatelessWidget {
  const BackgroundLocationExplanationScreen({super.key});

  /// Convenience: pushes the explanation screen and waits for the
  /// user to accept or decline. Returns `true` if the user
  /// accepted (and the system Settings page was opened).
  static Future<bool> show(BuildContext context) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const BackgroundLocationExplanationScreen(),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Background location')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.location_on, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Wakey-Wakey needs background location',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Geofence alarms fire when you enter a saved area — '
              'even if the app is closed. To make that possible, '
              'Android requires the "Allow all the time" location '
              'permission, which can only be granted from the system '
              'Settings page.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              "Your location is never sent off-device. It's only used "
              'to check whether you have entered a geofence you '
              'configured in the app.',
              style: theme.textTheme.bodyMedium,
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Not now'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('Open Settings'),
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

/// Helper for callers that want a single entry point for the
/// full foreground → background permission flow. The flow is:
///
///  1. Request foreground location (system dialog).
///  2. If granted, show the explanation screen.
///  3. If accepted, open the system Settings page for the
///     "Allow all the time" grant.
class LocationPermissionFlow {
  const LocationPermissionFlow(this._bridge);
  final GeofenceBridge _bridge;

  /// Run the foreground + (optional) background permission flow.
  /// Returns the final permission status.
  Future<LocationPermissionStatus> runFlow(BuildContext context) async {
    var status = await _bridge.getPermissionStatus();
    if (status == LocationPermissionStatus.denied) {
      status = await _bridge.requestForegroundLocation();
    }
    if (status == LocationPermissionStatus.grantedForegroundOnly &&
        context.mounted) {
      // Walk the user through the explanation screen.
      final accepted = await BackgroundLocationExplanationScreen.show(context);
      if (accepted) {
        status = await _bridge.requestBackgroundLocation();
      }
    }
    return status;
  }
}
