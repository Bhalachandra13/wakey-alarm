import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakey_alarm/domain/favourite_location.dart';
import 'package:wakey_alarm/presentation/providers/favourite_locations_provider.dart';
import 'package:wakey_alarm/presentation/screens/map_picker_screen.dart';

/// Manage the user's saved favourite places (e.g. "Home",
/// "Work") and create new ones. Favourites are quick-pick
/// targets for the geofence alarm editor — see Iteration 5 in
/// `workflow_plan.md`.
///
/// The screen supports three actions:
///  * **Tap a favourite** — reopens the map picker pre-filled at
///    the favourite's location so the user can recentre or
///    change the default radius. On confirm, the favourite is
///    updated (not duplicated).
///  * **+ in the app bar** — opens the map picker for a brand
///    new location. On confirm, the user is asked for a name
///    ("Home" is the common default).
///  * **Swipe / trash icon** — deletes the favourite after a
///    confirmation dialog.
///
/// When the list is empty, the screen shows a "saved places"
/// empty state with one-tap **Add Home** / **Add Work**
/// affordances plus an **Add custom place** escape hatch. These
/// mirror the in-picker "Add Home / Add Work" hint so the user
/// always has a guided on-ramp to the feature on first use.
class FavouritesScreen extends ConsumerWidget {
  const FavouritesScreen({super.key});

  /// Show the screen as a pushed modal route. Pulled out so
  /// callers don't repeat the MaterialPageRoute boilerplate.
  static Future<void> show(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FavouritesScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favouritesAsync = ref.watch(favouriteLocationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved places'),
        actions: [
          IconButton(
            key: const Key('favouritesAddButton'),
            tooltip: 'Add a saved place',
            icon: const Icon(Icons.add),
            onPressed: () => _pickAndAdd(context, ref),
          ),
        ],
      ),
      body: favouritesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Could not load saved places:\n$error'),
          ),
        ),
        data: (favourites) => favourites.isEmpty
            ? _EmptyState(
                onAddNamed: (name) =>
                    _pickAndAdd(context, ref, defaultName: name),
              )
            : _FavouritesList(
                favourites: favourites,
                onTap: (fav) => _editFavourite(context, ref, fav),
                onDelete: (fav) => _confirmDelete(context, ref, fav),
              ),
      ),
    );
  }

  /// Open the map picker for a brand new favourite. If
  /// [defaultName] is supplied (e.g. "Home" from the empty-state
  /// Add Home button), the name dialog is pre-filled with it.
  Future<void> _pickAndAdd(
    BuildContext context,
    WidgetRef ref, {
    String? defaultName,
  }) async {
    final picked = await Navigator.of(context).push<MapPickerResult>(
      MaterialPageRoute(builder: (_) => const MapPickerScreen()),
    );
    if (picked == null) return; // user cancelled
    if (!context.mounted) return;
    final name = await _askForName(context, defaultName: defaultName ?? '');
    if (name == null || name.trim().isEmpty) return;
    await ref
        .read(favouriteLocationsNotifierProvider.notifier)
        .add(
          name: name.trim(),
          latitude: picked.latitude,
          longitude: picked.longitude,
          radiusMeters: picked.radiusMeters,
        );
  }

  /// Open the map picker pre-filled at [fav]'s location. On
  /// confirm, [fav] is moved (not duplicated) to the new
  /// lat/lon/radius.
  Future<void> _editFavourite(
    BuildContext context,
    WidgetRef ref,
    FavouriteLocation fav,
  ) async {
    final picked = await Navigator.of(context).push<MapPickerResult>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialLatitude: fav.latitude,
          initialLongitude: fav.longitude,
          initialRadiusMeters: fav.radiusMeters,
        ),
      ),
    );
    if (picked == null) return;
    await ref
        .read(favouriteLocationsNotifierProvider.notifier)
        .move(
          fav.id!,
          latitude: picked.latitude,
          longitude: picked.longitude,
          radiusMeters: picked.radiusMeters,
        );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    FavouriteLocation fav,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete saved place?'),
        content: Text(
          'Remove "${fav.name}" from your saved places? '
          'Any alarms using it will keep their current location.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(favouriteLocationsNotifierProvider.notifier).delete(fav.id!);
  }

  /// Show a name dialog. Returns the trimmed name, or `null` if
  /// the user cancelled. The text field is auto-focused.
  Future<String?> _askForName(BuildContext context, {String defaultName = ''}) {
    final controller = TextEditingController(text: defaultName);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name this place'),
        content: TextField(
          key: const Key('favouriteNameField'),
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'e.g. Home, Work, Gym',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _FavouritesList extends StatelessWidget {
  const _FavouritesList({
    required this.favourites,
    required this.onTap,
    required this.onDelete,
  });

  final List<FavouriteLocation> favourites;
  final ValueChanged<FavouriteLocation> onTap;
  final ValueChanged<FavouriteLocation> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      key: const Key('favouritesList'),
      itemCount: favourites.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final f = favourites[i];
        return ListTile(
          key: Key('favouriteRow_$i'),
          leading: Icon(f.icon.iconData, size: 28),
          title: Text(f.name),
          subtitle: Text(
            'Lat ${f.latitude.toStringAsFixed(4)}, '
            'Lon ${f.longitude.toStringAsFixed(4)} · '
            '${_formatRadius(f.radiusMeters)} default',
          ),
          trailing: IconButton(
            key: Key('favouriteDelete_$i'),
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => onDelete(f),
          ),
          onTap: () => onTap(f),
        );
      },
    );
  }

  static String _formatRadius(int meters) {
    if (meters >= 1000) {
      final km = meters / 1000.0;
      return '${km.toStringAsFixed(km == km.truncate() ? 0 : 1)} km';
    }
    return '$meters m';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddNamed});

  /// Called with a pre-filled name when the user taps one of
  /// the suggested affordances ("Add Home" / "Add Work"). The
  /// pick-then-name flow lives in the parent.
  final void Function(String name) onAddNamed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_add_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No saved places yet',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Save places you visit often — Home, Work, the gym — '
              'and pick them in two taps when you set up a '
              'geofence alarm.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  key: const Key('emptyStateAddHome'),
                  onPressed: () => onAddNamed('Home'),
                  icon: Icon(FavouriteIcon.home.iconData),
                  label: const Text('Add Home'),
                ),
                FilledButton.tonalIcon(
                  key: const Key('emptyStateAddWork'),
                  onPressed: () => onAddNamed('Work'),
                  icon: Icon(FavouriteIcon.work.iconData),
                  label: const Text('Add Work'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('emptyStateAddCustom'),
              onPressed: () => onAddNamed(''),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Add a custom place'),
            ),
          ],
        ),
      ),
    );
  }
}
