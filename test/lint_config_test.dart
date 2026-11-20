// Guards the static-analysis bar from intent 0008. `flutter analyze` being
// clean is enforced by CI; these checks pin the configuration it runs with.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final options = File('analysis_options.yaml').readAsStringSync();

  // AC1 (intent 0008)
  test('flutter_lints is 6.x and the SDK constraint is unchanged', () {
    expect(pubspec, contains('flutter_lints: ^6.0.0'));
    expect(pubspec, contains("sdk: '>=2.18.6 <3.0.0'"));
  });

  // AC2 (intent 0008)
  test('unawaited_futures and avoid_dynamic_calls are enabled', () {
    expect(options, contains('include: package:flutter_lints/flutter.yaml'));
    expect(options, contains('unawaited_futures: true'));
    expect(options, contains('avoid_dynamic_calls: true'));
    expect(options, isNot(contains('#')),
        reason: 'commented-out rule overrides were removed');
  });

  // AC2, AC5 (intent 0008)
  test('the only new ignore in lib/ is the documented region-secret one', () {
    final ignores = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('region_data.dart')) continue;
      for (final line in f.readAsLinesSync()) {
        if (line.contains('// ignore')) ignores.add(line.trim());
      }
    }
    expect(
        ignores,
        unorderedEquals([
          '// ignore: collection_methods_unrelated_type', // region.dart, AC5
          'print("LOG: \$s"); // ignore: avoid_print', // mylogger.dart, pre-existing
        ]));
  });
}
