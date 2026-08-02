# feat: address search inside map picker + tests

- **Date:** 2026-08-02 17:05
- **Iteration:** 4
- **Commit:** 0e47096

## What changed

Moves the address-search affordance from the edit-alarm location
section into the map picker itself, where it belongs alongside
the map and the pin drop. The user now has a single,
unified "where do I want to be alarmed?" surface.

- `MapPickerScreen` gains a search field pinned to the top of
  the map (a new `_SearchPanel` widget). As the user types,
  a debounced call to `LocationSearchService` returns up to
  five Nominatim suggestions; tapping one drops the pin, flies
  the camera there, and clears the field. Stale in-flight
  requests are discarded via a per-call sequence number so the
  UI never shows a slow result behind a fast fresh query.
- `EditAlarmScreen` no longer renders a search field + result
  list. The location card now shows just the picked
  lat/long and a "Pick on map" / "Change on map" button. The
  search happens inside the picker, so the user never has to
  context-switch between a text form and a map.
- The floating hint over the map is updated to reflect both
  affordances ("Search for a place or pan the map to drop a
  pin").
- New `test/presentation/screens/map_picker_screen_test.dart`
  (7 tests): field renders on first paint; debounce collapses
  rapid keystrokes to one service call with the final query;
  selecting a suggestion returns the chosen coordinates; an
  empty query clears results without firing the service;
  `LocationSearchException` renders in the panel; a "no
  matches" response shows the empty message; stale in-flight
  calls do not overwrite a newer result.
- `edit_alarm_location_test.dart` updated: the in-screen
  search fake is gone, the "no search field here" assertion
  is added, and the new "Change on map" label is asserted.

Nominatim's usage policy caps us at 1 req/s; the search
debounces by 400 ms after the last keystroke and the IME
"search" action bypasses the debounce for an immediate fire.

## Why

The previous design had two parallel ways to pick a location
(search field on the edit screen, map in a separate picker)
and required the user to choose which one to engage with.
Collapsing them into one picker keeps the surface simple and
makes the "search then drop pin" flow a single tap.

Files touched references requirements.md §5.5
"Map-based location picker with Places Autocomplete address
search" and workflow_plan.md Iter 4 "Map-based location
picker screen".

## Files touched

- lib/presentation/screens/map_picker_screen.dart
- lib/presentation/screens/edit_alarm_screen.dart
- test/presentation/screens/map_picker_screen_test.dart (new)
- test/presentation/screens/edit_alarm_location_test.dart

## Verification

- [x] `flutter analyze` clean (re-verified in batch)
- [x] `flutter test` — all 294 tests pass (re-verified in
      batch; +7 new map_picker tests, several
      edit_alarm_location tests now assert the absence of the
      in-screen search field)
