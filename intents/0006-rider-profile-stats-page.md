---
id: "0006"
title: Read-only rider profile page with ride stats, opened from the app bar
status: approved
requested_by: rbrancher
issue: 17
final_slice: false
priority: medium
size: M
risk: low
touches:
  - lib/profile_stats.dart
  - lib/profile_page.dart
  - lib/event_list_page.dart
  - lib/side_menu.dart
  - lib/mock/mock_server.dart
  - lib/main.dart
  - test/profile_stats_test.dart
  - test/profile_page_test.dart
---

## Problem
A rider's name and Rider ID are buried in a collapsed "Rider Settings" section in Settings,
reachable only through the drawer. The app already stores past rides and outcomes on the
device (My Rides), but nowhere summarises them: finished brevets, kilometres ridden, or which
distances have been completed.

## User story
As a rider, I want a read-only Profile page one tap away in the app bar, showing my identity
and a summary of my finished rides, so that I can see who the app thinks I am and what I have
ridden.

## Acceptance criteria
This is slice (a). The stats model is a pure function over `ActivatedEvent`s. No check-in
rule, code or persisted state is edited.

- [ ] AC1: A pure `ProfileStats` calculation (new `lib/profile_stats.dart`) takes a list of
      `ActivatedEvent` and a rider ID, and returns total finished rides, total km (sum of
      `event.distance`), longest ride km, and a count per distance bucket. A unit test covers
      each rule below.
- [ ] AC2: Only rides with `isFinished` (outcome `finish`) count. `active`, `dnf`, `dns`,
      all `dnq*` and `unknown` outcomes do not.
- [ ] AC3: Only rides whose `riderID` equals the current Rider ID count (compared after
      trimming). Rides under another ID are ignored.
- [ ] AC4: Finished pre-rides (`StartStyle.preRide`) count as rides, like any other start style.
- [ ] AC5: Distance buckets are Populaire (under 200), 200, 300, 400, 600, 1000 and 1200+.
      Bucketing is by official `event.distance`, with each standard distance covering the range
      from itself up to (not including) the next one. Unit tests cover 199 -> Populaire,
      200 -> 200, 299 -> 200, 300 -> 300, 999 -> 600, 1000 -> 1000, 1199 -> 1000,
      1200 -> 1200+ and 1400 -> 1200+.
- [ ] AC6: Empty history, or no finished rides for the current ID, yields an "isEmpty"
      result and the page shows a friendly empty state instead of zeros.
- [ ] AC7: The Profile page (`lib/profile_page.dart`) is read-only, with no edit icon or
      dialog. It has a medium or large top app bar, a header with an initials avatar, the full
      name as the most prominent text and the Rider ID, a stats card group (rides, total km,
      longest ride) using `AppTokens.numeric`, and a "Distances completed" section listing all
      seven buckets. Completed buckets show their count. Buckets with none read "Not yet".
      A widget test pumps the page with fixture rides and finds these values, in light and dark,
      with `textContrastGuideline` and `androidTapTargetGuideline` passing.
- [ ] AC8: The page states plainly that stats come from rides saved on this phone and that
      history is pruned after the "keep past events" months setting, so they are not lifetime
      totals. A widget test finds this text.
- [ ] AC9: The page has a link that opens the existing My Rides page.
- [ ] AC10: The top-level event list app bar gets a profile action as its last (rightmost)
      action, after the day/night toggle. It shows an initials avatar, or a generic account icon
      if no name is set, has a "Profile" tooltip and semantic label, and a 48 dp touch target.
      Tapping it opens the Profile page. A widget test covers both avatar variants, the order
      relative to the day/night toggle, and navigation.
- [ ] AC11: The rider line in the drawer header opens the Profile page. A widget test taps it.
- [ ] AC12: In mock mode, a few finished mock rides for the demo rider ID covering 2-3
      distances, plus one DNF, are available so the preview shows non-zero totals and a
      partly filled distance list. They are added only in mock mode through the existing mock
      seams. Native and production builds are unaffected, and tests use fixtures from
      `test/support`.
- [ ] AC13: Styling uses theme color roles, `AppTokens` and `textTheme` only. The baseline
      in `test/style_guardrail_test.dart` stays empty and the guardrail passes.
- [ ] AC14: No behaviour change elsewhere. `flutter analyze` and `flutter test` stay green.

## Out of scope
Slice (b), the final slice, in order:
- Full-screen rider edit form (first name, last name, Rider ID) reached from an Edit action on
  the Profile page, with inline validation using the existing validators, Save / Cancel and a
  discard-changes prompt.
- Reusing that form for the first-run "Required Settings" screen.
- Keeping the developer-options side effect when the Rider ID changes, and a warning that
  start codes depend on the ID and that rides under the old ID won't count.
- Removing the rider fields from Settings.
- Saved name updating the profile header, app bar avatar and drawer header.

Not planned for either slice:
- RUSA awards (Super Randonneur, R-12), fetching lifetime results from RUSA, profile photos.
- Any change to check-in rules, codes, persisted ride state or reporting.
- New dependencies.

## Test plan
- New `test/profile_stats_test.dart`: unit tests for AC1-AC6.
- New `test/profile_page_test.dart`: widget tests for AC7-AC11 using fixtures in
  `test/support/fixtures.dart`.
- Preview (mock mode): the avatar sits at the right end of the event list app bar and opens
  Profile. The demo rider's name and ID show with no edit controls. Stats are non-zero and the
  DNF is not counted. The My Rides link works. Check light and dark.

## UI notes
Use M3 components: a medium or large top app bar, `Card`s for the stat group, section
headers, and `ListTile`s for the distance list. Risk is low: it only reads persisted rides
and does not touch check-in rules, codes or stored state. Mock seeding (AC12) must not leak
into production.
