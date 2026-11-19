---
id: "0005"
title: Apply Material 3 tokens to settings, certificate, log, past events and side menu
status: approved
requested_by: rbrancher
issue: 2
final_slice: true
priority: medium
size: M
risk: low
touches:
  - lib/app_tokens.dart
  - lib/app_settings.dart
  - lib/day_night.dart
  - lib/settings_page.dart
  - lib/settings_tiles.dart
  - lib/cert_page.dart
  - lib/confetti_dialog.dart
  - lib/log_page.dart
  - lib/my_activated_events_page.dart
  - lib/side_menu.dart
  - lib/control_card.dart
  - test/style_guardrail_test.dart
  - test/remaining_screens_test.dart
---

## Problem
Slices (a) to (d1) added `AppTokens`, themed the event list, the controls and check-in
screens, and replaced Flushbar with `AppSnack`. The last screens still bypass the theme:
- `cert_page.dart` (9 guardrail violations: `Colors.blueAccent/blue/red/yellow/green`, literal
  `fontSize`) and `confetti_dialog.dart`
- `settings_page.dart` and `settings_tiles.dart`, where every action is an `ElevatedButton`
  (three in `settings_page.dart`, plus Continue on line 421)
- `my_activated_events_page.dart` and `log_page.dart`
- `app_settings.dart`, whose default theme seed is `Colors.blue` (1 violation)
- `side_menu.dart`, a classic `Drawer`

Two follow-ups from slice (c) are still open: check-ins pending upload used to be orange
and now have no distinct status color, and card detail lines have no small numeric text
token. This is slice (d2), the final slice. It is visual only.

## User story
As a rider, I want the settings, certificate, log and past rides screens to look and behave
like the rest of the app in light and dark mode, so that the whole app feels consistent and
my finish certificate is easy to read and share.

## Acceptance criteria
- [ ] AC1: `cert_page.dart`, `confetti_dialog.dart`, `settings_page.dart`,
      `settings_tiles.dart`, `log_page.dart`, `my_activated_events_page.dart`, `side_menu.dart`
      and `app_settings.dart` contain no `Colors.` (except `Colors.transparent`), `Color(0x`,
      `fontSize:` or `Flushbar`. The `baseline` map in `test/style_guardrail_test.dart` is
      emptied (`{}`) and the guardrail enforces zero for all of `lib/` outside the exempt
      files. The default theme seed becomes a named constant in `app_tokens.dart` with the
      same blue value, so the default look and any saved theme color do not change.
- [ ] AC2: The certificate page takes colors from `colorScheme` and `AppTokens`, and text
      sizes from `textTheme`. The finish code uses `AppTokens.numeric` so its characters line
      up. The finish code text, certificate text and every displayed value are unchanged. A
      widget test pumps the certificate for a finished mock event in light and dark and
      finds the finish code string, with `textContrastGuideline` passing.
- [ ] AC3: Confetti uses theme colors (primary, secondary, tertiary, and a status token)
      instead of fixed blue, red, yellow and green. A widget test pumps the dialog without
      error in light and dark.
- [ ] AC4: The settings page and the Continue dialog have at most one `FilledButton` per
      screen (the confirming action). Other actions use `FilledButton.tonal`,
      `OutlinedButton` or `TextButton`. No `ElevatedButton` remains in `lib/`. A widget test
      counts `FilledButton`s and `ElevatedButton`s on the settings page in light and dark.
- [ ] AC5: Settings, past events and log pages pass `textContrastGuideline` and
      `androidTapTargetGuideline` in light and dark in a widget test using mock data.
- [ ] AC6: `AppTokens` gains a distinct "pending upload" status pair (`pending`,
      `onPending`) for both brightnesses, built like the other custom colors from a fixed
      orange source hue in `app_tokens.dart` (the old indicator was orange). Because the
      control card draws it as an icon on the card surface, `pending` must reach at least
      3:1 contrast against `surface` (WCAG non-text contrast), and `onPending` at least 4.5:1
      against `pending`. It must differ visibly from `checkedIn` and `closingSoon`. The
      control card shows it for a check-in that is recorded but not yet posted, using the
      existing "is it posted" flag, with no new logic. A unit test covers the contrast
      requirements in both brightnesses for the default seed and two others, and a widget
      test shows the pending color on a control with an unposted check-in.
- [ ] AC7: `AppTokens` gains a smaller numeric text style (same tabular figures feature)
      used by control card detail lines. A unit test checks the feature and size ordering
      against `numeric`.
- [ ] AC8: The side menu is evaluated and kept as `Drawer` or moved to `NavigationDrawer`.
      The choice and the reasoning go in a short comment at the top of `side_menu.dart`
      and in the PR description. If the `Drawer` is kept, its header, spacing and text use
      theme values only. Either way every menu entry keeps its label, order and destination,
      and a widget test opens the drawer and finds each entry.
- [ ] AC9: No behavior changes. Check-in rules, distance or time windows, codes, persisted
      state, settings keys and values, and reporting are not edited. The only logic
      touched in `control_card.dart` is reading the existing posted flag for AC6 and the
      text style for AC7. The check-in regression test in `test/controls_screen_test.dart`
      and the `AppSnack` tests still pass unchanged.

## Out of scope
- This is the final slice, so nothing remains to follow.
- Golden tests.
- Layout, wording and ordering changes (except the optional `NavigationDrawer` swap in AC8).
- Any change to check-in rules, codes, persisted state or reporting.
- New dependencies.

## Test plan
- New `test/remaining_screens_test.dart` covers AC2 to AC8 using fixed-time fixtures from
  `test/support/fixtures.dart`, mock location, and the mock feed.
- `test/style_guardrail_test.dart` covers AC1 (empty baseline).
- Run `flutter analyze` and `flutter test`. In the mock-mode web preview, open Settings,
  Past rides, Log and a finished ride's certificate in light and dark, and open the side
  menu.

## UI notes
Visual only. Reviewers should check the `control_card.dart` diff contains only the
pending color and text style lines. Risk is low because it touches no rule, code or
persisted state files, and the finish code text is only restyled.
