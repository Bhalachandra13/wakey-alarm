import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:wakey_alarm/data/location_search_service.dart';
import 'package:wakey_alarm/domain/favourite_location.dart';
import 'package:wakey_alarm/domain/geofence_validator.dart';
import 'package:wakey_alarm/native_bridge/geofence_bridge.dart';
import 'package:wakey_alarm/presentation/providers/alarms_provider.dart';
import 'package:wakey_alarm/presentation/providers/favourite_locations_provider.dart';
import 'package:wakey_alarm/presentation/screens/favourites_screen.dart';

/// Map-based location picker for creating a geofence alarm.
///
/// Allows the user to:
///  * Search for a place by name (with live suggestions).
///  * Drop a pin on a map (the camera center is the pick).
///  * See the radius circle overlaid on the map.
///  * Adjust the radius via a slider (200 m–20 km, default 2 km).
///  * Confirm or cancel the selection.
///
/// Search is *inside* the picker now. As the user types, a debounced
/// call to [LocationSearchService] returns up-to-five suggestions;
/// tapping one drops a pin and flies the camera to that location.
/// The Nominatim usage policy caps us at 1 request/second, so the
/// search is debounced by [kSearchDebounce] and in-flight calls are
/// cancelled when the query changes (no point waiting for a stale
/// result).
///
/// On real devices with a configured Google Maps API key the map
/// renders normally. Without a key (or in unit tests) the map
/// widget shows a blank canvas but the picker still works — the
/// user can type a place into the search field and pick one of the
/// results. This keeps the feature testable in CI without burning
/// API quota.
class MapPickerScreen extends ConsumerStatefulWidget {
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
  ConsumerState<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends ConsumerState<MapPickerScreen> {
  /// How long to wait after the last keystroke before firing the
  /// search. Nominatim's usage policy requires ≤1 req/s, so this
  /// is well above a typical rapid-typing cadence yet short enough
  /// to feel live.
  static const Duration kSearchDebounce = Duration(milliseconds: 400);

  late int _radiusMeters;
  LatLng? _pin;
  GoogleMapController? _mapController;
  bool _hasCenteredOnUser = false;

  // Search state.
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _searchDebounceTimer;
  int _searchRequestSeq = 0;
  bool _isSearching = false;
  List<LocationSearchResult> _searchResults = const [];
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _radiusMeters = widget.initialRadiusMeters;
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _pin = LatLng(widget.initialLatitude!, widget.initialLongitude!);
    }
    // Run an initial search if the field is empty — gives the
    // user immediate "what can I pick?" affordance on open.
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  /// Best-effort recenter on the user's current location. Called
  /// once after the map's first frame; silently no-ops if location
  /// permission isn't granted yet, in which case the user can still
  /// pan the map manually, tap the my-location button, or use the
  /// search field.
  Future<void> _maybeCenterOnUser() async {
    if (_hasCenteredOnUser) return;
    final controller = _mapController;
    if (controller == null) return;
    // If the user passed in an existing pin, honour that — don't
    // yank the camera away to the user's current location.
    if (_pin != null) return;
    _hasCenteredOnUser = true;
    try {
      final bridge = ref.read(geofenceBridgeProvider);
      final here = await bridge.getCurrentLocation(
        timeout: const Duration(seconds: 6),
      );
      if (here != null && mounted) {
        await controller.animateCamera(
          CameraUpdate.newLatLngZoom(LatLng(here.latitude, here.longitude), 14),
        );
      }
    } on Object {
      // Swallow — no location fix is a normal state (permission
      // not granted, GPS off, etc.) and shouldn't break the picker.
    }
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

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  /// Called on every keystroke. Schedules a debounced search so we
  /// don't hammer the public Nominatim endpoint on every character.
  void _onSearchChanged(String _) {
    _searchDebounceTimer?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = const [];
        _searchError = null;
        _isSearching = false;
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _searchError = null;
    });
    _searchDebounceTimer = Timer(kSearchDebounce, () {
      _runSearch(query);
    });
  }

  /// Fires the actual search. Each call is tagged with a sequence
  /// number; if a newer call comes in (e.g. the user kept typing)
  /// the older one is discarded so the UI never shows stale
  /// results behind a fresh query.
  Future<void> _runSearch(String query) async {
    final seq = ++_searchRequestSeq;
    try {
      final service = ref.read(locationSearchServiceProvider);
      final results = await service.search(query);
      if (!mounted || seq != _searchRequestSeq) return;
      setState(() {
        _isSearching = false;
        _searchResults = results;
        if (results.isEmpty) {
          _searchError = 'No matches for "$query"';
        } else {
          _searchError = null;
        }
      });
    } on LocationSearchException catch (e) {
      if (!mounted || seq != _searchRequestSeq) return;
      setState(() {
        _isSearching = false;
        _searchResults = const [];
        _searchError = e.message;
      });
    }
  }

  /// Submits the current text (Enter / search IME action). Bypasses
  /// the debounce so the user can fire a search immediately.
  void _onSearchSubmitted(String query) {
    _searchDebounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchResults = const [];
        _searchError = null;
        _isSearching = false;
      });
      return;
    }
    setState(() {
      _isSearching = true;
      _searchError = null;
    });
    _runSearch(trimmed);
  }

  /// Clears the search field and dismisses the suggestions
  /// overlay. Keeps the existing pin (the user may have already
  /// picked one).
  void _clearSearch() {
    _searchDebounceTimer?.cancel();
    _searchController.clear();
    setState(() {
      _searchResults = const [];
      _searchError = null;
      _isSearching = false;
    });
  }

  /// Adopts [result] as the picked location. Drops the pin, flies
  /// the camera there, dismisses the suggestions, and clears the
  /// search field so the user sees the picked pin on the map
  /// (matching the manual-pick UX).
  Future<void> _selectSearchResult(LocationSearchResult result) async {
    final latLng = LatLng(result.latitude, result.longitude);
    setState(() {
      _pin = latLng;
      _searchResults = const [];
      _searchError = null;
      _isSearching = false;
    });
    _searchController.clear();
    _searchFocus.unfocus();
    final controller = _mapController;
    if (controller != null) {
      await controller.animateCamera(CameraUpdate.newLatLngZoom(latLng, 14));
    }
  }

  /// Adopts a saved [FavouriteLocation] as the picked location.
  /// Same UX as [_selectSearchResult] — drops the pin, flies the
  /// camera, dismisses the suggestions, clears the search — but
  /// also adopts the favourite's stored default radius so the
  /// user doesn't have to re-set it.
  Future<void> _selectFavourite(FavouriteLocation fav) async {
    final latLng = LatLng(fav.latitude, fav.longitude);
    setState(() {
      _pin = latLng;
      _radiusMeters = fav.radiusMeters;
      _searchResults = const [];
      _searchError = null;
      _isSearching = false;
    });
    _searchController.clear();
    _searchFocus.unfocus();
    final controller = _mapController;
    if (controller != null) {
      await controller.animateCamera(CameraUpdate.newLatLngZoom(latLng, 14));
    }
  }

  /// Open the Favourites screen so the user can add or manage
  /// saved places. Pushed as a full route (not a modal sheet) so
  /// the back gesture returns to the picker and the in-progress
  /// pin is preserved.
  Future<void> _openFavourites() async {
    await FavouritesScreen.show(context);
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
          // can ignore here — the search field still works and
          // drops the pin in the in-memory camera state.
          Expanded(
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: initialCameraTarget,
                    zoom: 12,
                  ),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: true,
                  onMapCreated: (controller) {
                    _mapController = controller;
                    // Wait for the first frame to be laid out
                    // before panning; the controller isn't ready
                    // to accept camera updates synchronously here.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _maybeCenterOnUser();
                    });
                  },
                  onCameraMove: (position) {
                    // Update the pin as the user pans so the
                    // "drop a pin" UX feels responsive. The user
                    // confirms with the check button.
                    setState(() {
                      _pin = position.target;
                    });
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
                // Search bar + suggestions overlay, pinned to the
                // top of the map so it stays visible while panning.
                // The quick-pick favourite chip strip lives inside
                // the same card (below the suggestions) so the two
                // pick-a-place affordances share one floating
                // panel and never overlap each other.
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: _SearchPanel(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    isSearching: _isSearching,
                    results: _searchResults,
                    errorMessage: _searchError,
                    hasPin: _pin != null,
                    onChanged: _onSearchChanged,
                    onSubmitted: _onSearchSubmitted,
                    onClear: _clearSearch,
                    onSelectResult: _selectSearchResult,
                    onSelectFavourite: _selectFavourite,
                    onManageFavourites: _openFavourites,
                  ),
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
                            ? 'Search for a place or pan the map to drop a pin'
                            : 'Drag the pin or pick another place. Tap the ✓ to confirm.',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Radius slider. Kept below the map so the slider is
          // always reachable even on small screens where the
          // search suggestions cover the bottom of the map.
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
                const SizedBox(height: 4),
                if (_pin != null)
                  Text(
                    'Lat: ${_pin!.latitude.toStringAsFixed(5)}, '
                    'Lon: ${_pin!.longitude.toStringAsFixed(5)}',
                    style: theme.textTheme.bodySmall,
                  ),
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

/// The search field + suggestions overlay + quick-pick favourite
/// chip strip, all in one floating card. Kept as its own widget
/// (now a [ConsumerWidget] so it can read the favourites list
/// directly) so [_MapPickerScreenState.build] stays readable —
/// there's a lot going on with the keyboard, results, error
/// states, and the saved-places affordance.
class _SearchPanel extends ConsumerWidget {
  const _SearchPanel({
    required this.controller,
    required this.focusNode,
    required this.isSearching,
    required this.results,
    required this.errorMessage,
    required this.hasPin,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
    required this.onSelectResult,
    required this.onSelectFavourite,
    required this.onManageFavourites,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSearching;
  final List<LocationSearchResult> results;
  final String? errorMessage;
  final bool hasPin;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;
  final ValueChanged<LocationSearchResult> onSelectResult;
  final ValueChanged<FavouriteLocation> onSelectFavourite;
  final VoidCallback onManageFavourites;

  bool get _hasContent => controller.text.isNotEmpty;
  bool get _showSuggestions =>
      results.isNotEmpty || (errorMessage != null && !isSearching);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final favouritesAsync = ref.watch(favouriteLocationsProvider);
    final favourites = favouritesAsync.value ?? const <FavouriteLocation>[];
    return Material(
      // The panel needs a solid background so map tiles behind it
      // don't bleed through the rounded corners.
      color: theme.colorScheme.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                const SizedBox(width: 8),
                Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant),
                Expanded(
                  child: TextField(
                    key: const Key('mapPickerSearchField'),
                    controller: controller,
                    focusNode: focusNode,
                    textInputAction: TextInputAction.search,
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                    decoration: InputDecoration(
                      hintText: 'Search for a place',
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                if (isSearching)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_hasContent)
                  IconButton(
                    key: const Key('mapPickerSearchClear'),
                    icon: const Icon(Icons.close),
                    tooltip: 'Clear',
                    onPressed: onClear,
                  ),
              ],
            ),
          ),
          if (_showSuggestions)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: _SuggestionsList(
                results: results,
                errorMessage: errorMessage,
                onSelect: (r) => onSelectResult(r),
              ),
            ),
          // Quick-pick favourite chips (or the empty-state nudge
          // when no favourites exist yet). Always visible at the
          // bottom of the card so the user has a one-tap path to
          // their common places whenever the picker is open.
          if (favourites.isNotEmpty)
            _FavouriteChips(favourites: favourites, onSelect: onSelectFavourite)
          else
            _EmptyFavouritesHint(onTap: onManageFavourites),
        ],
      ),
    );
  }
}

