---
id: "0001"
title: Add Material 3 design tokens, themed components and a style guardrail
requested_by: rbrancher
issue: 2
final_slice: false
priority: medium
size: M
risk: low
touches:
  - lib/day_night.dart
  - lib/app_tokens.dart
  - lib/main.dart
  - test/app_tokens_test.dart
  - test/style_guardrail_test.dart
---

## Problem
Most screens bypass the Material 3 theme built in `day_night.dart`. `lib/` has 43
`Colors.*` / `Color(0x…)` uses, 14 literal `fontSize:` values, ad hoc spacing and
`Flushbar` toasts. Night mode has hard-to-read spots, and nothing stops new code from
adding more. Issue #2 asks for a full revamp. That is too large for one change, so this
intent covers **slice (a) only**: the tokens, the theme wiring and the guardrail, with no
visible layout change.

## User story
As a rider, I want the app's colors, type and spacing to come from one themed token set
so that later screens can be made legible in sun and at night without each one inventing
its own look.

## Acceptance criteria
- [x] AC1: A `ThemeExtension<AppTokens>` in `lib/app_tokens.dart` exposes spacing
      (at least small, medium and large), a corner radius, and status color pairs
      (color plus on-color) for on time, closing soon, closed, checked in and DNF.
- [x] AC2: Status colors follow the M3 custom-color pattern. Fixed source hues are allowed
      only in `lib/app_tokens.dart`: green for on time, amber for closing soon. Each is
      turned into a container/on-container pair with
      `ColorScheme.fromSeed(seedColor: source, brightness: …)` for the current brightness.
      Closed uses `error`/`onError`, checked in uses `primary`/`onPrimary`, and DNF uses
      `onSurfaceVariant` on `surface`. A unit test builds tokens for light and dark, each
      with several app seed colors including the default, and checks that every status
      pair has at least 4.5:1 contrast.
- [x] AC3: `DayNight.dayTheme` and `nightTheme` register `AppTokens` in `extensions`, and
      `Theme.of(context).extension<AppTokens>()` is non-null in the app. A widget test
      checks this in both modes.
- [x] AC4: The seed color remains configurable (the existing `DayNight.color` setter
      rebuilds the themes and tokens), and `toggleMode` still switches day and night.
      Tests cover both.
- [x] AC5: The theme sets `FilledButton`, `OutlinedButton` and `SnackBar` styles using
      tokens or color roles. The only `lib/` files changed are `day_night.dart`,
      `main.dart` (only if needed for wiring) and the new `app_tokens.dart`.
      `app_smoke_test.dart` still passes.
- [x] AC6: A guardrail test, `test/style_guardrail_test.dart`, scans `lib/` and fails on
      `Colors.` (except `Colors.transparent`), `Color(0x`, `fontSize:` and `Flushbar`.
      It exempts `lib/day_night.dart` and `lib/app_tokens.dart`.
      Today's violations are recorded in a per-file baseline list in the test. A file
      fails if its count exceeds its baseline, and a new file fails if it has any.
      Baseline counts may only go down. A PR that raises any baseline must say why in
      its description.
- [x] AC7: The guardrail's scanning function is unit tested against in-memory sample
      sources. A sample that adds a hard-coded color, a `fontSize:` or a `Flushbar` is
      reported, and a sample using only `colorScheme` roles passes.
- [x] AC8: `AppTokens` provides a `numeric` text style for times and distances. It is
      based on `textTheme.titleLarge` with `FontFeature.tabularFigures()`. A unit test
      checks the font feature is present in light and dark.

## Out of scope
- Slices (b) event list, (c) controls and check-in, (d) settings, dialogs and the other
  screens. These need follow-up intents.
- Removing existing `Colors.*` / `fontSize:` / `Flushbar` usages, using `numeric` or the
  status colors on screens, and swapping `ElevatedButton` for `FilledButton` on screens.
- Golden tests, `NavigationBar` / `NavigationDrawer` evaluation and tap-target guidelines.
  These belong with the per-screen slices.
- Wiring the guardrail into a CI workflow. `.github/` is protected, and `flutter test`
  already runs in CI.
- Any change to check-in rules, codes, persisted state or reporting.
- Material 3 Expressive, custom fonts and the app icon.

## Test plan
- New `test/app_tokens_test.dart` covers AC1 to AC4 and AC8 (contrast math, theme
  registration, seed color change, mode toggle, tabular figures).
- New `test/style_guardrail_test.dart` covers AC6 and AC7.
- Run `flutter analyze` and `flutter test`, including the existing smoke test.
- In the mock-mode web preview, the event list should look unchanged in light and dark.

## UI notes
No intended visual change, apart from the theme-level default styles for buttons and
snackbars. Status colors and the `numeric` style are defined here but not yet used by
the screens.
