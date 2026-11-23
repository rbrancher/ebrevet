---
id: "0016"
title: Settings multi-select for event regions (slice b of c)
requested_by: rbrancher
issue: 44
final_slice: false
priority: medium
size: M
risk: medium
touches:
  - lib/settings_page.dart
  - lib/scheduled_events.dart
  - lib/region_picker_page.dart
  - test/region_picker_test.dart
  - test/settings_event_sources_test.dart
---

## Problem
Slice (a) (intent 0015) added a persisted, ordered list of event sources
(`EventSources`) with separate caches, but Settings still edits a single source through
the "Event Info Source" dropdowns (`scheduleEventsSourceID` and `regionID`). A rider
cannot yet configure more than one region. Issue #44 asks for a multi-select
configuration. This is slice (b): the Settings side only. The segmented switcher on the
events page is slice (c).

## User story
As a rider, I want to choose several regions (US, International, and the custom URL) in
Settings, and order or remove them, so that I can follow more than one region's calendar.

## Acceptance criteria
- [ ] AC1: Summary row. The "Event Info Source" section in Settings shows a summary row
      such as "3 regions" (singular "1 region" for one) listing the configured sources
      in order. Tapping it opens a full-screen region picker page
      (`lib/region_picker_page.dart`). Widget test.
- [ ] AC2: Categories. The picker keeps the three categories: International, US and
      Custom. Within International and US the rider can select one or more regions from
      `Region.regionMap`, each as a `CheckboxListTile`, grouped by state or country and
      sorted with `Region.compareByStateName`. Widget test: checking two US regions and
      one International region adds three entries.
- [ ] AC3: Search. A search field filters the region list by region name, state or
      country, case-insensitively. An empty result shows a short "No matching regions"
      message. Widget test.
- [ ] AC4: Custom. The custom URL source can be added or removed alongside regions. Its
      URL and secret fields stay in Settings as today, shown while the custom source is
      configured. Only one custom source is supported (more than one is a nice-to-have
      and not in any slice). Widget test: custom plus a region are both configured.
- [ ] AC5: Reorder and remove. The configured list can be reordered (drag handle, with
      move up/down actions as a non-drag alternative) and a source can be removed. The
      order is persisted through `EventSources.save`. Removing the last remaining source
      is not allowed: the control is disabled and an explanation is shown. Widget tests
      for reorder, remove and the last-source guard.
- [ ] AC6: Persistence. The saved list and order come back after a restart (reload
      `EventSources.list` from shared preferences in the test). Duplicates cannot be
      created from the picker. Test.
- [ ] AC7: Selected source stays valid. If the selected source is removed, the first
      remaining source becomes selected, `SourceSelection` is updated, and the event list
      shows that source's cached events. Removing a source drops its cache file and
      in-memory cache; no other source's cache or last-refreshed time changes. Test:
      with A, B, C cached, remove B and A and C are unchanged.
- [ ] AC8: Unknown region. A configured region ID missing from `Region.regionMap` is shown
      in the list with the existing "region not in the list of regions this app knows
      about" message and can be removed. It never crashes the page. Test.
- [ ] AC9: Old Settings controls. The single source dropdowns are replaced by the summary
      row. The old settings keys (`scheduleEventsSourceID`, `regionID`) are no longer
      written by the picker, and are not removed or changed (a downgrade still works).
      The "Get Latest Region List" button keeps working and the picker rebuilds from the
      new `Region.regionMap`. Test.
- [ ] AC10: Mock mode. In the mock-mode web preview, Settings lets me add and remove
      regions. The events page shows the selected source's events (switching between
      sources before slice (c) is by choosing the first entry). Existing widget tests
      keep passing.
- [ ] AC11: No change to check-in rules, codes (`signature.dart`), the saved ride format or
      server reporting. At 390 dp the picker page has no overflow errors. `flutter
      analyze`, `flutter test` and `dart format` are green.

## Out of scope
Slices of issue #44, in order:
- Slice (c): the Material 3 segmented region switcher at the top of
  `lib/event_list_page.dart`, under the app bar and above the existing header. One
  segment per configured source in configured order, with short labels and the full name
  as tooltip or semantics label. Hidden for one source. Switching is instant, shows that
  source's cached events and its own last-refreshed time, and "Update event data"
  refreshes only the selected source. A horizontally scrollable fallback for many sources
  that works at 390 dp with about 5 sources (behaviour documented). The last selection is
  remembered across restarts (through `EventSources.select`). Slice (c) sets
  `final_slice: true`.
- Not in any slice: merging all regions into one list, server changes, more than one
  custom URL source.

## Test plan
New `test/region_picker_test.dart` (AC1 to AC5, AC8, AC11) and
`test/settings_event_sources_test.dart` (AC6, AC7, AC9) using mock shared preferences,
temp storage and the helpers in `test/support/event_sources.dart`. Preview: open
Settings, add two regions and the custom source, reorder, remove one, restart (reload)
and check the list and the events page.

## UI notes
Use Material 3 components: full-screen picker with a `SearchBar` or search `TextField` in
the app bar, `CheckboxListTile` rows under category headers, a `ReorderableListView` for
the configured list. Risk is medium: this edits persisted settings and deletes a cache
file on removal, but does not touch check-in rules, codes or ride state. Size M because
the picker is one new page plus a small change to `EventSources`.