/// Horizontal strip of saved-place chips. Tapping a chip drops
/// the pin at the favourite's location and adopts its default
/// radius — the core "two taps to set up a geofence" affordance.
class _FavouriteChips extends StatelessWidget {
  const _FavouriteChips({required this.favourites, required this.onSelect});

  final List<FavouriteLocation> favourites;
  final ValueChanged<FavouriteLocation> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('mapPickerFavouriteChips'),
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        itemCount: favourites.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final f = favourites[i];
          return Center(
            child: ActionChip(
              key: Key('mapPickerFavouriteChip_$i'),
              avatar: Icon(f.icon.iconData, size: 18),
              label: Text(f.name),
              onPressed: () => onSelect(f),
            ),
          );
        },
      ),
    );
  }
}

/// Inline nudge shown in the chip strip area when the user has
/// no saved places yet. One tap takes them to the Favourites
/// screen where the empty-state "Add Home / Add Work" buttons
/// are the guided on-ramp.
class _EmptyFavouritesHint extends StatelessWidget {
  const _EmptyFavouritesHint({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('mapPickerFavouritesEmptyHint'),
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        children: [
          const SizedBox(width: 8),
          Icon(
            Icons.bookmark_add_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Tip: save frequent places for one-tap picking',
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(onPressed: onTap, child: const Text('Manage')),
        ],
      ),
    );
  }
}

/// Renders either the suggestion hits or the "no matches" /
/// error line. Pulled out so [_SearchPanel.build] can stay
/// short and the suggestions get their own scrollable region
/// (the map can be tall, but the suggestions should never push
/// it off-screen).
class _SuggestionsList extends StatelessWidget {
  const _SuggestionsList({
    required this.results,
    required this.errorMessage,
    required this.onSelect,
  });

  final List<LocationSearchResult> results;
  final String? errorMessage;
  final ValueChanged<LocationSearchResult> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(
          errorMessage ?? '',
          style: theme.textTheme.bodySmall?.copyWith(
            color: errorMessage == null
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.error,
          ),
        ),
      );
    }
    return ListView.builder(
      key: const Key('mapPickerSearchResults'),
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: results.length,
      itemBuilder: (context, index) {
        final r = results[index];
        return ListTile(
          key: Key('mapPickerSearchResult_$index'),
          dense: true,
          leading: const Icon(Icons.place_outlined),
          title: Text(
            r.displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
          onTap: () => onSelect(r),
        );
      },
    );
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
