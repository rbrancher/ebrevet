---
id: "0013"
title: Ride summary bottom sheet on the full-screen map (slice a of b)
requested_by: rbrancher
issue: 39
final_slice: false
priority: medium
size: M
risk: low
touches:
  - lib/route_map_page.dart
  - lib/ride_summary_sheet.dart
  - test/route_map_page_test.dart
  - test/ride_summary_sheet_test.dart
---

## Problem
The full-screen map (intent 0011) shows only the map. To see the key facts of a ride
(distance, start time, time limit, controls) a rider has to go back to the card or the
event page. Issue #39 asks for a collapsible summary on the map and, separately, for the
real route; this slice covers the summary only.

## User story
As a rider, I want a collapsible ride summary over the full-screen map so that I can see
the key facts of the ride and its controls without leaving the map.

## Acceptance criteria
- [ ] AC1: `RouteMapPage` shows a persistent Material 3 bottom sheet (a
      `DraggableScrollableSheet` inside the page body, not a modal) with a drag handle,
      overlaid on the map. It starts collapsed. Collapsed content: event name, distance and
      start date/time. Test.
- [ ] AC2: The sheet has three snap points (collapsed, half, expanded) with `snap: true`.
      Dragging up and down moves between them; a widget test checks the sheet extent after
      drags. Expanded content scrolls and has no overflow.
- [ ] AC3: Tapping the handle toggles the sheet (collapsed to half, half or expanded back to
      collapsed). The handle has a semantics label and tap action, and a tap target of at
      least 48 dp. `androidTapTargetGuideline` passes. Test.
- [ ] AC4: Map gestures still work in the area not covered by the sheet (a drag there pans
      the map). On opening, the route is fitted to the area above the collapsed sheet, so
      every usable control is inside the visible area and not behind the sheet. Test with
      the camera and the collapsed sheet height.
- [ ] AC5: Summary content, from existing `Event` and `Control` fields, all visible when the
      sheet is expanded for a sample event: name, distance (km), sanction and type; start
      date/time in the event's timezone and the time limit (start to end); start city and
      state; club and region; number of controls, with each control's name, distance and
      open/close times as a compact list (untimed controls show no times); gravel distance
      only if above 0; cue version or "No cue sheet"; organizer name. Test against a mock event.
- [ ] AC6: The organizer phone is a tappable link (`tel:`) where supported, with at least a
      48 dp tap target; where launching is unsupported (e.g. web) it is plain text. Launching
      goes through an injectable seam, and tests never launch anything. Missing or "?" values
      are omitted. No new dependency unless `url_launcher` is already in `pubspec.yaml`.
- [ ] AC7: Tapping a control marker no longer opens `ControlDetailsSheet` as a modal. The
      persistent sheet expands to at least half, scrolls its control list to that control and
      highlights it, showing the control's name, address and times. No second sheet is
      stacked. Test: tap a marker, expect no modal route pushed and the control highlighted.
- [ ] AC8: Tapping a control in the sheet's list centres the map on that control (map
      controller move, zoom unchanged or raised to a minimum useful level) and highlights it.
      Test checks the camera centre.
- [ ] AC9: The sheet uses the existing `ColorScheme` and `AppTokens`, with no hard-coded
      colours. `textContrastGuideline` and `androidTapTargetGuideline` pass in light and dark;
      no overflow on rotation or resize. The style guardrail baseline stays empty.
- [ ] AC10: The sheet and its list are included in semantics, in reading order. The map
      attribution chip stays visible and is not hidden by the collapsed sheet.
- [ ] AC11: Non-drawable geometry: the page behaves as today (no map) and shows the summary
      content without the map gestures. No exception. Test.
- [ ] AC12: No network or location access is added, and tests make no request. Check-in
      rules, codes, saved ride state and server reporting are unchanged.

## Out of scope
Slices still to come, in order:
- **Slice (b): the real route on the full-screen map.** Needs a decision on the feed field
  (an optional `route_polyline` Google encoded polyline, or a route link), a hand-written
  polyline decoder, an OSRM/Valhalla routed fallback behind one endpoint constant with a
  per-event in-memory cache and an injectable fake in tests, the "approximate road route" and
  "straight-line route" labels, sample routes in `examples/future_events.json`, and the
  mock-mode choice between a read-only GET pass-through for the router host and canned
  responses in `MockServer`. Cards keep straight lines.
  Persisting the field in `Event.toJson` is part of that slice's risk review.
- Note for the maintainer (not an action for this agent): ask upstream (ctnadovich) whether
  the randonneuring.org feed can include the route. Do not contact upstream.
- Any change to the cards, the list, check-in rules, codes, saved ride state or reporting.

## Test plan
Extend `test/route_map_page_test.dart` (AC1 to AC4, AC7, AC8, AC10, AC11) and add
`test/ride_summary_sheet_test.dart` for content and links (AC5, AC6, AC9) using the
`FakeTileProvider` from `test/support/fake_tiles.dart`. Update 0011 tests that expect the
modal `ControlDetailsSheet`. In the mock-mode web preview, open a card map: the sheet is
collapsed with name, distance and start; drag or tap the handle to half and expanded; tap a
marker and a list row; check light and dark.

## UI notes
Keep `ControlDetailsSheet` content reusable for the highlighted control inside the sheet.
Put the summary in a new `lib/ride_summary_sheet.dart` to keep `route_map_page.dart` small.
