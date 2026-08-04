import 'package:flutter/material.dart';
import 'package:wakey_alarm/native_bridge/geofence_bridge.dart';

/// Pre-explanation screen shown before the system Settings page is
/// opened to grant the "Allow all the time" background location
/// permission. The user has to accept the explanation here before
/// we send them to the system Settings \u2014 without this, the grant
/// rate is dramatically lower (per `requirements.md` \u00A74).
///
/// The single biggest cause of "geofence alarm doesn't fire" reports
/// from users is that they pick "Allow only while using the app" in
/// Android's permission dialog, not realising that option is
/// insufficient for a geofence \u2014 the alarm needs the OS to keep
/// evaluating location in the background. This screen is designed
/// to make that distinction unambiguous:
///
///   * A warning callout explicitly names "Allow only while using
///     the app" and explains that it is not enough.
///   * A visual mockup of the Android Settings page with "Allow
///     all the time" highlighted so the user can recognise it on
///     the real screen.
///   * A numbered step list telling them exactly what to tap.
///   * A note about the "Precise" choice on Android 12+ (the
///     follow-up dialog that asks for precise vs approximate).
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
      appBar: AppBar(title: const Text('Allow location all the time')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.location_on,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Wakey-Wakey needs location all the time',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Geofence alarms fire when you enter a saved area \u2014 '
              'even if the app is closed, your screen is off, or you '
              'are using a different app. To do that, Android needs '
              'the "Allow all the time" location setting for '
              'Wakey-Wakey.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            _WhyNotWhileUsingAppCard(theme: theme),
            const SizedBox(height: 20),
            Text(
              'This is the screen you will see in Settings',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            const _SettingsMockupCard(),
            const SizedBox(height: 20),
            Text('What to tap', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            const _NumberedSteps(),
            const SizedBox(height: 20),
            _PrivacyNote(theme: theme),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Row(
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
      ),
    );
  }
}

/// Warning callout that explicitly names the wrong option and
/// states that it will not work for geofence alarms. The previous
/// version of this screen was positive-only ("here is what to do")
/// which left users who had already picked the wrong option unsure
/// whether to re-do it.
class _WhyNotWhileUsingAppCard extends StatelessWidget {
  const _WhyNotWhileUsingAppCard({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('bgLocationWhyNotWhileUsingApp'),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.error,
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: theme.colorScheme.onErrorContainer,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '"Allow only while using the app" is not enough',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'If you pick that option, the geofence alarm will not '
                  'fire when the app is in the background, your screen '
                  'is off, or you are using another app \u2014 which is '
                  'most of the time. You need "Allow all the time".',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mocked-up Android Settings page showing the Location permission
/// dialog. The correct option ("Allow all the time") is highlighted
/// with a filled radio button, a green checkmark, and a "Pick this
/// one" badge so the user can pattern-match against the real screen.
class _SettingsMockupCard extends StatelessWidget {
  const _SettingsMockupCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark
        ? theme.colorScheme.surfaceContainerHigh
        : const Color(0xFFF1F3F4);
    final cardBorder = isDark
        ? theme.colorScheme.outlineVariant
        : const Color(0xFFDADCE0);
    return Container(
      key: const Key('bgLocationMockup'),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.arrow_back,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Location',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'App permission',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cardBorder),
          _MockRadioRow(
            label: 'Allow all the time',
            isCorrect: true,
            selected: true,
          ),
          Divider(height: 1, color: cardBorder),
          _MockRadioRow(
            label: 'Allow only while using the app',
            isCorrect: false,
            selected: false,
          ),
          Divider(height: 1, color: cardBorder),
          _MockRadioRow(
            label: 'Ask every time',
            isCorrect: false,
            selected: false,
          ),
          Divider(height: 1, color: cardBorder),
          _MockRadioRow(
            label: "Don't allow",
            isCorrect: false,
            selected: false,
          ),
        ],
      ),
    );
  }
}

class _MockRadioRow extends StatelessWidget {
  const _MockRadioRow({
    required this.label,
    required this.isCorrect,
    required this.selected,
  });

  final String label;
  final bool isCorrect;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlight = isCorrect
        ? theme.colorScheme.primary
        : Colors.transparent;
    return Container(
      decoration: BoxDecoration(
        color: isCorrect
            ? theme.colorScheme.primary.withValues(alpha: 0.10)
            : null,
        border: Border(
          left: BorderSide(color: highlight, width: 4),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: isCorrect
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: isCorrect
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
                fontWeight: isCorrect ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (isCorrect)
            Container(
              key: const Key('bgLocationMockupPickThisBadge'),
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Pick this one',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NumberedSteps extends StatelessWidget {
  const _NumberedSteps();

  static const _steps = <String>[
    'Tap "Open Settings" below. The system Settings opens on the '
        'Wakey-Wakey permission page.',
    'Tap "Location" in the list, then choose "Allow all the time".',
    'If Android also asks "Use precise location?", choose '
        '"Precise" (not "Approximate") so the alarm fires at the '
        'right place.',
    'Use the back gesture to return to Wakey-Wakey. The banner '
        'will update automatically.',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${i + 1}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_steps[i], style: theme.textTheme.bodyMedium),
              ),
            ],
          ),
          if (i < _steps.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            color: theme.colorScheme.onSecondaryContainer,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Your location is never sent off your device. It is only '
              'used to check whether you have entered a geofence you '
              'configured in the app.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper for callers that want a single entry point for the
/// full foreground \u2192 background permission flow. The flow is:
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
