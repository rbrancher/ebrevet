// Style guardrail (intent 0001): stops new hard-coded colors, font sizes and
// Flushbar toasts from being added to lib/. Use theme color roles,
// `AppTokens` and SnackBar instead.
//
// BASELINE counts may only go down. When you remove violations from a file,
// lower its count here (or delete the entry once it reaches zero). A PR that
// raises any count must explain why in its description.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Banned patterns. `Colors.transparent` is allowed.
final Map<String, RegExp> bannedPatterns = {
  'Colors.': RegExp(r'Colors\.(?!transparent\b)'),
  'Color(0x': RegExp(r'Color\(0x'),
  'fontSize:': RegExp(r'fontSize\s*:'),
  'Flushbar': RegExp(r'Flushbar'),
};

/// Files that may hold raw style values: the theme and the token set.
/// `region_data.dart` is gitignored (secrets) and differs per machine.
const Set<String> exemptFiles = {
  'lib/day_night.dart',
  'lib/app_tokens.dart',
  'lib/region_data.dart',
};

/// Violations present when the guardrail was added.
const Map<String, int> baseline = {
  'lib/activated_event.dart': 8,
  'lib/app_settings.dart': 1,
  'lib/cert_page.dart': 9,
  'lib/checkin.dart': 2,
  'lib/checkin_progress.dart': 6,
  'lib/checkin_rider_details.dart': 8,
  'lib/checkin_status_page.dart': 3,
  'lib/checkin_status_rider.dart': 3,
  'lib/control.dart': 2,
  'lib/control_card.dart': 9,
  'lib/controls_view_page.dart': 3,
  'lib/event_card.dart': 19,
  'lib/event_header_card.dart': 2,
  'lib/event_list_page.dart': 3,
  'lib/log_page.dart': 2,
  'lib/main.dart': 2,
  'lib/map_icon_button.dart': 1,
  'lib/my_activated_events_page.dart': 1,
  'lib/region.dart': 3,
  'lib/report.dart': 7,
  'lib/scheduled_events.dart': 2,
  'lib/screen_shot.dart': 2,
  'lib/settings_page.dart': 1,
  'lib/snackbarglobal.dart': 42,
};

/// Number of banned-pattern matches in [source].
int countViolations(String source) => bannedPatterns.values
    .fold(0, (n, re) => n + re.allMatches(source).length);

/// Checks [sources] (path -> contents) against [baseline]. Returns one
/// message per file whose count exceeds its baseline (0 if not listed).
List<String> checkSources(Map<String, String> sources,
    {Map<String, int> baseline = baseline,
    Set<String> exempt = exemptFiles}) {
  final failures = <String>[];
  for (final path in sources.keys.toList()..sort()) {
    if (exempt.contains(path)) continue;
    final count = countViolations(sources[path]!);
    final allowed = baseline[path] ?? 0;
    if (count > allowed) {
      final found = [
        for (final e in bannedPatterns.entries)
          if (e.value.hasMatch(sources[path]!)) e.key
      ];
      failures.add('$path: $count style violations, baseline $allowed '
          '(${found.join(', ')}). Use Theme color roles / AppTokens / '
          'SnackBar instead.');
    }
  }
  return failures;
}

Map<String, String> readLibSources() => {
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart'))
          f.path.replaceAll(r'\', '/'): f.readAsStringSync()
    };

void main() {
  // AC6 (intent 0001)
  test('lib/ adds no new hard-coded colors, font sizes or Flushbars', () {
    final failures = checkSources(readLibSources());
    expect(failures, isEmpty, reason: failures.join('\n'));
  });

  // AC6 (intent 0001): keep the baseline honest so counts only go down.
  test('baseline lists only existing, non-exempt files with violations', () {
    final sources = readLibSources();
    for (final e in baseline.entries) {
      expect(sources.containsKey(e.key), isTrue,
          reason: '${e.key} no longer exists; remove it from the baseline');
      expect(exemptFiles.contains(e.key), isFalse);
      expect(e.value, greaterThan(0));
    }
  });

  // AC7 (intent 0001)
  group('checkSources', () {
    const clean = '''
      Container(color: Theme.of(context).colorScheme.primary,
          child: Text('x', style: Theme.of(context).textTheme.bodyLarge));
      Container(color: Colors.transparent);
    ''';

    test('colorScheme roles only: passes', () {
      expect(countViolations(clean), 0);
      expect(checkSources({'lib/new_page.dart': clean}, baseline: {}),
          isEmpty);
    });

    test('hard-coded Colors.* is reported', () {
      final r = checkSources(
          {'lib/new_page.dart': '$clean Container(color: Colors.red);'},
          baseline: {});
      expect(r, hasLength(1));
      expect(r.single, contains('lib/new_page.dart'));
      expect(r.single, contains('Colors.'));
    });

    test('Color(0x...) is reported', () {
      final r = checkSources(
          {'lib/a.dart': 'const c = Color(0xFF123456);'}, baseline: {});
      expect(r.single, contains('Color(0x'));
    });

    test('fontSize: is reported', () {
      final r = checkSources(
          {'lib/a.dart': 'TextStyle(fontSize: 20)'}, baseline: {});
      expect(r.single, contains('fontSize:'));
    });

    test('Flushbar is reported', () {
      final r = checkSources(
          {'lib/a.dart': 'Flushbar(message: "hi").show(context);'},
          baseline: {});
      expect(r.single, contains('Flushbar'));
    });

    test('a file at its baseline passes, above it fails', () {
      const src = 'Colors.red; Colors.blue;';
      expect(checkSources({'lib/a.dart': src}, baseline: {'lib/a.dart': 2}),
          isEmpty);
      expect(
          checkSources({'lib/a.dart': '$src Colors.green;'},
              baseline: {'lib/a.dart': 2}),
          hasLength(1));
    });

    test('exempt files are skipped', () {
      expect(
          checkSources({'lib/app_tokens.dart': 'Color(0xFF2E7D32)'},
              baseline: {}),
          isEmpty);
    });
  });
}
