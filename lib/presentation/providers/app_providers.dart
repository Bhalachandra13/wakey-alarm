import 'package:flutter_riverpod/flutter_riverpod.dart';

enum PermissionReadiness { unknown, ready, actionRequired }

final alarmsProvider = Provider<List<Object>>((ref) => const <Object>[]);

final timersProvider = Provider<List<Object>>((ref) => const <Object>[]);

final permissionStatusProvider = Provider<PermissionReadiness>(
  (ref) => PermissionReadiness.unknown,
);
