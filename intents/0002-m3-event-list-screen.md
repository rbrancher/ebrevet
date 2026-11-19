---
id: "0002"
title: Apply Material 3 tokens and button hierarchy to the event list screen
status: done
requested_by: rbrancher
issue: 2
final_slice: false
priority: medium
size: M
risk: low
touches:
  - lib/main.dart
  - lib/event_list_page.dart
  - lib/event_card.dart
  - lib/event_header_card.dart
  - lib/snackbarglobal.dart
  - test/style_guardrail_test.dart
  - test/event_list_screen_test.dart
---

## Problem
Slice (a) (intent 0001) added `AppTokens`, themed buttons/snackbars and a guardrail, but no
screen uses them yet. The event list (`event_list_page.dart`, `event_card.dart`,
`event_header_card.dart`) still has hard-coded `fontSize:` and `Colors.blueAccent`, uses
`ElevatedButton` for every action (RIDE does not stand out from secondary actions) and
shows toasts through `Flushbar`. Issue #2 asks for this screen to follow the theme. This
is slice (b) of (a) to (d).

## User story
As a rider, I want the event list to use the app theme, with an obvious primary RIDE
action, so that I can read it in sun or at night and see the next step at once.

## Acceptance criteria
- [x] AC1: `event_list_page.dart`, `event_card.dart` and `event_header_card.dart` contain
      no `Colors.` (except `Colors.transparent`), `Color(0x`, `fontSize:` or `Flushbar`.
      Their entries are removed from the `baseline` map in `test/style_guardrail_test.dart`,
      so the guardrail test enforces this. No other baseline count is raised.
- [x] AC2: Text that used literal sizes uses `textTheme` roles. The event title uses
      `titleMedium` and the header card uses `titleLarge` and `bodyLarge`. A widget test
      checks the rendered title style matches the theme role.
- [x] AC3: The event website icon uses `colorScheme.primary` rather than `blueAccent`.
- [x] AC4: Each event card shows at most one `FilledButton`, the RIDE (or PRE-RIDE when
      that is the start style) action. Other actions on the list screen and its dialogs use
      `FilledButton.tonal` or `OutlinedButton` (secondary) or `TextButton` (tertiary).
      Widget tests with the mock feed check that a card has exactly one `FilledButton` and
      that its label is the start action.
- [x] AC5: Add a global `scaffoldMessengerKey` to `MaterialApp` in `lib/main.dart`, and a
      helper `AppSnack.show(message, {style})` in `lib/snackbarglobal.dart` that shows M3
      `SnackBar`s through it. The error style uses `error`/`onError`; other styles use theme
      roles or `AppTokens`. Migrate only the calls in `event_list_page.dart`,
      `event_card.dart` and `event_header_card.dart`. `FlushbarGlobal` stays for the other
      screens until their slices. A widget test shows a `SnackBar` with the message text.
- [x] AC6: Check-in, start-code, ride-start logic and the messages shown are unchanged.
      Only the widget that displays them changes. Existing tests pass.
- [x] AC7: A widget test pumps the event list in mock mode in light and dark with
      `textContrastGuideline` and `androidTapTargetGuideline`, and both pass for the cards
      and buttons on this screen.

## Out of scope
- Slice (c): controls and check-in screens (`controls_view_page.dart`, `control_card.dart`,
  `checkin_*`, `time_till.dart`). Use of the status colors and `numeric` style on screens
  belongs there.
- Slice (d), the final slice: settings, dialogs on other screens, certificate, log and
  the remaining screens, removal of `FlushbarGlobal` and the `Flushbar` baseline in
  `snackbarglobal.dart`, and the NavigationBar/NavigationDrawer evaluation.
- Golden tests. The widget guideline tests in AC7 stand in for now.
- Any change to check-in rules, codes, persisted state or reporting.

## Test plan
- New `test/event_list_screen_test.dart` covers AC2 to AC5 and AC7 using the mock feed
  and fixed-time events from `test/support/fixtures.dart`.
- `test/style_guardrail_test.dart` baseline edits cover AC1.
- Run `flutter analyze` and `flutter test`. In the mock-mode web preview, check the event
  list in light and dark: RIDE is the only filled button on each card and text is legible.

## UI notes
Only theme-level styling and button emphasis change. Layout, wording and order stay the same.
