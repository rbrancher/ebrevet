---
id: "0015"
title: Multiple event sources with separate caches and migration (slice a of b)
requested_by: rbrancher
issue: 44
final_slice: false
priority: medium
size: L
risk: high
touches:
  - lib/scheduled_events.dart
  - lib/app_settings.dart
  - lib/my_settings.dart
  - lib/event_list_page.dart
  - lib/event_card.dart
  - lib/settings_page.dart
  - lib/main.dart
  - lib/mock/mock_server.dart
  - test/scheduled_events_sources_test.dart
  - test/scheduled_events_migration_test.dart
  - test/mock_server_test.dart
---

## Problem
The app holds one event source at a time (`AppSettings.scheduleEventsSourceID` plus
`AppSettings.regionID`), one in-memory list (`ScheduledEvents.events`) and one cache file
that `ScheduledEvents.clear()` wipes on every source change. A rider who follows several
regions loses the other regions' cached events when switching, which hurts offline on a
ride. Issue #44 asks for several configured regions with a segmented switcher. This is
slice (a): the data model only. The settings multi-select and the switcher are slice (b).

## User story
As a rider, I want the app to keep each configured event source and its cached events
separately so that I can look at another region later without losing the first one's data.

## Acceptance criteria
- [x] AC1: Source list. A new persisted, ordered list of configured sources, each being an
      International region, a US region or the custom URL source (a region entry holds its
      region ID and category; the custom entry uses the existing custom URL and secret
      settings). Duplicates are not allowed. Stored through `MySetting`/shared
      preferences as JSON. Unreadable or invalid stored data gives the default list and
      never throws. Unit tests: round trip, order kept, duplicate rejected, garbage input.
- [x] AC2: Migration. With the new list absent, the list is built from the old
      `scheduleEventsSourceID` and `regionID` settings as exactly one entry. With none of
      the old settings set (fresh install) it is the default region (938017, PA Rando). A
      custom-URL install migrates to the single custom entry. Migration runs once, does not
      overwrite an existing list, and leaves the old settings keys untouched. Tests for each
      case, including an install with a region ID no longer in `Region.regionMap`.
- [x] AC3: Selected source. The selected source is persisted and survives restart. If it is
      missing from the list (removed), the first source is used. An empty list falls back
      to the default region. Tests.
- [x] AC4: Separate caches. Each source has its own in-memory event list, last-refreshed
      time and cache file (named from a stable source key). Refreshing or selecting one
      source never clears or changes another's cache. `SourceSelection.updateFromSettings()`
      and Settings no longer wipe other sources' data. Regression test: load A, load B,
      A's events and last-refreshed are unchanged.
- [x] AC5: Legacy cache. The existing single `scheduled_events` cache file is adopted as the
      cache of the migrated first source (read once, then kept under the new name), so a
      rider upgrading offline still sees their events. It is not adopted if its recorded
      `event_info_source` does not match that source. Test both.
- [x] AC6: Per-source refresh and verification. Refreshing fetches only the given source,
      using that source's URL and secret (region secret for regions, custom secret for
      custom), with the existing nonce and HMAC checks. A signature made with another
      source's secret is rejected and leaves that source's cache untouched. Tests use a
      fake fetch, never the network.
- [x] AC7: Cross-source lookup. A lookup by event ID resolves across every configured
      source's cache, independent of the selected one. Activated events, My Rides, check-in
      and start-code checks behave the same as before (their saved state is unchanged and
      does not depend on which source is selected). Test: an event from B resolves while A
      is selected; saved ride JSON keys are unchanged.
- [x] AC8: A removed or unknown region. A configured region ID that no longer exists in
      `Region.regionMap` stays in the list, shows the existing "unknown region" style
      message where Settings shows it today, and never crashes the list page or refresh.
      Test.
- [x] AC9: No visible change. The existing Settings screen and event list behave as today for
      a single source: the event list shows the selected source's events and its refreshed
      time, and "Update event data" refreshes only the selected source. Existing widget
      tests keep passing.
- [x] AC10: Mock mode. `MockServer` serves a distinct sample feed for at least two region
      IDs (different event names/IDs per region, correctly signed for that region's
      secret as today); unknown regions get the current feed. `mock_server_test.dart` shows
      two regions return different events. Tests never hit the network.
- [x] AC11: No change to check-in rules, codes (`signature.dart`), the saved ride format or
      server reporting. `flutter analyze`, `flutter test` and `dart format` are green.

## Out of scope
Slices of issue #44, in order:
- Slice (b): Settings multi-select (searchable full-screen picker grouped by country or
  state using `Region.compareByStateName`, a "3 regions" summary row, reorder and remove,
  custom source selectable together with regions) and the Material 3 segmented region
  switcher at the top of `event_list_page.dart` (hidden for one region, instant switching,
  a scrollable fallback that works at 390 dp with about 5 regions, last selection
  remembered, behaviour documented). Slice (b) sets `final_slice: true`.
- Not in any slice: merging all regions into one list, server changes, more than one custom
  URL source (nice-to-have; decide in slice b).

## Test plan
New `test/scheduled_events_sources_test.dart` (AC1 to AC4, AC6 to AC8) and
`test/scheduled_events_migration_test.dart` (AC2, AC5) using mock shared preferences and
temp storage; extend `test/mock_server_test.dart` (AC10). Preview: nothing visibly changes
(AC9); check the default region still loads and refreshes.

## UI notes
No UI additions in this slice. Because the change touches persisted settings and the cache,
treat migration and cache separation as the highest-risk parts and keep the old setting
keys in place so a downgrade or rollback still works.
