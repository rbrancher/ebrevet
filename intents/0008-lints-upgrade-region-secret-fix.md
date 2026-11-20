---
id: "0008"
title: Upgrade lints (flutter_lints 6, unawaited_futures, avoid_dynamic_calls) and fix the region-secret lookup
requested_by: rbrancher
issue: 26
final_slice: true
priority: medium
size: M
risk: high
touches:
  - pubspec.yaml
  - analysis_options.yaml
  - lib/region.dart
  - lib/activated_event.dart
  - lib/report.dart
  - lib/scheduled_events.dart
  - test/region_test.dart
---

## Problem
The analyzer runs on `flutter_lints ^2.0.0` (current is 6) and `analysis_options.yaml` adds no
rules, only commented-out overrides. Newer rules surface real issues that CI misses:
- `unawaited_futures` (11 places): saves to local storage and report uploads that nothing waits on, so a failure passes silently (e.g. `lib/activated_event.dart:160`, `lib/report.dart:53`, `lib/scheduled_events.dart:310`).
- `avoid_dynamic_calls` (25 places): calls on untyped JSON values while parsing event and ride data.
- `collection_methods_unrelated_type` at `lib/region.dart:85`: `RegionData.regionSecret[rid]` looks up a `String` region ID in a map the template types as `Map<int, String>`. The lookup can never match, so every region falls back to `defaultSecret`.

## User story
As a maintainer, I want a stricter static-analysis bar and a working per-region secret lookup so that silent failures and type bugs are caught in CI and regions with their own secret use it.

## Acceptance criteria
- [ ] AC1: `flutter_lints` is upgraded to 6.x in `pubspec.yaml`, and `flutter pub get` resolves. Do **not** change the `environment: sdk` constraint. Dart 3 already resolves `flutter_lints` 6 against `'>=2.18.6 <3.0.0'` (checked). Raising the lower bound to 3.7 or above would switch `dart format` to the tall style and reformat almost every file. `flutter analyze` reports no issues.
- [ ] AC2: `analysis_options.yaml` enables `unawaited_futures` and `avoid_dynamic_calls`, and the commented-out rule overrides are removed. `flutter analyze` is clean, with no `// ignore` comments added to get there.
- [ ] AC3: Each deliberately un-awaited future is wrapped in `unawaited(...)` with a short comment saying why. Each future that should be awaited is awaited, keeping the existing error handling.
- [ ] AC4: Findings from the new `flutter_lints` rules (mostly `strict_top_level_inference`) are fixed with type annotations and no behaviour change.
- [ ] AC5: `Region` looks up its secret by ACP club code. The key type is consistent between `lib/region.dart` and the commented `RegionData` template in that file. Unit test: with a region-secret map containing 938017, `Region(regionID: '938017')` uses that secret. A region missing from the map uses `defaultSecret`. The code compiles and runs against both an empty `Map<int, String>` (the CI stub) and the template. The test injects the map and default secret through a small seam, such as optional constructor parameters defaulting to `RegionData`, since `RegionData` is a const.
- [ ] AC6: `test/signature_test.dart` passes unchanged, including golden start code E32C. Start codes for the default secret do not change.
- [ ] AC7: `flutter test` passes and `dart format --set-exit-if-changed lib test` passes.
- [ ] AC8: The diff has no behaviour changes beyond the region-secret fix: no UI changes, no changes to check-in rules, and no changes to the saved ride state format.

## Out of scope
- Strict analyzer modes (`strict-casts`, `strict-inference`, `strict-raw-types`), which add about 200 findings and are planned for later.
- Style-only rules (quotes, trailing commas, import order).
- Any edit to `harness/ci/region_data.stub.dart` or other protected paths.

## Test plan
- Add `test/region_test.dart` covering AC5: a known club code, an unknown club code, and an empty map.
- Existing tests, including the signature and start-code tests, must pass unchanged.
- Run `flutter analyze`, `flutter test` and the format check. Nothing needs checking in the preview, since there are no UI changes.

## UI notes
None. Risk is `high` because the change touches server reporting, persisted ride-state saves (awaiting or `unawaited` on writes) and secret selection, which feeds code generation. Review each `unawaited_futures` fix for ordering changes. No SDK constraint bump is needed for `flutter_lints` 6 (see AC1).
