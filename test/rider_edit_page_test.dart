// Full-screen rider edit form (intent 0007). No network or location is
// used: the form only reads and writes SharedPreferences (mocked).

import 'dart:io';

import 'package:ebrevet_card/app_settings.dart';
import 'package:ebrevet_card/control_state.dart';
import 'package:ebrevet_card/day_night.dart';
import 'package:ebrevet_card/my_settings.dart';
import 'package:ebrevet_card/mylogger.dart';
import 'package:ebrevet_card/rider_edit_page.dart';
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'style_guardrail_test.dart' show countViolations;

const modes = [ThemeMode.light, ThemeMode.dark];

/// Hosts [RiderEditPage] on top of a home page with an "open" button, so
/// popping can be observed.
Widget host({ThemeMode mode = ThemeMode.light, List<Object?>? results}) {
  final dn = DayNight(mode: mode);
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: dn),
      ChangeNotifierProvider(create: (_) => ControlState()),
      ChangeNotifierProvider(create: (_) => SourceSelection()),
    ],
    child: MaterialApp(
      theme: dn.dayTheme,
      darkTheme: dn.nightTheme,
      themeMode: mode,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final r = await Navigator.of(context).push(MaterialPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => const RiderEditPage()));
                results?.add(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> open(WidgetTester tester,
    {ThemeMode mode = ThemeMode.light, List<Object?>? results}) async {
  await tester.pumpWidget(host(mode: mode, results: results));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  expect(find.byType(RiderEditPage), findsOneWidget);
}

Finder field(int i) => find.byType(TextFormField).at(i);
String textOf(WidgetTester tester, int i) =>
    tester.widget<TextFormField>(field(i)).controller!.text;
final warning = find.byKey(const Key('rider-id-warning'));

Future<void> setRider(String first, String last, String id,
    {Map<String, Object> extra = const {}}) async {
  SharedPreferences.setMockInitialValues({
    'key-first-name': first,
    'key-last-name': last,
    'key-rusa-id': id,
    ...extra,
  });
  await MySetting.initSharedPreferences();
}

void main() {
  setUp(() async {
    await setRider('Test', 'Rider', '12345');
  });

  // AC1 (intent 0007)
  testWidgets('full-screen form with three prefilled fields, close and Save',
      (tester) async {
    await open(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(Scaffold), findsWidgets);
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.byType(Form), findsOneWidget);
    for (final label in ['First Name', 'Last Name', 'Rider ID']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(textOf(tester, 0), 'Test');
    expect(textOf(tester, 1), 'Rider');
    expect(textOf(tester, 2), '12345');
    final appBar = find.byType(AppBar);
    expect(find.descendant(of: appBar, matching: find.byIcon(Icons.close)),
        findsOneWidget);
    expect(find.descendant(of: appBar, matching: find.text('Save')),
        findsOneWidget);
  });

  // AC2 (intent 0007)
  testWidgets('inline errors; Save with an invalid field writes nothing',
      (tester) async {
    await open(tester);
    // The fields use the settings' own validators.
    final fields =
        tester.widgetList<TextFormField>(find.byType(TextFormField)).toList();
    expect(fields[0].validator, same(AppSettings.firstName.validator));
    expect(fields[1].validator, same(AppSettings.lastName.validator));
    expect(fields[2].validator, same(AppSettings.rusaID.validator));
    expect(
        AppSettings.firstName.validator, same(AppSettings.notEmptyValidator));
    expect(AppSettings.rusaID.validator, same(AppSettings.numericIDValidator));

    await tester.enterText(field(0), 'Changed');
    await tester.enterText(field(1), '');
    await tester.enterText(field(2), 'abc');
    await tester.pump();
    expect(find.text('Please enter something'), findsOneWidget);
    expect(find.text('Invalid numeric ID'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(RiderEditPage), findsOneWidget);
    expect(AppSettings.firstName.value, 'Test');
    expect(AppSettings.lastName.value, 'Rider');
    expect(AppSettings.rusaID.value, '12345');
  });

  // AC3 (intent 0007)
  testWidgets('Save writes all changed values and pops', (tester) async {
    final results = <Object?>[];
    await open(tester, results: results);
    await tester.enterText(field(0), 'Ann');
    await tester.enterText(field(1), 'Other');
    await tester.enterText(field(2), '777');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(RiderEditPage), findsNothing);
    expect(results, [true]);
    expect(AppSettings.firstName.value, 'Ann');
    expect(AppSettings.lastName.value, 'Other');
    expect(AppSettings.rusaID.value, '777');
  });

  // AC3 (intent 0007)
  testWidgets('Cancel and back with no changes pop silently', (tester) async {
    await open(tester);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(RiderEditPage), findsNothing);
    expect(find.text('Discard changes?'), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    await nav.maybePop(); // system back
    await tester.pumpAndSettle();
    expect(find.byType(RiderEditPage), findsNothing);
    expect(find.text('Discard changes?'), findsNothing);
  });

  // AC3 (intent 0007)
  for (final via in ['close', 'back']) {
    testWidgets('$via with unsaved changes asks to discard', (tester) async {
      await open(tester);
      await tester.enterText(field(0), 'Edited');
      await tester.pump();

      Future<void> leave() async {
        if (via == 'close') {
          await tester.tap(find.byIcon(Icons.close));
        } else {
          await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
        }
        await tester.pumpAndSettle();
      }

      await leave();
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.text('Keep editing'), findsOneWidget);

      // Keep editing: still on the page with edits intact.
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(RiderEditPage), findsOneWidget);
      expect(textOf(tester, 0), 'Edited');

      // Discard: pops and writes nothing.
      await leave();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.byType(RiderEditPage), findsNothing);
      expect(AppSettings.firstName.value, 'Test');
    });
  }

  // AC5 (intent 0007)
  group('developer options on Rider ID change', () {
    Future<void> withDevOption(String storedID) =>
        setRider('Test', 'Rider', storedID,
            extra: {AppSettings.openTimeOverride.key: 'true'});

    test('a new non-magic ID clears developer options', () async {
      await withDevOption(AppSettings.magicRUSAID);
      expect(AppSettings.openTimeOverride.value, isTrue);
      await saveRiderSettings(
          firstName: 'Test', lastName: 'Rider', rusaID: '12345');
      expect(AppSettings.rusaID.value, '12345');
      expect(AppSettings.openTimeOverride.value, isFalse);
    });

    test('the magic ID keeps developer options and logs a warning', () async {
      await withDevOption('12345');
      await saveRiderSettings(
          firstName: 'Test',
          lastName: 'Rider',
          rusaID: AppSettings.magicRUSAID);
      expect(AppSettings.rusaID.value, AppSettings.magicRUSAID);
      expect(AppSettings.openTimeOverride.value, isTrue);
      expect(MyLogger.records.last,
          matches(RegExp(r'WARNING\s+Developer Options Enabled$')));
    });

    test('an unchanged ID clears nothing', () async {
      await withDevOption('12345');
      await saveRiderSettings(
          firstName: 'New', lastName: 'Name', rusaID: '12345');
      expect(AppSettings.firstName.value, 'New');
      expect(AppSettings.openTimeOverride.value, isTrue);
    });

    testWidgets('the form Save applies the same rule', (tester) async {
      await withDevOption('12345');
      await open(tester);
      await tester.enterText(field(2), '777');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(AppSettings.openTimeOverride.value, isFalse);
    });
  });

  // AC6 (intent 0007)
  testWidgets('Rider ID warning shows only when the stored ID changes',
      (tester) async {
    await open(tester);
    expect(warning, findsNothing);
    await tester.enterText(field(2), '777');
    await tester.pump();
    expect(warning, findsOneWidget);
    expect(find.textContaining('Start codes depend on your Rider ID'),
        findsOneWidget);
    expect(find.textContaining('will not count in your profile stats'),
        findsOneWidget);
    // Back to the stored ID: hidden again.
    await tester.enterText(field(2), '12345');
    await tester.pump();
    expect(warning, findsNothing);
  });

  // AC6 (intent 0007)
  testWidgets('no Rider ID warning on first run (stored ID empty)',
      (tester) async {
    await setRider('', '', '');
    await open(tester);
    await tester.enterText(field(2), '777');
    await tester.pump();
    expect(warning, findsNothing);
  });

  // AC9 (intent 0007)
  for (final mode in modes) {
    testWidgets('form meets tap-target and contrast guidelines ($mode)',
        (tester) async {
      final handle = tester.ensureSemantics();
      await open(tester, mode: mode);
      await tester.enterText(field(1), '');
      await tester.enterText(field(2), '777'); // show the warning card
      await tester.pumpAndSettle();
      expect(warning, findsOneWidget);
      final scheme = Theme.of(tester.element(warning)).colorScheme;
      expect(tester.widget<Card>(warning).color, scheme.errorContainer);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }

  // AC9 (intent 0007)
  test('rider form files use theme roles and tokens only', () {
    for (final path in [
      'lib/rider_edit_page.dart',
      'lib/settings_page.dart',
      'lib/profile_page.dart',
    ]) {
      expect(countViolations(File(path).readAsStringSync()), 0, reason: path);
    }
  });
}
