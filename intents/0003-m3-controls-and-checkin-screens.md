---
id: "0003"
title: Apply Material 3 tokens, status colors and button hierarchy to the controls and check-in screens
requested_by: rbrancher
issue: 2
final_slice: false
priority: medium
size: M
risk: medium
touches:
  - lib/day_night.dart
  - lib/controls_view_page.dart
  - lib/control_card.dart
  - lib/checkin_progress.dart
  - lib/checkin_rider_details.dart
  - lib/checkin_status_page.dart
  - lib/checkin_status_rider.dart
  - lib/map_icon_button.dart
  - test/style_guardrail_test.dart
  - test/controls_screen_test.dart
---

## Problem
Slices (a) and (b) added `AppTokens` and themed the event list. The riding screens still
bypass the theme. `controls_view_page.dart`, `control_card.dart`, `checkin_progress.dart`,
`checkin_rider_details.dart`, `checkin_status_page.dart`, `checkin_status_rider.dart` and
`map_icon_button.dart` use `Colors.green/orange/red/blueGrey/grey/blue`, a literal
`fontSize:`, `ElevatedButton` for every action (CHECK IN does not stand out from GPS Update
and Resend Checkins) and `FlushbarGlobal` toasts. The status colors and `numeric` text
style defined in `AppTokens` are not used anywhere. This is slice (c) of (a) to (d). It is
visual only.

## User story
As a rider on the road, I want the control list to show each control's state in themed
status colors, with times and distances that read at a glance and an obvious CHECK IN
button, so that I can see my next action in sun or at night.

## Acceptance criteria
- [x] AC1: The seven files listed in Problem contain no `Colors.` (except
      `Colors.transparent`), `Color(0x`, `fontSize:` or `Flushbar`. Their entries are
      removed from the `baseline` map in `test/style_guardrail_test.dart`, so the guardrail
      enforces this. No other baseline count is raised. `time_till.dart` and
      `checkin_status_timed.dart` have no violations today and must stay clean.
- [x] AC2: Control state icons and indicators use the `AppTokens` status pairs: checked in
      uses the checked-in pair, an open control uses on time (or closing soon when the
      existing logic already says it is closing soon), a closed or missed control uses the
      closed pair, and DNF uses the DNF pair. The mapping from existing control state to
      token is one small function covered by a unit test for each state. No new rule decides
      which state a control is in.
- [x] AC3: Times and distances on the control card (open, close, distance to control) use
      `AppTokens.numeric`. The progress indicator in `checkin_progress.dart` takes its colors
      from the theme and its label size from `textTheme`. A widget test checks the rendered
      style of a control's close time has the tabular figures font feature.
- [x] AC4: Each of the controls screen and the check-in status screen has at most one
      `FilledButton`. On the controls screen it is CHECK IN, on the one control that is
      available. When no control is available, it has none. GPS Update and Resend Checkins
      use `FilledButton.tonal` or `OutlinedButton`, and dialog cancel and dismiss actions use
      `TextButton`. Widget tests count `FilledButton`s with events from the mock feed.
- [x] AC5: `FlushbarGlobal.show` calls in `controls_view_page.dart` and `control_card.dart`
      move to `AppSnack.show` from slice (b). The messages and their trigger conditions are
      unchanged. A widget test shows a `SnackBar` with the GPS update message after the GPS
      Update button is tapped in mock mode.
- [x] AC6: Check-in logic is unchanged. The proximity radius, open/close window, skip
      rules, comment dialog, late flag, start/finish codes, persisted ride state and report
      posting are not edited. `git diff` for this slice touches only widget build code,
      styles and the toast calls. A regression test pumps the controls screen for an
      activated mock event whose start control is open. `kMockMode` is false under
      `flutter test`, so the test sets `RiderLocation.riderLocation = MockLocation.position`
      and `lastLocationUpdate` directly, and wraps the test in
      `http.runWithClient(..., MockServer.client)`. Tapping CHECK IN must leave exactly one
      check-in recorded for that control index on the `ActivatedEvent`, and
      `MockServer.receivedReports` must contain exactly one report with that
      `control_index`.
- [x] AC7: A widget test pumps the controls screen for an activated mock event in light and
      dark with `textContrastGuideline` and `androidTapTargetGuideline`, and both pass for
      the cards and buttons on this screen.
- [x] AC8: The map icon in `map_icon_button.dart` uses `colorScheme.primary`.
- [x] AC9: `FilledButton.tonal` works. Slice (a)'s `filledButtonTheme` in `day_night.dart`
      forces `backgroundColor: primary` on every `FilledButton`, which makes tonal buttons
      look the same as primary ones. Remove that color override and keep only shape,
      padding and text style; M3's defaults already give `FilledButton` the `primary`
      color and `FilledButton.tonal` the `secondaryContainer` color. A widget test checks
      that a `FilledButton` renders with `primary` and a `FilledButton.tonal` with
      `secondaryContainer`, in light and dark. The slice (b) test that RIDE renders with
      `primary` still passes.

## Out of scope
- Slice (d), the final slice: settings, dialogs on other screens, certificate, log, the
  past events page and the remaining screens, removal of `FlushbarGlobal` and the `Flushbar`
  baseline in `snackbarglobal.dart`, and the NavigationBar/NavigationDrawer evaluation.
- Golden tests. The widget guideline tests in AC7 stand in for now.
- Any change to check-in rules, distance or time windows, codes, persisted state or
  reporting.
- Layout, wording and ordering changes.

## Test plan
- New `test/controls_screen_test.dart` covers AC2 to AC7. It uses the mock feed, fixed-time
  events from `test/support/fixtures.dart`, `MockLocation` and `MockServer.receivedReports`.
- `test/style_guardrail_test.dart` baseline edits cover AC1.
- Run `flutter analyze` and `flutter test`. In the mock-mode web preview, start a ride and
  open the controls screen in light and dark. CHECK IN should be the only filled button and
  the status icons should be legible.

## UI notes
Only colors, text styles, button emphasis and the toast widget change. Because
`control_card.dart` holds the check-in handler, reviewers should check the diff leaves
that code alone. That is why risk is medium, not low.
