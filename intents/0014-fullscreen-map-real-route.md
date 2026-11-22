---
id: "0014"
title: Draw the real route on the full-screen map (slice b of b)
requested_by: rbrancher
issue: 39
final_slice: true
priority: medium
size: M
risk: medium
touches:
  - lib/event.dart
  - lib/route_polyline.dart
  - lib/route_service.dart
  - lib/route_map.dart
  - lib/route_map_page.dart
  - lib/mock/mock_server.dart
  - examples/future_events.json
  - assets/mock/future_events.json
  - test/route_polyline_test.dart
  - test/route_service_test.dart
  - test/route_map_page_test.dart
  - test/mock_server_test.dart
---

## Problem
The full-screen map (intents 0011 and 0013) draws straight segments between controls, so a
rider cannot see which roads the ride follows. The feed has no route geometry. Issue #39,
part 2, asks for the real route on the full-screen view only. Slice (a) (intent 0013, merged
in #41) added the summary sheet.

## User story
As a rider, I want the full-screen map to show the roads the ride follows so that I can
see where the ride goes before I start.

## Acceptance criteria
Route source order: (1) the feed's route, (2) a routed road path, (3) straight lines.

- [x] AC1: Feed field. `Event` reads an optional `route_polyline` string (Google encoded
      polyline, precision 5) into a nullable decoded point list. Absent, null, non-string
      or malformed values give no route and never throw; `Event.fromJson` still succeeds
      and all other fields parse as before. Test with good, absent and malformed input.
- [x] AC2: `lib/route_polyline.dart` holds a hand-written decoder (no new dependency).
      Tests check it against known polylines with known decoded points (including the
      Google documentation example `_p~iF~ps|U_ulLnnqC_mqNvxq`@` = (38.5,-120.2),
      (40.7,-120.95), (43.252,-126.453)), negative deltas, an empty string, and
      truncated or garbage input. Garbage or truncated input yields no route, not an
      exception. Points outside valid lat/long, or fewer than 2 points, count as no route.
- [x] AC3: Persisted state is unchanged. The decoded route is NOT written by
      `Event.toJson` (the saved-ride JSON has the same keys as before), and restoring a
      saved event still works. Regression test: `toJson` of an event with a feed route has
      no route key, and a round trip keeps every existing field.
- [x] AC4: Feed route drawn. `RouteMapPage` for an event with a valid feed route draws the
      decoded polyline in place of the straight segments. No router call is made. The
      control markers, start and finish markers and contrast casing from 0010 and 0011
      stay on top of the line. Test: the line's points equal the decoded points.
- [x] AC5: Router seam. New `lib/route_service.dart` has a `RouteService` with one
      injectable async method that takes the ordered usable control coordinates and
      returns road geometry or null. The router endpoint (base URL and cycling profile)
      is one constant. The default implementation does a read-only GET with `http`, a
      timeout of at most 10 s, and an identifying user agent (set where the platform
      allows it; browsers set their own), and parses the response defensively (malformed
      or non-OK responses give null). Tests use a fake, never the network.
- [x] AC6: Only control coordinates are sent: the request URL is built from control
      lat/long only (no rider ID, event ID, name or any other field). Unit test on the
      built URL.
- [x] AC7: Routed fallback. For an event without a feed route and at least 2 usable
      controls, opening `RouteMapPage` requests the route once and draws the returned
      geometry, labelled "Approximate road route" with the semantics label
      "approximate road route; may differ from the official course". Test with a fake
      service: geometry drawn, label and semantics present, call count is 1.
- [x] AC8: Cache. Results are cached in memory per event ID and control coordinates, so
      closing and reopening the map for the same event does not call the router again,
      and a changed control set does. Failures (null) are not cached beyond the page, so
      a later reopen may retry. Test: two opens, one call.
- [x] AC9: Fallback. If the router returns null, throws, times out or returns fewer than 2
      points, the page keeps the straight lines and shows a subtle "Straight-line route"
      label (also in semantics). No error dialog, snackbar or exception. Tests for null,
      throw and timeout (fake with a never-completing future and a short timeout).
      While the request is in flight the straight lines are shown with no error label.
      A response arriving after the page is disposed does nothing.
- [x] AC10: Cards unchanged. `EventCard`, the list and the card map keep the
      straight-line sketch and make no router calls and no feed-route drawing. Test that a
      list with several events calls the fake service zero times.
- [x] AC11: Request discipline. The router is called only when the full-screen map opens,
      once per event, never from the list, a card or prefetching. Events with a feed
      route, or with non-drawable geometry, make no call.
- [x] AC12: Fit and markers. The initial fit (0013 AC4) still covers every usable control
      and is not affected by the drawn geometry arriving later (the camera does not jump
      when the routed line replaces the straight one). Test the camera before and after.
- [x] AC13: Mock mode. `examples/future_events.json` and `assets/mock/future_events.json`
      (keep them in sync as today) get a valid `route_polyline` on some events, leaving
      others without it. `MockServer` serves canned routed responses for the router host
      for the events without one, and does NOT pass requests to the real router (the
      existing same-origin and tile GET pass-through is unchanged). The preview thus
      shows the feed route, the labelled approximate route and the straight-line case,
      with no external request other than tiles. `mock_server_test.dart` covers the
      canned response and that other hosts are still not passed through.
- [x] AC14: Labels and route line use the existing `ColorScheme` and `AppTokens` with no
      hard-coded colours. The label does not cover the attribution chip or the sheet's
      handle, and `textContrastGuideline` passes in light and dark. The style guardrail
      baseline stays empty.
- [x] AC15: No change to check-in rules, codes, saved ride state or server reporting. No
      rider data leaves the device. `flutter analyze`, `flutter test` and `dart format`
      are green.

## Out of scope
- Cards, the list and the card map keep straight lines.
- Contacting upstream. Note for the maintainer (not an action for this agent): ask
  upstream (ctnadovich) whether the randonneuring.org feed can include the official
  route, as `route_polyline` or a route link.
- A hosted or paid router, API keys, or offline route storage.
- Persisting the route in saved rides. A restored ride reloads it from the feed or the
  router when the map opens.
- Route links (Ride with GPS IDs). Only the encoded polyline is supported.
- Any change to check-in rules, codes, saved ride state or reporting.

## Test plan
Add `test/route_polyline_test.dart` (AC1, AC2), `test/route_service_test.dart` (AC5, AC6,
AC8), extend `test/route_map_page_test.dart` (AC4, AC7 to AC12, AC14), `mock_server_test.dart`
(AC13), and an `Event` toJson regression test (AC3). In the mock-mode web preview, open the
full-screen map of an event with a feed route (real line, no label), one without (approximate
label) and check the straight-line case; light and dark.

## UI notes
Decisions made here for the agent: the feed field is `route_polyline` (Google encoded
polyline), the simplest to decode by hand and to embed in JSON. Mock mode serves canned
router responses instead of passing through to the router host, so previews never call a
public routing server and the result is deterministic. The public OSRM demo server is
car-only and has a strict usage policy, so choose a cycling-capable endpoint and keep its
URL in the single constant, with a code comment noting it must be swapped for a hosted
service if usage grows. Keep the label small (a chip near the top of the map).
