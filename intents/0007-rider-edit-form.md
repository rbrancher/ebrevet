---
id: "0007"
title: Full-screen rider edit form, reused for first run, and rider fields removed from Settings
status: draft
requested_by: rbrancher
issue: 17
final_slice: true
priority: medium
size: M
risk: medium
touches:
  - lib/rider_edit_page.dart
  - lib/profile_page.dart
  - lib/settings_page.dart
  - lib/event_list_page.dart
  - test/rider_edit_page_test.dart
  - test/profile_page_test.dart
  - test/remaining_screens_test.dart
---

## Problem
Slice (a) (0006) added the read-only Profile page. Rider details (first name, last name,
Rider ID) can still only be changed through one `AlertDialog` per field, inside a collapsed
"Rider Settings" section of Settings, and the first-run "Required Settings" screen
(`RequiredAppSettings`) repeats the same dialog tiles. There are two ways to edit the same
data, and neither warns that the Rider ID drives start codes and the profile stats.

## User story
As a rider, I want to edit my name and Rider ID in one full-screen form opened from my
Profile, so that I can change all three fields at once and understand the consequences of
changing my Rider ID.

## Acceptance criteria
Rider ID is an input to start codes, so this slice changes only where and how the existing
settings are edited. Code generation, check-in rules and persisted ride state are not edited.

- [ ] AC1: A new full-screen `RiderEditPage` (`lib/rider_edit_page.dart`) has three text
      fields (First Name, Last Name, Rider ID) prefilled from `AppSettings`, with Save and
      Cancel actions (close icon plus Save in the app bar, per the Material full-screen
      dialog pattern). It is not an `AlertDialog`.
- [ ] AC2: Inline validation reuses the `AppSettings.firstName/lastName/rusaID` validators
      (`notEmptyValidator`, `numericIDValidator`). Errors show under the field, and Save with
      an invalid field writes nothing and stays on the page.
- [ ] AC3: Save writes all changed values via `MySetting.setValue` and pops. Cancel and
      back with no changes pop silently. Cancel or back with unsaved changes asks
      "Discard changes?" with Discard / Keep editing. Keep editing stays with edits intact.
- [ ] AC4: The Profile page has an Edit action in its app bar that opens `RiderEditPage`.
      After saving, the Profile header (name, initials, Rider ID) shows the new values,
      and so do the event list app bar avatar and drawer header when next shown. A widget
      test covers the header update.
- [ ] AC5: Developer-options behaviour on a Rider ID change matches today. If the saved ID
      differs from the stored one and is not `AppSettings.magicRUSAID`,
      `MySetting.clearDeveloperOptions()` runs. If it equals the magic ID, developer options
      stay available and a warning is logged. If the ID is unchanged, nothing is cleared.
      Tests cover all three.
- [ ] AC6: When the Rider ID field differs from the stored non-empty ID, the form shows a
      warning that start codes depend on the Rider ID and that rides under the old ID will
      not count in the profile stats. It is hidden when the ID is unchanged and on first run
      (stored ID empty). A test covers shown and hidden.
- [ ] AC7: The first-run "Required Settings" screen (`RequiredAppSettings(collapsed: false)`
      on the event list) uses the same form widget (shared body, no duplicated field or
      validation code) with a Continue/Save action. Saving calls `onContinue` and leaves the
      user on the event list with settings applied. Existing first-run behaviour in
      `test/remaining_screens_test.dart` is updated, not dropped.
- [ ] AC8: Settings no longer contains the "Rider Settings" section or any rider field
      tiles, and has no other way to edit them. A test asserts they are absent.
- [ ] AC9: Styling uses theme color roles, `AppTokens` and `textTheme` only. The
      `test/style_guardrail_test.dart` baseline stays empty. New form controls pass
      `androidTapTargetGuideline` and `textContrastGuideline` in light and dark.
- [ ] AC10: `flutter analyze` and `flutter test` stay green. Tests use no network and no
      real location.

## Out of scope
- RUSA awards, lifetime results from RUSA, profile photos.
- Any change to check-in rules, code generation, reporting or persisted ride state.
- Changing the validators themselves, or the stats rules from slice (a).
- New dependencies.

## Test plan
- New `test/rider_edit_page_test.dart`: AC1-AC3, AC5, AC6, AC9.
- Update `test/profile_page_test.dart` (AC4) and `test/remaining_screens_test.dart` (AC7, AC8).
- Preview (mock mode): Profile -> Edit opens the full-screen form. Invalid input shows inline
  errors. Changing the Rider ID shows the warning. Back with edits prompts to discard. Save
  updates the Profile header. Settings has no rider section.

## UI notes
Use `TextFormField`s in a shared `Form`, a `PopScope` for the discard prompt, and a tinted
`Card` for the Rider ID warning using theme color roles. Risk is medium rather than low only
because Rider ID feeds start codes. The ID-change side effects must be preserved exactly (AC5).
