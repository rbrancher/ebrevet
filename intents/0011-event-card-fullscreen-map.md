---
id: "0011"
title: Tap the card map to open a full-screen interactive map (slice c of c)
requested_by: rbrancher
issue: 29
final_slice: true
priority: medium
size: M
risk: low
touches:
  - lib/route_map.dart
  - lib/route_map_page.dart
  - lib/event_card.dart
  - test/route_map_page_test.dart
  - test/event_card_layout_test.dart
  - test/event_list_screen_test.dart
---

## Problem
Slices (a) and (b) (intents 0009 and 0010, merged in #31 and #33) put a static map of the
route on each upcoming event card. It cannot be panned or zoomed and does not name the
controls, so a rider who wants a closer look at the route or at where a control is has no
way to get it from the card. Issue #29 lists a full-screen interactive map as the last step.

## User story
As a rider, I want to tap the map on an event card to open a full-screen map of the
route that I can pan and zoom and that shows the control names, so that I can study
the ride before I start.

## Acceptance criteria
- [ ] AC1: New `lib/route_map_page.dart` provides `RouteMapPage`, a full-screen page
      with a Material `AppBar` (event name and distance as the title, with a back button) that shows
      the event's route. It reuses the slice (b) tile constants and attribution, and the
      `RouteOverlay` / shared painter from slices (a) and (b). It does not duplicate them.
      No new dependency is added.
- [ ] AC2: The page's `FlutterMap` is interactive: drag and pinch/scroll zoom are enabled
      and rotation is disabled. Its initial camera uses the same fit as the card map, so
      every usable control is inside the initial view. Zoom is limited to the tile server's
      range (min 3 to max 19). A widget test checks the interaction flags, the zoom limits
      and that every control is in the initial view.
- [ ] AC3: Control names: each usable control has a marker on the page that shows the
      control's name. Names are readable and do not make the map unusable. The tap target of
      each marker is at least 48x48 dp. Tapping a marker shows the control's name
      and address (and its open/close times if the control is timed) in a bottom sheet or
      similar. A test checks that every control name is reachable (visible, or shown on tap)
      and that the tap targets pass `androidTapTargetGuideline`.
- [ ] AC4: Tile provider seam: `RouteMapPage` takes the same optional `TileProvider` and
      falls back to the same `RouteMap.tileProviderFactory` as the card map, so
      `flutter test` never makes network requests. The visible "© OpenStreetMap contributors"
      attribution is shown. Tiles are fetched for the visible area only, with no prefetching
      (a `panBuffer` of at most 1 is allowed for panning). A test asserts the fake provider is
      the one used.
- [ ] AC5: Offline and failure fallback: with a failing provider the route, control markers
      and attribution still render on the neutral themed background, with no exception
      thrown. Widget test.
- [ ] AC6: Non-drawable geometry (fewer than 2 usable points, invalid or identical
      coordinates): the card shows the slice (a) placeholder as today, and it is not tappable.
      No page is opened, because there is no map to show. Test.
- [ ] AC7: `EventCard`: tapping the card map pushes `RouteMapPage` for that event. The
      tappable map has a semantics button label such as "Open full-screen map of the
      route", and its hit area is at least 48 dp (the map is much larger than that).
      The map stays non-interactive inside the card, so list scrolling is unaffected. The
      past-rides card (`showRouteMap` false) is unchanged and not tappable. The slice (a)
      and (b) card layout tests still pass: one media widget per card, one filled ride
      button, all information present. Widget tests cover tap-to-open, back-to-list, and
      the unchanged past-rides card.
- [ ] AC8: The page survives rotation and resizing (no overflow) and works in light and dark.
      `textContrastGuideline` and `androidTapTargetGuideline` pass for the page and for the
      event list in mock mode, in light and dark, using the fake tile provider. The style
      guardrail baseline stays empty. No test makes a network request.
- [ ] AC9: Mock mode needs no new pass-through: tile GETs already reach the tile host
      (intent 0010 AC10). A test confirms the page makes no request other than tile GETs
      to that host, and that no check-in report is posted.
- [ ] AC10: Check-in rules, codes, saved ride state and server reporting are unchanged.

## Out of scope
- A "you are here" location marker or any live location on the map. That would need
  location access.
- Navigation, turn-by-turn, or opening external map apps (`lib/map_icon_button.dart`
  already does the latter for a single control).
- Real route geometry along roads, since the feed has none.
- A persistent on-disk tile cache, tile provider switching UI, or any production
  tile-server account or key.
- Changes to the My Rides layout, check-in rules, codes, saved ride state or reporting.

This is the last slice of issue #29.

## Test plan
Add `test/route_map_page_test.dart` (AC1 to AC6, AC8, AC9) with `FakeTileProvider` from
`test/support/fake_tiles.dart`, extend `test/event_card_layout_test.dart` and
`test/event_list_screen_test.dart` (AC7, AC8). In the mock-mode web preview, tap a card map:
the full-screen page opens with the route, named control markers and OSM attribution. Pan
and zoom, tap a marker for its details, go back to the list, and check light and dark.
Turning the network off in devtools leaves the route and markers on the neutral background.

## UI notes
Keep the page simple: map fills the body below the app bar, attribution chip in the
corner as on the card. Label markers with the control name or its index; long names may be
truncated on the marker, with the full name in the details sheet.
