import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;

/// Icon for a [FavouriteLocation].
///
/// Stored as a stable string [code] in the database so that the
/// `icon_code` column survives across app upgrades even if the
/// Material icon set renames a glyph. The [iconData] getter maps
/// back to the Flutter [IconData] for rendering.
///
/// The set is intentionally tiny — five values cover the common
/// "frequent place" cases (home, work, school, generic favourite,
/// generic place). User-typed names that don't match a known
/// category fall through to [FavouriteIcon.place].
enum FavouriteIcon {
  home('home'),
  work('work'),
  school('school'),
  favorite('favorite'),
  place('place');

  const FavouriteIcon(this.code);

  /// Stable string identifier persisted in the `icon_code` column.
  final String code;

  /// Flutter icon used to render the favourite in the UI.
  IconData get iconData {
    switch (this) {
      case FavouriteIcon.home:
        return Icons.home_outlined;
      case FavouriteIcon.work:
        return Icons.work_outline;
      case FavouriteIcon.school:
        return Icons.school_outlined;
      case FavouriteIcon.favorite:
        return Icons.favorite_outline;
      case FavouriteIcon.place:
        return Icons.place_outlined;
    }
  }

  static FavouriteIcon fromCode(String? code) {
    for (final icon in FavouriteIcon.values) {
      if (icon.code == code) return icon;
    }
    return FavouriteIcon.place;
  }

  /// Auto-pick an icon based on the favourite's display [name].
  /// Used when the user adds a new favourite and hasn't chosen
  /// an icon explicitly — Home/Work/School/Gym-style names map
  /// to a sensible default so the list reads at a glance.
  static FavouriteIcon fromName(String name) {
    final lower = name.trim().toLowerCase();
    if (lower.contains('home') || lower.contains('house')) {
      return FavouriteIcon.home;
    }
    if (lower.contains('work') ||
        lower.contains('office') ||
        lower.contains('job')) {
      return FavouriteIcon.work;
    }
    if (lower.contains('school') ||
        lower.contains('university') ||
        lower.contains('college')) {
      return FavouriteIcon.school;
    }
    if (lower.contains('gym') ||
        lower.contains('favorite') ||
        lower.contains('favourite') ||
        lower.contains('star')) {
      return FavouriteIcon.favorite;
    }
    return FavouriteIcon.place;
  }
}

/// A user-saved place that can be quickly picked as the geofence
/// center when creating a location alarm. See Iteration 5
/// (favourites) in `workflow_plan.md`.
///
/// Favourites live in their own table (rather than as a column on
/// the `alarms` table) because a single favourite is typically
/// referenced by many alarms — "Home" doesn't disappear when the
/// alarm that first used it is deleted, and renaming "Home" to
/// "Apartment" updates every alarm that points at it without a
/// per-alarm rewrite.
@immutable
class FavouriteLocation {
  const FavouriteLocation({
    this.id,
    required this.name,
    required this.icon,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Auto-increment DB id. Null for a not-yet-inserted record.
  final int? id;

  /// User-facing name, e.g. "Home", "Work", "Gym".
  final String name;

  /// Icon shown in the favourites list and the map-picker chip.
  /// Persisted as [FavouriteIcon.code] in the DB.
  final FavouriteIcon icon;

  /// WGS84 latitude of the favourite's center.
  final double latitude;

  /// WGS84 longitude of the favourite's center.
  final double longitude;

  /// Default radius in meters (200 m – 20 km) used when this
  /// favourite is picked for a new geofence alarm. The user can
  /// adjust the radius on the alarm afterwards; the favourite's
  /// stored radius is just a sensible default.
  final int radiusMeters;

  /// ISO 8601 timestamp of when the favourite was first saved.
  final String createdAt;

  /// ISO 8601 timestamp of the last edit (rename, move, …).
  final String updatedAt;

  /// Returns a copy with the given fields replaced. Used by the
  /// DAO and the favourites screen for rename / move operations.
  FavouriteLocation copyWith({
    int? id,
    String? name,
    FavouriteIcon? icon,
    double? latitude,
    double? longitude,
    int? radiusMeters,
    String? createdAt,
    String? updatedAt,
  }) {
    return FavouriteLocation(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'icon_code': icon.code,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory FavouriteLocation.fromJson(Map<String, Object?> json) {
    return FavouriteLocation(
      id: json['id'] as int?,
      name: json['name'] as String,
      icon: FavouriteIcon.fromCode(json['icon_code'] as String?),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusMeters: json['radius_meters'] as int,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FavouriteLocation &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          icon == other.icon &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          radiusMeters == other.radiusMeters &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    icon,
    latitude,
    longitude,
    radiusMeters,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'FavouriteLocation(id: $id, name: $name, '
      'lat: ${latitude.toStringAsFixed(4)}, '
      'lon: ${longitude.toStringAsFixed(4)}, '
      'radius: ${radiusMeters}m)';
}
