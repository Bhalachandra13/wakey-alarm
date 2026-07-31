import 'dart:convert';

import 'package:http/http.dart' as http;

/// A single location search hit returned by [LocationSearchService.search].
///
/// Display name is the human-readable label Nominatim returns (e.g.
/// "Eiffel Tower, 5 Avenue Anatole France, 75007 Paris, France"). The
/// latitude/longitude are the WGS84 coordinates for the hit, ready
/// to drop into a geofence alarm.
class LocationSearchResult {
  const LocationSearchResult({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });

  final String displayName;
  final double latitude;
  final double longitude;
}

/// Thin HTTP client around the public OpenStreetMap Nominatim search
/// endpoint, used by the location tab to let the user pick a place
/// by name instead of dropping a pin on the map.
///
/// We use Nominatim (rather than Google Places Autocomplete) because
/// the project has no Google Maps API key configured — the key in
/// the manifest is a placeholder. Nominatim requires a descriptive
/// `User-Agent` header per its usage policy; we send one identifying
/// the app.
///
/// Nominatim's usage policy caps us at 1 request/second; the UI
/// enforces this by only firing on a button press (no
/// keystroke-driven autocomplete).
class LocationSearchService {
  LocationSearchService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// Maximum number of results returned per search.
  static const int _resultLimit = 5;

  /// Queries Nominatim for [query] and returns up to 5 hits, ordered
  /// by Nominatim's relevance ranking. Returns an empty list if no
  /// results match. Throws [LocationSearchException] on transport
  /// errors or non-2xx responses.
  Future<List<LocationSearchResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': trimmed,
      'format': 'json',
      'limit': _resultLimit.toString(),
      'addressdetails': '0',
    });
    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: const {
          // Nominatim's usage policy requires an identifying
          // User-Agent; the default Dart HTTP user agent is
          // generic and gets rate-limited.
          'User-Agent': 'WakeyWakey/1.0 (alarm app)',
          'Accept': 'application/json',
        },
      );
    } on Object catch (e) {
      throw LocationSearchException('Search request failed: $e');
    }
    if (response.statusCode != 200) {
      throw LocationSearchException(
        'Search returned status ${response.statusCode}',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on Object catch (e) {
      throw LocationSearchException('Search response was not valid JSON: $e');
    }
    if (decoded is! List) {
      return const [];
    }
    final results = <LocationSearchResult>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final lat = entry['lat'];
      final lon = entry['lon'];
      final name = entry['display_name'];
      if (lat is! String || lon is! String || name is! String) continue;
      final parsedLat = double.tryParse(lat);
      final parsedLon = double.tryParse(lon);
      if (parsedLat == null || parsedLon == null) continue;
      results.add(
        LocationSearchResult(
          displayName: name,
          latitude: parsedLat,
          longitude: parsedLon,
        ),
      );
    }
    return results;
  }
}

/// Thrown by [LocationSearchService.search] when the underlying
/// HTTP call fails or returns an unexpected payload. The UI is
/// expected to surface this in a SnackBar and leave the previously
/// picked location untouched.
class LocationSearchException implements Exception {
  const LocationSearchException(this.message);

  final String message;

  @override
  String toString() => 'LocationSearchException: $message';
}
