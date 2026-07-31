import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakey_alarm/native_bridge/permission_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';

/// Banner shown when the app is missing the `POST_NOTIFICATIONS`
/// permission. Without it, the ringing notification (and therefore
/// the full-screen ringing UI) cannot be shown on Android 13+, so
/// even an alarm that fires will be invisible to the user.
///
/// Tapping the banner launches the system permission dialog. The
/// banner re-checks on lifecycle resume so it disappears as soon
/// as the user grants the permission from the system Settings page
/// (the path used when the user has previously chosen "Don't ask
/// again").
///
/// On the very first app launch (i.e. the first time this widget
/// mounts) we also *proactively* call `requestNotificationPermission`
/// so the user sees the system dialog the moment they open the app,
/// without having to discover the banner. We remember that we have
/// already asked once via [SharedPreferences] so we never pester the
/// user a second time on subsequent launches.
class NotificationPermissionBanner extends ConsumerStatefulWidget {
  const NotificationPermissionBanner({super.key});

  /// SharedPreferences key for the "we already auto-asked once" flag.
  /// Exposed so tests can target the same key.
  static const String autoRequestedKey =
      'notification_permission_auto_requested';

  @override
  ConsumerState<NotificationPermissionBanner> createState() =>
      _NotificationPermissionBannerState();
}

class _NotificationPermissionBannerState
    extends ConsumerState<NotificationPermissionBanner>
    with WidgetsBindingObserver {
  NativePermissionStatus? _status;
  bool _isRequesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
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

  /// Initial load. Re-checks the current status and, if this is the
  /// first time the app has run, proactively asks the OS for the
  /// permission so the user sees the dialog on first launch.
  Future<void> _bootstrap() async {
    await _refresh();

    if (!mounted) return;
    if (_status != NativePermissionStatus.denied) return;

    // Only auto-request on the very first launch. If the user
    // denied previously, we leave the banner visible and let them
    // tap it to re-open the system dialog — we never auto-ask twice,
    // because Android suppresses the dialog after a permanent
    // denial and silently no-ops, which is confusing.
    final prefs = await SharedPreferences.getInstance();
    final alreadyAsked = prefs.getBool(
      NotificationPermissionBanner.autoRequestedKey,
    );
    if (alreadyAsked == true) return;

    await prefs.setBool(
      NotificationPermissionBanner.autoRequestedKey,
      true,
    );
    await _request();
  }

  Future<void> _refresh() async {
    final bridge = ref.read(permissionBridgeProvider);
    final status = await bridge.getNotificationPermissionStatus();
    if (mounted) {
      setState(() => _status = status);
    }
  }

  Future<void> _request() async {
    if (_isRequesting) return;
    setState(() => _isRequesting = true);
    try {
      final bridge = ref.read(permissionBridgeProvider);
      final status = await bridge.requestNotificationPermission();
      if (mounted) {
        setState(() => _status = status);
      }
    } finally {
      if (mounted) {
        setState(() => _isRequesting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_status != NativePermissionStatus.denied) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.tertiaryContainer,
      child: InkWell(
        onTap: _isRequesting ? null : _request,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                Icons.notifications_active_outlined,
                color: theme.colorScheme.onTertiaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Allow notifications so Wakey-Wakey can ring your '
                  'alarms and timers. Tap to grant.',
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
