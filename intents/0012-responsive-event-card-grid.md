---
id: "0012"
title: Responsive event card grid on tablets and desktop
requested_by: rbrancher
issue: 36
final_slice: true
priority: medium
size: M
risk: low
touches:
  - lib/responsive_card_grid.dart
  - lib/event_list_page.dart
  - lib/my_activated_events_page.dart
  - test/responsive_card_grid_test.dart
  - test/event_list_screen_test.dart
---

## Problem
`LatestEventList` (`lib/event_list_page.dart`) and `MyActivatedEventsPage`
(`lib/my_activated_events_page.dart`) put one `EventCard` per row in a plain `ListView`.
On an iPad mini, a desktop browser or the web preview each card becomes a very wide
strip. The 5:2 route map turns huge and mostly empty, the headline and details sit far
apart, and only one or two rides fit on screen.

## User story
As a rider on a tablet or desktop, I want event cards laid out in a responsive grid of
limited width so that I can see more rides at once and each card stays readable.

## Acceptance criteria
- [x] AC1: New `lib/responsive_card_grid.dart` provides a reusable layout widget (for example
      `ResponsiveCardGrid`) that takes a full-width header widget and a list of card
      widgets. It is used by both the event list and My Rides. No new dependency is added.
- [x] AC2: The column count is derived from a maximum card width constant and the available
      width, not from hard-coded breakpoints per device. The Material 3 window size classes
      (compact under 600, medium 600-839, expanded 840-1199, large 1200-1599,
      extra-large 1600 and up) are documented in the code, and the constants are chosen so
      that the counts below hold. Unit test of the column-count function: 390 dp gives 1,
      599 dp gives 1, 744 dp gives 2, 839 dp gives 2, 1280 dp gives 3, and 1920 dp or wider
      gives 3 or more.
- [x] AC3: Widget tests that set the test surface size check the cards per row, by comparing
      the top offsets of the rendered `EventCard`s: 390 dp wide gives 1 per row, as today;
      744 dp gives 2; 1280 dp gives 3; 1920 dp gives 3 or more.
- [x] AC4: Centred max-width body: the grid is centred, and its total width never exceeds a
      maximum body width constant, so on a very wide window (for example 3840 dp) the
      grid does not span edge to edge. At 1920 dp and 3840 dp no `EventCard` is wider than
      the maximum card width. Widget test.
- [x] AC5: Gutters and margins use `AppTokens` spacing (`spaceMedium` between cards in both
      directions, page margins as today). The spacing is the same horizontally and
      vertically, and the style guardrail baseline stays empty.
- [x] AC6: Uneven card heights work: cards in a row are top-aligned, none overlap, and none
      clip their content. The approach needs no fixed card height (lazy rows of top-aligned
      cards, or a `Wrap`; not a `GridView` with a fixed aspect ratio). A widget test with
      cards of different heights (with and without the gravel note, and with the My Rides
      delete button) at 744 dp and 1280 dp finds no overflow errors and no rectangle overlap.
- [x] AC7: The header (source selection, last refreshed, "Update event data", and the
      "Next update from" line) stays a full-width block above the grid at every size.
      Test: the header's top is above every card, and it is at least as wide as the card
      area at 390, 744, 1280 and 1920 dp. The button still triggers a refresh.
- [x] AC8: My Rides (`MyActivatedEventsPage`) uses the same layout and the same column counts
      at 390, 744 and 1280 dp. `showRouteMap: false`, delete and tap behaviour are
      unchanged. An empty list still renders without error.
- [x] AC9: Resizing and rotation reflow live: a test changes the surface size from 390 to
      744 to 1280 dp (and a landscape/portrait swap) in the same pumped widget tree and checks
      that the column count follows, without exceptions.
- [x] AC10: Intents 0010 and 0011 still hold in the narrower card: the map keeps its
      aspect ratio, so its width divided by its height is unchanged at 744 and 1280 dp. The map
      tile requests still go through the fake provider, off-screen cards are built lazily
      (tiles of off-screen cards are not requested, which needs a lazy sliver-based or
      equivalent layout), and tapping the map opens `RouteMapPage`. The existing card
      layout tests (one media widget, one filled ride button, all information present)
      still pass.
- [x] AC11: `textContrastGuideline` and `androidTapTargetGuideline` pass for the list at the
      three widths, in light and dark. No test makes a network request.
- [x] AC12: Presentation only: event data, check-in rules, codes, saved ride state and server
      reporting are unchanged. The mock-mode web preview shows 1, 2 and 3 columns as the
      browser is resized.

## Out of scope
- Changes to the content or internals of `EventCard`, apart from what the layout needs (for
  example, dropping horizontal margins if the grid owns the spacing).
- Master-detail or other canonical layouts, a navigation rail, or changes to other pages
  (settings, controls, profile, certificate).
- A user setting for the column count, or a list/grid toggle.
- Text scale or font changes.

## Test plan
Add `test/responsive_card_grid_test.dart` (AC1 to AC9, AC11) with a small fake card
builder for uneven heights, and extend `test/event_list_screen_test.dart` for the real
`EventCard`s from mock events (AC3, AC7, AC10). Use `tester.view.physicalSize` with
`devicePixelRatio = 1`. In the mock-mode web preview, resize the browser from
phone width up to a desktop width: the grid goes from 1 to 2 to 3 columns, the header stays
on top at full width, and the map in each card opens the full-screen map. Check My Rides too.

## UI notes
Sketch: use a `CustomScrollView` with the header as a `SliverToBoxAdapter`, then a lazy
sliver for the cards inside a centred `ConstrainedBox`. If no stock sliver fits uneven
heights, build lazy rows of N cards in a `SliverList`, each row a top-aligned `Row` of
`Expanded` cards. Do not use `shrinkWrap`, which would break AC10's lazy tile loading.
