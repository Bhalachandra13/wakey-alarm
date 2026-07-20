import 'package:flutter_riverpod/flutter_riverpod.dart';

/// High-level permission state surfaced to the app shell. The
/// concrete provider is wired up in the alarms/permissions providers;
/// this enum + provider is the dependency the shell needs.
enum PermissionReadiness { unknown, ready, actionRequired }

/// The "are all critical permissions granted" readiness indicator.
/// Concrete logic lives in the permissions provider; this is a stable
/// type the shell can depend on without taking on a hard dependency
/// on the permission bridge.
final permissionStatusProvider = Provider<PermissionReadiness>(
  (ref) => PermissionReadiness.unknown,
);
