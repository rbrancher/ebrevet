---
id: "0017"
title: Segmented region switcher on the events page (slice c of c)
requested_by: rbrancher
issue: 44
final_slice: true
priority: medium
size: M
risk: low
touches:
  - lib/event_list_page.dart
  - lib/scheduled_events.dart
  - test/region_switcher_test.dart
---

## Problem
Slices (a) and (b) (intents 0015 and 0016) let a rider configure several event sources,
each with its own cache. The events page still shows only the first-selected source and
the rider has to go to Settings to look at another region. Issue #44 asks for a segmented
switcher at the top of the events page. This is slice (c), the last one.

## User story
As a rider, I want to switch between my configured regions on the events page so that I
can look at another region's calendar instantly, even offline.

## Acceptance criteria
- [ ] AC1: Switcher placement. `lib/event_list_page.dart` shows a Material 3 region
      switcher under the app bar and above the existing header (source info, last
      refreshed, "Update event data"), with one segment per entry of `EventSources.list`
      in configured order. Widget test with three sources.
- [ ] AC2: Hidden for one source. With one configured source no switcher is built and the
      page looks as it does today. Widget test.
- [ ] AC3: Labels. Each segment has a short label (the region's short name, "Custom" for
      the custom source, the region ID for a region not in `Region.regionMap`). The full
      name (`fullDescription`) is the tooltip and the semantics label. Widget test.
- [ ] AC4: Instant switching. Selecting a segment updates `SourceSelection` and persists
      the choice through `EventSources.select`. The list then shows that source's cached
      events and that source's own last-refreshed time, with no network call. Other
      sources' caches and last-refreshed times are unchanged. Widget test with two
      cached sources.
- [ ] AC5: Per-source refresh. "Update event data" refreshes only the selected source
      (existing behaviour; tested through the mock server): after refreshing B, A's
      events and last-refreshed time are unchanged. Test.
- [ ] AC6: Many sources. With more sources than fit (about 5 at 390 dp) the switcher is a
      horizontally scrollable row of single-select segments (for example a scrollable
      `SegmentedButton` or `ChoiceChip` row) and the selected segment is scrolled into
      view. The chosen behaviour is documented in a code comment and in
      `docs/ARCHITECTURE.md` if it describes the events page. Widget test at 390 dp with 5
      sources: no overflow errors, the last segment is reachable by scrolling and
      tappable.
- [ ] AC7: Remembered. The last selection is restored after a restart: a new
      `SourceSelection` with the saved preferences selects the same source and the
      switcher shows it selected. Test. If the saved selection was removed in Settings,
      the first source is selected (existing `EventSources.selected` rule).
- [ ] AC8: Settings changes. Adding, removing or reordering sources in Settings updates
      the switcher when returning to the events page (including its appearing for two
      sources and disappearing for one). Widget test.
      Reordering in Settings no longer changes the selection: drop the slice (b)
      "reorder selects the first source" behaviour (`selectFirst` on reorders) now that
      the switcher selects explicitly. Removing the selected source still selects the
      first remaining one. Test: select B, move A below C, B stays selected.
- [ ] AC9: Mock mode. In the mock-mode web preview with two regions configured, the
      switcher shows both and switching shows the distinct mock feeds.
- [ ] AC10: Activated events, My Rides, check-in and start-code lookups still resolve
      across all sources whichever is selected (existing tests keep passing). No change
      to check-in rules, codes (`signature.dart`), the saved ride format or server
      reporting. `flutter analyze`, `flutter test` and `dart format` are green.

## Out of scope
- Merging all regions into one list, server changes, more than one custom URL source
  (not in any slice).
- Changes to the Settings picker (slice b, merged).

## Test plan
New `test/region_switcher_test.dart` (AC1 to AC8) using mock shared preferences, temp
storage and `test/support/event_sources.dart`; AC5 uses the mock server. Existing
`event_list_screen_test.dart` must keep passing. Preview: in Settings add two regions,
go to the events page, switch between them, refresh one, restart and check the selection.

## UI notes
Use a Material 3 `SegmentedButton` (single selection) when the segments fit, otherwise
the scrollable fallback in AC6. Keep labels short. Risk is low: UI-only change on top of
the data model from slice (a); it reads and writes only the selected-source setting.

New files under `lib/` start with `// Copyright (C) 2026 eBrevet autonomous AI-SDLC` and the
same GPL-3 notice the existing files carry, never a copied `Chris Nadovich` line.
