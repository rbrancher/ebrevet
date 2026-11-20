---
id: "0009"
title: Event card headline/subhead hierarchy and route sketch (slice a of c)
requested_by: rbrancher
issue: 29
final_slice: false
priority: medium
size: M
risk: low
touches:
  - lib/event_card.dart
  - lib/route_geometry.dart
  - lib/route_sketch.dart
  - test/route_geometry_test.dart
  - test/event_card_layout_test.dart
---

## Problem
Issue #29 asks for event cards that are easy to scan, with a map of the route on top. Today
every card is a `ListTile` whose name is only `titleMedium`, and the club, city, start
style, date, gravel note and cue version are equal-weight lines. Riders cannot tell rides
apart at a glance. The full request (real map tiles with attribution, caching, new
`flutter_map` dependency, mock-server pass-through) is too big for one change, so this is
slice (a) of (a) to (c). It delivers the card hierarchy and a dependency-free route sketch,
and builds the geometry that the map slice will reuse.

## User story
As a rider, I want each event card to show the ride name prominently with the club
underneath, and a small drawing of the route's shape, so that I can tell rides apart at a
glance.

## Acceptance criteria
- [x] AC1: New pure-Dart `lib/route_geometry.dart` takes an event's controls and returns
      the usable points in control order (skipping controls with non-finite coordinates,
      out-of-range lat/long, or exactly 0,0), plus the padded bounding box covering them.
      Points are projected with spherical Web Mercator (EPSG:3857, the projection
      `flutter_map` and OSM tiles use), so slice (b) can lay the same route over map tiles
      without re-deriving the projection. Fitting into a target size uses one uniform scale
      for x and y, centred, so the route's shape is never stretched to the card's aspect
      ratio. Unit tests check:
      - order is preserved
      - padding is applied and every point lies inside the padded box
      - a start-equals-finish loop keeps both points
      - invalid points are dropped
      - a north-south route and an east-west route of equal ground length keep equal
        length when fitted into a 16:9 box (uniform scale)
- [x] AC2: The geometry reports "not drawable" when fewer than 2 usable points remain or
      all points are identical (zero extent). Unit tests cover a single control, all-invalid
      controls, and identical points.
- [x] AC3: New `RouteSketch` widget draws the route with a `CustomPaint` on a neutral
      themed background (`ColorScheme` / `AppTokens` only, no literal colors). It draws the
      polyline in control order with a contrasting casing, a distinct start marker, a
      distinct finish marker and dots for intermediate controls. For a loop (start equals
      finish) it draws a combined start/finish marker rather than hiding one marker. It has
      a fixed aspect ratio and no gestures. A widget test checks the fixed size and that no
      gesture detector or scrollable is added.
- [x] AC4: `RouteSketch` has semantics label "Sketch of the route with N controls" (N is
      the control count of the event, not the usable count). When the geometry is not
      drawable it shows a neutral placeholder of the same size with an icon, and no painter.
      Widget tests cover both.
- [x] AC5: `EventCard` places the `RouteSketch` at the top of the card for upcoming events
      in the event list, above the text. The sketch is drawn locally: no tiles, no network
      access. A widget test with the mock feed checks each card has one.
- [x] AC6: The card's headline (event name and distance) uses `titleLarge` with a bolder
      weight than today, and the club name is a subhead using `onSurfaceVariant`. A widget
      test checks the headline font size and weight are greater than the subhead's.
- [x] AC7: The card keeps every item it shows today: club, start city and state, start
      style, gravel line when present, date and status text, UNDERWAY! state, cue version,
      the info and check-ins buttons, the outcome row from intent 0002 and the single
      filled RIDE / PRE-RIDE button. Only layout and emphasis change. Existing event-list
      tests still pass and a test asserts each item is present on a mock-feed card.
- [x] AC8: Distance and the gravel percentage may become compact chips. If so, the full
      gravel text remains available to screen readers.
- [x] AC9: The card in My Rides (past rides) still renders correctly with the shared
      widget. It may omit the sketch there if the layout is cramped. A widget test pumps it.
- [x] AC10: The event list in mock mode passes `textContrastGuideline` and
      `androidTapTargetGuideline` in light and dark. The style guardrail baseline stays
      empty. No new dependency is added to `pubspec.yaml`.
- [x] AC11: Check-in rules, codes, saved ride state and server reporting are unchanged.

## Out of scope
- Slice (b): replace the neutral background with a real static `flutter_map` base map. It
  adds the dependency, an OSM tile layer (URL template in one constant,
  `userAgentPackageName`, visible "© OpenStreetMap contributors" attribution, tile cache,
  no prefetching), an injectable tile provider so tests never hit the network, the
  `MockServer` pass-through for the tile host only, and the offline fallback to the slice
  (a) sketch. It reuses `route_geometry.dart`.
- Slice (c): tapping the card map opens a full-screen interactive map with control names.
- Drawing real route geometry, since the feed has none.
- Any change to check-in rules, saved ride state, or the My Rides page layout beyond what
  the shared card changes.

## Test plan
Add `test/route_geometry_test.dart` (AC1, AC2) and `test/event_card_layout_test.dart`
(AC3 to AC9), using the mock fixture `assets/mock/future_events.json`. Extend the existing
event-list guideline test for AC10. In the web preview, check that each card shows a route
shape on top, the ride name as the headline and the club below it, in light and dark.

## UI notes
Follow the Material 3 card anatomy: media (sketch), headline, subhead, supporting text,
actions. Fixed aspect ratio (for example 16:9, or shorter) so cards do not change height.
