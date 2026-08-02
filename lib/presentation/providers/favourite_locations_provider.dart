import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakey_alarm/data/favourite_location_dao.dart';
import 'package:wakey_alarm/domain/favourite_location.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';

/// DAO provider for the `favourite_locations` table. Mirrors the
/// `alarmDaoProvider` / `timerDaoProvider` pattern: the [Provider]
/// watches the [databaseProvider] so test code can override the
/// database (and therefore the DAO) by overriding either one.
final favouriteLocationDaoProvider = Provider<FavouriteLocationDao>((ref) {
  return FavouriteLocationDao(ref.watch(databaseProvider));
});

/// AsyncNotifier for the user's saved favourite places.
///
/// Exposes a sorted list of [FavouriteLocation]s and the
/// mutations the UI needs (add, update, delete). The favourite
/// count is short in practice (handful of items), so a single
/// in-memory list is the right granularity — no pagination,
/// no separate "active" vs "archived" state.
class FavouriteLocationsNotifier
    extends AsyncNotifier<List<FavouriteLocation>> {
  @override
  Future<List<FavouriteLocation>> build() async {
    final dao = ref.watch(favouriteLocationDaoProvider);
    return dao.getAll();
  }

  /// Save a new favourite. Stamps `created_at` / `updated_at` to
  /// `now` and lets [FavouriteIcon.fromName] auto-pick an icon
  /// when the caller didn't set one. Returns the inserted row id.
  Future<int> add({
    required String name,
    required double latitude,
    required double longitude,
    required int radiusMeters,
    FavouriteIcon? icon,
  }) async {
    final dao = ref.read(favouriteLocationDaoProvider);
    final now = DateTime.now().toIso8601String();
    final fav = FavouriteLocation(
      name: name,
      icon: icon ?? FavouriteIcon.fromName(name),
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      createdAt: now,
      updatedAt: now,
    );
    final id = await dao.insert(fav);
    ref.invalidateSelf();
    return id;
  }

  /// Rename a favourite (and optionally change its icon and
  /// default radius). Bumps `updated_at`.
  ///
  /// Named `edit` rather than `update` to avoid clashing with
  /// [AsyncNotifier.update], which has a different signature
  /// (state-replacement callback).
  Future<void> edit(
    int id, {
    String? name,
    FavouriteIcon? icon,
    int? radiusMeters,
  }) async {
    final dao = ref.read(favouriteLocationDaoProvider);
    final existing = await dao.read(id);
    if (existing == null) return;
    final updated = existing.copyWith(
      name: name,
      icon: icon,
      radiusMeters: radiusMeters,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await dao.update(updated);
    ref.invalidateSelf();
  }

  /// Move a favourite to a new location. Used when the user
  /// re-pins a favourite on the map ("tap to recentre" on the
  /// favourites screen).
  Future<void> move(
    int id, {
    double? latitude,
    double? longitude,
    int? radiusMeters,
  }) async {
    final dao = ref.read(favouriteLocationDaoProvider);
    final existing = await dao.read(id);
    if (existing == null) return;
    final updated = existing.copyWith(
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      updatedAt: DateTime.now().toIso8601String(),
    );
    await dao.update(updated);
    ref.invalidateSelf();
  }

  /// Hard-delete a favourite. The user has to confirm in the UI
  /// before the caller invokes this — the row is gone immediately
  /// and there is no undo.
  Future<void> delete(int id) async {
    final dao = ref.read(favouriteLocationDaoProvider);
    await dao.delete(id);
    ref.invalidateSelf();
  }
}

final favouriteLocationsNotifierProvider =
    AsyncNotifierProvider<FavouriteLocationsNotifier, List<FavouriteLocation>>(
      FavouriteLocationsNotifier.new,
    );

/// Convenience read-only view of the favourites list. Mirrors the
/// `alarmsProvider` pattern: most consumers only need to render the
/// list and don't need the notifier's mutation methods.
final favouriteLocationsProvider =
    Provider<AsyncValue<List<FavouriteLocation>>>((ref) {
      return ref.watch(favouriteLocationsNotifierProvider);
    });

/// True if the user has saved at least one favourite. The map
/// picker uses this to decide whether to show the empty-state
/// "Add Home / Add Work" hint or the chip strip with the existing
/// favourites.
final hasFavouritesProvider = Provider<bool>((ref) {
  final favourites = ref.watch(favouriteLocationsProvider).value ?? const [];
  return favourites.isNotEmpty;
});
