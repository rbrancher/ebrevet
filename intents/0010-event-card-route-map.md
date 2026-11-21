---
id: "0010"
title: Event card route map with OSM tiles (slice b of c)
requested_by: rbrancher
issue: 29
final_slice: false
priority: medium
size: M
risk: low
touches:
  - pubspec.yaml
  - lib/route_sketch.dart
  - lib/route_map.dart
  - lib/route_geometry.dart
  - lib/mock/mock_server.dart
  - test/route_map_test.dart
  - test/mock_server_test.dart
---

## Problem
Slice (a) (intent 0009, merged in #31) gave each event card a `RouteSketch`: the route
drawn locally over a neutral background. Issue #29 asks for a real map of the area behind
the route. Cards still show no roads, towns or terrain, so riders cannot place a ride on
the ground.

## User story
As a rider, I want the route on each event card drawn over a real map of the area, so
that I can see where the ride goes. When I have no signal I still want the route drawn.

## Acceptance criteria
- [x] AC1: `flutter_map` (and only what it needs transitively) is added to `pubspec.yaml`
      as the new dependency this issue asks for. The chosen version must resolve and build
      with the repo's current Flutter/Dart SDK constraint. If it cannot, the agent stops and
      reports the conflict rather than raising the SDK constraint. No other dependency is
      added. In particular there is no disk tile-cache package.
- [x] AC2: New `lib/route_map.dart` provides a static, non-interactive `RouteMap` widget
      with the same fixed aspect ratio as `RouteSketch`. Its `FlutterMap` has
      `InteractionOptions(flags: InteractiveFlag.none)`. Its camera fits the bounds of
      `RouteGeometry` (padded) so that every usable control is inside the view. A
      widget test checks the interaction flags and that every control is inside the camera's
      visible bounds. The camera fit must agree with the Web Mercator projection used by
      `route_geometry.dart`.
- [x] AC3: Tile source: one constant holds the URL template (OpenStreetMap standard tiles)
      and one holds the `userAgentPackageName`. A visible "© OpenStreetMap contributors"
      attribution is shown on every map. Tiles are only requested for the visible tiles of
      the card (no prefetching). A test checks the attribution text and the constants are
      used by the tile layer.
- [x] AC4: Route overlay on the map: polyline in control order with a contrasting casing,
      a distinct start marker, a distinct finish marker, dots for intermediate controls, and
      the combined start/finish marker for a loop. It uses theme colors only
      (`ColorScheme` / `AppTokens`). It reuses the geometry and marker logic from slice (a)
      (for example by extracting the shared painter) rather than duplicating it. The slice (a)
      `RouteSketch` tests still pass.
- [x] AC5: Tile provider is injectable. `RouteMap` takes an optional `TileProvider`, or
      reads one from a single seam, so tests pass a fake that never touches the network. In
      `flutter test` the default must not make requests. A test asserts the fake provider is
      the one used.
- [x] AC6: Offline and failure fallback: when tiles fail to load or are disabled, the
      overlay still draws on the neutral themed background from slice (a). No grey error
      tiles, no exception thrown, and the attribution stays. A widget test with a
      failing provider checks the overlay and attribution still render and nothing throws.
- [x] AC7: When the geometry is not drawable (fewer than 2 usable points, invalid
      coordinates, identical points) the card shows the slice (a) neutral placeholder, not a
      map, and creates no tile layer. When a map is shown, the semantics label is "Map of
      the route area with N controls" (N is the event's control count). The placeholder's
      semantics label is unchanged from slice (a). Tests cover both.
- [x] AC8: `EventCard` uses `RouteMap` in place of `RouteSketch` for upcoming events. The
      past-rides card behaviour from slice (a) is unchanged. Slice (a) card layout tests
      are updated for the new widget and still pass: one media widget per card, one filled
      ride button, all information still present.
- [x] AC9: In-session tile caching: tiles already fetched are reused when the list is
      reopened or a card is scrolled back into view, via Flutter's image cache (the
      `NetworkTileProvider` default), with no extra package. The list stays lazy so
      off-screen cards do not build maps. A test shows an off-screen card has no
      `FlutterMap` until scrolled into view.
- [x] AC10: Mock mode: `MockServer` passes through GET requests to the tile host only (host
      taken from the tile URL constant), using the same mechanism as the same-origin
      pass-through, created outside `http.runWithClient`. Every other request is handled as
      before (feed served from fixture, check-in POST mocked, unknown URLs 404). Check-in
      reports are never posted anywhere real. Unit tests check that a tile-host GET is
      passed to the passthrough client (a fake one, no network), that a POST to the tile
      host is not passed through, and that another host is still answered by the mock.
- [x] AC11: The event list in mock mode still passes `textContrastGuideline` and
      `androidTapTargetGuideline` in light and dark, using the fake tile provider, and
      the style guardrail baseline stays empty. No test makes a network request.
- [x] AC12: Check-in rules, codes, saved ride state and server reporting are unchanged.

## Out of scope
- Slice (c) (the last one): tapping the card map opens a full-screen interactive map
  (pan, zoom, control names) reusing the same tile layer and route overlay.
- A persistent on-disk tile cache. It would need another dependency; revisit if the
  in-session cache proves insufficient.
- Real route geometry along roads, since the feed has none.
- Tile provider switching UI, or any production tile-server account or key.
- Changes to check-in rules, codes, saved ride state or reporting.

## Test plan
Add `test/route_map_test.dart` (AC2 to AC7, AC9) with a fake `TileProvider`, extend
`test/mock_server_test.dart` (AC10), update `test/event_card_layout_test.dart` (AC8) and
the event-list guideline test (AC11). In the web preview (mock mode, real tiles are fine as
a read-only GET to the tile host), check that each upcoming card shows a map with the route
over it and OSM attribution, in light and dark, and that going offline (devtools network
off) leaves the route on the neutral background.

## UI notes
Keep the 5:2 media area from slice (a) so cards do not change height while tiles load.
Attribution sits in a small corner chip with readable contrast on map imagery.
