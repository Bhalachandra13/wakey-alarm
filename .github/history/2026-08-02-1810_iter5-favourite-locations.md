# feat: favourite locations for geofence alarms

- **Date:** 2026-08-02 18:10
- **Iteration:** 5 (new — see workflow_plan.md)
- **Commit:** c21c00e

## What changed

Saves places the user visits often (Home, Work, the gym) and
makes them a one-tap pick target inside the geofence alarm
map picker. Together with the permission-UX follow-up in the
same iteration, this is the minimum delta that makes the
common "alarm me near home" use case 2 taps end-to-end.

### Data layer

- `favourite_locations` sqflite table (v2→v3 migration in
  `WakeyDatabase`). Columns: `id`, `name`, `icon_code`,
  `latitude`, `longitude`, `radius_meters`, `created_at`,
  `updated_at`. Lives alongside `alarms` rather than as a
  column on `alarms` because a single favourite is reused
  across many alarms — "Home" doesn't disappear when the
  alarm that first used it is deleted, and renaming "Home" →
  "Apartment" updates every alarm that points at it without
  a per-alarm rewrite.
- `FavouriteLocation` domain model with a tiny `FavouriteIcon`
  enum (`home`, `work`, `school`, `favorite`, `place`). The
  `code` (a stable string) is persisted so the column
  survives across app upgrades even if Material renames a
  glyph; `FavouriteIcon.fromCode` defensively falls back to
  `.place` for unknown codes (a future migration adding a new
  icon won't crash old builds). `FavouriteIcon.fromName`
  auto-picks an icon from a typed name ("Home" → home,
  "Office" → work, unknown → place) so the favourites list
  reads at a glance.
- `FavouriteLocationDao` (insert / read / getAll / update /
  delete / deleteAll / count). `getAll` sorts by
  `created_at ASC` so the user's mental order is preserved.
- `FavouriteLocationsNotifier` (Riverpod `AsyncNotifier`) with
  `add` (auto-picks icon from name, stamps `created_at` /
  `updated_at`), `edit` (rename/icon/radius — renamed from
  `update` to avoid clashing with `AsyncNotifier.update`),
  `move` (lat/lon/radius), `delete`. Plus a
  `favouriteLocationsProvider` convenience read-only view and
  a `hasFavouritesProvider` derived flag.

### UI

- **`FavouritesScreen`** — manage favourites. List with
  delete (confirm dialog, hard delete), tap-to-edit
  (reopens the map picker pre-filled; on confirm the
  favourite is *moved*, not duplicated), + in the app bar
  to add (opens picker → name dialog → save). Empty-state
  shows one-tap **Add Home** / **Add Work** `FilledButton.
  tonalIcon` affordances plus an **Add a custom place**
  `TextButton` escape hatch — the "pre-seed suggestion" from
  the design discussion, realised as a UI on-ramp rather than
  auto-created empty rows.
- **Quick-pick chip strip in `MapPickerScreen`** — the
  headline UX win. When the user has saved favourites, a
  horizontal row of `ActionChip`s (icon + name) sits at the
  bottom of the existing search panel. Tapping a chip drops
  the pin, flies the camera to zoom 14, and adopts the
  favourite's default radius — the "two taps to set up a
  geofence" affordance. When no favourites exist yet, an
  inline "Tip: save frequent places for one-tap picking"
  nudge with a "Manage" `TextButton` replaces the strip.
- **Entry point on the alarms screen** — a compact
  `_SavedPlacesRow` above the alarm list (bookmark icon +
  "Saved places" + count + chevron) pushes `FavouritesScreen`.
  Acts as both navigation and a discoverability signal.
- **`EditAlarmScreen` location section** — the existing
  "Pick on map" button now opens the picker with the chip
  strip visible, so picking a favourite requires no extra
  navigation hop.

### Tests (+31, 325 total)

- `test/data/favourite_location_dao_test.dart` (15): insert
  + id round-trip, read unknown → null, getAll ordering by
  `created_at`, update (with null-id throws), delete (with
  missing-id no-op), deleteAll, count, icon_code round-trip
  + `fromCode` fallback, lat/lon numeric round-trip,
  `FavouriteIcon.fromName` (common names, case-insensitive,
  whitespace-trimmed, unknown → place).
- `test/presentation/providers/favourite_locations_provider_test.dart`
  (7): build() empty, add (stamps timestamps, auto-icon,
  explicit icon honoured), edit (bumps `updated_at` only,
  not `created_at`), move (lat/lon/radius), delete,
  `hasFavouritesProvider` reflects the list.
- `test/presentation/screens/favourites_screen_test.dart` (6):
  empty state shows Add Home / Add Work / Add custom, Add
  Home pushes the map picker, populated list renders one
  row per saved favourite, delete button shows a confirmation
  dialog (Cancel keeps the row), tapping a row pushes the
  map picker pre-filled, + in the app bar pushes the map
  picker. Uses `tester.runAsync` to bridge the sqflite_ffi
  real-isolate read into the widget-test fake-async clock.
- `test/presentation/screens/map_picker_screen_test.dart`
  (+3): renders a chip per saved favourite (empty hint
  absent), tapping a chip drops the pin and adopts the
  favourite's radius (verified via `MapPickerResult` round-
  trip), shows the empty-state nudge when no favourites are
  saved. The chip tests override `favouriteLocationsProvider`
  with a stub list rather than seeding via the DAO because
  the map picker's `GoogleMap` widget throws on a platform-
  view create when the test uses `runAsync` to wait for the
  real isolate — the override bypasses the isolate read
  without losing the behaviour we're testing.

## Why

The geofence feature is the app's headline capability, and
on-device testing showed that "alarm me near home / near my
stop" — the dominant use case — required opening a map and
searching for the place on *every* alarm creation. That's
the single largest friction point in the headline flow.
Favourites collapse it to: open picker → tap Home → confirm.
The empty-state "Add Home / Add Work" affordance is the
guided on-ramp for first-time users so they discover the
feature without a tour.

## Scope note

`requirements.md` does not mention favourite locations. This
is an explicit addition agreed with the user after on-device
testing. The companion permission-UX follow-up
(`PermissionsSetupScreen` + consolidated `_PermissionsHealth
Banner`) is documented in `workflow_plan.md` Iteration 5 and
will land in a follow-up commit in the same iteration; it is
not in this commit.

## Files touched

- lib/data/wakey_database.dart (v2→v3 migration)
- lib/data/favourite_location_dao.dart (new)
- lib/domain/favourite_location.dart (new)
- lib/presentation/providers/favourite_locations_provider.dart (new)
- lib/presentation/screens/favourites_screen.dart (new)
- lib/presentation/screens/map_picker_screen.dart (chip strip + empty hint)
- lib/presentation/screens/alarms_screen.dart (Saved places entry row)
- test/data/favourite_location_dao_test.dart (new)
- test/presentation/providers/favourite_locations_provider_test.dart (new)
- test/presentation/screens/favourites_screen_test.dart (new)
- test/presentation/screens/map_picker_screen_test.dart (+3 tests)
- docs/workflow_plan.md (Iteration 5 section, scope note)

## Verification

- [x] `flutter analyze` clean
- [x] `flutter test` — 325 tests pass (+31 new, 0 regressions)
- [x] `dart format` clean (favourites files; unrelated
      whitespace in other files left as-is to keep the
      commit focused on the feature)
- [ ] Manual on-device: from a fresh install, confirm the
      empty-state Add Home / Add Work buttons open the map
      picker and the resulting favourite shows up in the
      chip strip on the next picker open. Per workflow_plan
      Iter 5 manual DoD; human verification on a real device.
