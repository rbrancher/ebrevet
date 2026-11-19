---
id: "0004"
title: Retire Flushbar - move every toast to AppSnack (M3 SnackBar)
status: approved
requested_by: rbrancher
issue: 2
final_slice: false
priority: medium
size: M
risk: medium
touches:
  - lib/snackbarglobal.dart
  - lib/main.dart
  - lib/activated_event.dart
  - lib/checkin.dart
  - lib/control.dart
  - lib/region.dart
  - lib/report.dart
  - lib/scheduled_events.dart
  - lib/log_page.dart
  - lib/screen_shot.dart
  - pubspec.yaml
  - pubspec.lock
  - test/style_guardrail_test.dart
  - test/app_snack_test.dart
---

## Problem
Slices (a) to (c) added `AppSnack` (M3 `SnackBar`s through a global `scaffoldMessengerKey`)
and moved the event list, controls and check-in screens to it. Every other message still
goes through the legacy `FlushbarGlobal` overlay (`another_flushbar`):
- `activated_event.dart` (4 calls), `report.dart` (4), `region.dart` (2), `checkin.dart`,
  `control.dart`, `scheduled_events.dart`, `log_page.dart`, `screen_shot.dart` (1 each)
- the overlay implementation in `snackbarglobal.dart` (42 guardrail violations)
- `main.dart`, which passes `FlushbarGlobal.navigatorKey` to `MaterialApp` and has a TODO
  about Flushbar

So the app shows two different toast styles. This slice (d1) removes Flushbar completely.
Issue #2's original slice (d) was split in two. The remaining screens follow as the final
slice (d2).

## User story
As a rider, I want every message the app shows to look and behave the same way, in light
and dark mode, so that I always recognise and can read what the app is telling me.

## Acceptance criteria
- [ ] AC1: Every `FlushbarGlobal.show(...)` call becomes `AppSnack.show(...)` and every
      `FlushbarStyle.x` becomes `AppSnackStyle.x`. The message expressions, the trigger
      conditions and the chosen style are unchanged. `AppSnackStyle` gains any style value
      that is used today and missing from it.
- [ ] AC2: In `activated_event.dart`, `checkin.dart`, `control.dart`, `region.dart`,
      `report.dart` and `scheduled_events.dart`, the diff contains only the toast calls and
      their imports. Proximity, open/close windows, codes, persisted ride state, region
      handling and report posting are not edited. The check-in regression test in
      `test/controls_screen_test.dart` still passes unchanged.
- [ ] AC3: `FlushbarGlobal`, `FlushbarStyle` and the rest of the overlay code are deleted
      from `snackbarglobal.dart`, and nothing imports `another_flushbar`. The
      `another_flushbar` dependency is removed from `pubspec.yaml` (and `pubspec.lock`).
      If `MaterialApp` still needs a `navigatorKey` for anything other than Flushbar, it
      keeps one under a neutral name; otherwise it is removed. The Flushbar TODO in
      `main.dart` is removed.
- [ ] AC4: The baseline entries for `snackbarglobal.dart`, `activated_event.dart`,
      `checkin.dart`, `control.dart`, `region.dart`, `report.dart`, `scheduled_events.dart`,
      `log_page.dart`, `screen_shot.dart` and `main.dart` are removed from
      `test/style_guardrail_test.dart`, so these files must have zero violations. No other
      baseline count is raised. A new guardrail test fails if any file under `lib/`
      contains `Flushbar` (no baseline, no exemptions).
- [ ] AC5: `test/app_snack_test.dart` shows a `SnackBar` through `AppSnack.show` for every
      `AppSnackStyle` value, in light and dark, with no `BuildContext` passed in. The error
      style uses `error`/`onError`. Calling `AppSnack.show` before the app has a
      `ScaffoldMessenger` (for example from startup code) does not throw. It logs the
      message instead.
- [ ] AC6: Messages raised from non-widget code still appear: a test calls
      `AppSnack.show` from outside any widget (as `report.dart` does) while the app is
      pumped, and the `SnackBar` with the message text is found.

## Out of scope
- Slice (d2), the final slice: settings page and tiles, certificate page and confetti,
  log page and past events page layout, side menu evaluation (`Drawer` vs
  `NavigationDrawer`), the default seed color in `app_settings.dart`, and the remaining
  `ElevatedButton`s. Also the follow-ups from slice (c): a distinct status color for
  check-ins pending upload (they used to be orange) and a smaller numeric text token for
  card detail lines.
- Golden tests.
- Any change to check-in rules, distance or time windows, codes, persisted state or
  reporting.
- Changing message wording.

## Test plan
- New `test/app_snack_test.dart` covers AC5 and AC6.
- `test/style_guardrail_test.dart` baseline edits and the new no-Flushbar test cover AC4.
- The existing check-in regression test covers AC2.
- Run `flutter analyze` and `flutter test`. In the web preview, tap "Update event data"
  and Resend Checkins and confirm the toasts are M3 SnackBars in light and dark.

## UI notes
Visual only: toasts move from a top overlay to the standard bottom SnackBar used since
slice (b). Reviewers should check the logic files' diffs contain only toast lines.
