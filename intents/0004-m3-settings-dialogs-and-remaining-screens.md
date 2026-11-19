---
id: "0004"
title: Finish the Material 3 revamp on settings, dialogs, certificate and remaining screens, and retire Flushbar
status: draft
requested_by: rbrancher
issue: 2
final_slice: true
priority: medium
size: M
risk: medium
touches:
  - lib/snackbarglobal.dart
  - lib/main.dart
  - lib/app_settings.dart
  - lib/settings_page.dart
  - lib/settings_tiles.dart
  - lib/cert_page.dart
  - lib/confetti_dialog.dart
  - lib/log_page.dart
  - lib/my_activated_events_page.dart
  - lib/screen_shot.dart
  - lib/side_menu.dart
  - lib/scheduled_events.dart
  - lib/region.dart
  - lib/report.dart
  - lib/control.dart
  - lib/checkin.dart
  - lib/activated_event.dart
  - test/style_guardrail_test.dart
  - test/remaining_screens_test.dart
---

## Problem
Slices (a) to (c) added `AppTokens` and `AppSnack`, and themed the event list, controls and
check-in screens. The guardrail baseline still lists 14 files.
- Most violations are `FlushbarGlobal.show` / `FlushbarStyle` toast calls in non-UI files:
  `activated_event.dart`, `checkin.dart`, `control.dart`, `region.dart`, `report.dart`,
  `scheduled_events.dart`, `log_page.dart`, `screen_shot.dart`.
- 42 more are in the legacy overlay implementation in `snackbarglobal.dart`.
- `cert_page.dart` uses `Colors.blue/red/blueAccent/yellow/green` and literal `fontSize:`.
- `settings_page.dart` and `settings_tiles.dart` use `ElevatedButton`.
- `main.dart` and `app_settings.dart` have one stray reference each (the `navigatorKey` and
  the default seed color `Colors.blue`).
- `my_activated_events_page.dart` and `settings_page.dart` have commented-out `fontSize:`.

This is slice (d), the last one. It is visual only.

## User story
As a rider, I want every screen and message in the app to look and behave the same way in
light and dark mode, so that I can always find the main action and read what the app tells me.

## Acceptance criteria
- [ ] AC1: All 14 entries are removed from `baseline` in `test/style_guardrail_test.dart`
      and `baseline` is empty. `lib/` outside `day_night.dart`, `app_tokens.dart` and
      `region_data.dart` has no `Colors.` (except `Colors.transparent`), `Color(0x`,
      `fontSize:` or `Flushbar`. The default seed color is defined only in an exempt file,
      and stays configurable through the existing `themeColor` setting.
- [ ] AC2: Every `FlushbarGlobal.show` call becomes `AppSnack.show`, and every
      `FlushbarStyle.*` becomes `AppSnackStyle.*`. Messages, trigger conditions and styles
      are unchanged. `FlushbarGlobal`, `FlushbarStyle`, `FlushbarPosition`,
      `FlushBarTextSize`, the overlay queue and the `another_flushbar` import are deleted,
      and `main.dart` no longer uses `FlushbarGlobal.navigatorKey`. The `another_flushbar`
      dependency is removed from `pubspec.yaml`, since nothing imports it any more. A
      guardrail test fails if `lib/` mentions `Flushbar`.
- [ ] AC3: A widget test shows a `SnackBar` through `AppSnack.show` for the `comment`,
      `error` and `success` styles, in light and dark. Error uses `error` and `onError`.
      The test does not need a `Navigator` context.
- [ ] AC4: No `ElevatedButton` remains in `lib/`. `settings_page.dart`, `settings_tiles.dart`,
      `cert_page.dart`, `confetti_dialog.dart` and `my_activated_events_page.dart` each have
      at most one `FilledButton` as the primary action. Other actions use
      `FilledButton.tonal` or `OutlinedButton`, and dialog cancel and dismiss actions use
      `TextButton`. Widget tests count `FilledButton`s on the settings page and on the
      certificate page.
- [ ] AC5: The certificate page takes its text and accent colors from `colorScheme`,
      `textTheme` and `AppTokens`, and the finish code uses `AppTokens.numeric`. The confetti
      colors come from the color scheme. A widget test pumps the certificate page for a
      finished mock event and checks the finish-code style has tabular figures.
- [ ] AC6: The settings, certificate, log and past events pages pass
      `textContrastGuideline` and `androidTapTargetGuideline` in light and dark. A widget
      test covers each page.
- [ ] AC7: A unit test checks WCAG AA contrast (at least 4.5:1) for every `AppTokens`
      status foreground/background pair, for light and dark, for the default seed and at
      least two other seeds. If `test/app_tokens_test.dart` already covers this, it is
      extended to the default seed and the configured seed.
- [ ] AC8: The side menu is evaluated and the decision is recorded in a short comment at
      the top of `side_menu.dart`, with the reason for keeping `Drawer` or moving to
      `NavigationDrawer`. If the drawer is kept, its header, spacing and sizes use theme
      values only. If it moves, every existing menu destination stays reachable and a widget
      test taps each one. Either way no menu item is added or removed.
- [ ] AC9: Check-in logic is unchanged. In `checkin.dart`, `activated_event.dart`,
      `control.dart`, `report.dart`, `region.dart` and `scheduled_events.dart`, the diff
      contains only toast calls and their imports. Proximity, open/close windows, codes,
      persisted ride state and report posting are not edited. The check-in regression test
      in `test/controls_screen_test.dart` (one check-in recorded, one report in
      `MockServer.receivedReports`) still passes.
- [ ] AC10: In the mock-mode web preview, every screen reachable from the side menu looks
      consistent in light and dark, and shows toasts as Material 3 SnackBars.

## Out of scope
- Golden tests. The issue asks for them, but the widget guideline tests (AC6) stand in for
  all four slices. A separate follow-up issue can add goldens.
- Material 3 Expressive, custom fonts and an app icon redesign.
- Any change to check-in rules, distance or time windows, codes, persisted state or reporting.
- Layout, wording and ordering changes, and adding or removing menu items.
- Changing the day/night switching in `DayNight`.

## Test plan
- New `test/remaining_screens_test.dart` covers AC3 to AC6 and AC8, using fixed-time events
  from `test/support/fixtures.dart` and the mock feed. AC7 goes in `test/app_tokens_test.dart`.
- `test/style_guardrail_test.dart` baseline edits cover AC1 and the `Flushbar` check in AC2.
- Run `flutter analyze` and `flutter test`. In the web preview, open each menu entry, the
  certificate for a finished ride and a toast (for example Resend Checkins), in light and dark.

## UI notes
Visual only. Because the toast calls sit in `checkin.dart`, `activated_event.dart` and
`report.dart`, reviewers should check those diffs for toast-only changes. That is why risk
is medium, not low.
