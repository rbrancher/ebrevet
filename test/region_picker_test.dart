// Intent 0016: the Settings summary row and the full-screen region picker.
// Mock shared preferences only. path_provider has no documents directory, so
// cache file reads and deletes fail quietly (the cache file behaviour is
// covered in settings_event_sources_test.dart). Never the network.

import 'dart:convert';

import 'package:ebrevet_card/app_settings.dart';
import 'package:ebrevet_card/day_night.dart';
import 'package:ebrevet_card/my_settings.dart';
import 'package:ebrevet_card/region.dart';
import 'package:ebrevet_card/region_picker_page.dart';
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:ebrevet_card/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/event_sources.dart' show regionSource, customSource;

const _sourcesKey = 'key-event-sources';

List<String> keys(List<ScheduledEventsSource> l) => [for (final s in l) s.key];

/// A 390 dp wide phone.
void phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  addTearDown(tester.view.reset);
}

Widget app(Widget home) {
  final dn = DayNight();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: dn),
      ChangeNotifierProvider(create: (_) => SourceSelection()),
    ],
    child: MaterialApp(theme: dn.dayTheme, home: home),
  );
}

Future<void> pumpPicker(WidgetTester tester) async {
  phone(tester);
  await tester.pumpWidget(app(const RegionPickerPage()));
  await tester.pumpAndSettle();
}

Future<void> search(WidgetTester tester, String q) async {
  await tester.enterText(
      find.descendant(
          of: find.byKey(const Key('region-search')),
          matching: find.byType(TextField)),
      q);
  await tester.pumpAndSettle();
}

final pickerScrollable = find
    .descendant(
        of: find.byKey(const Key('region-picker-list')),
        matching: find.byType(Scrollable))
    .first;

Finder regionTile(String id) => find.byKey(ValueKey('region-$id'));

Finder configured(String key) => find.byKey(ValueKey('configured-$key'));

/// The button with [tooltip] in the configured row of [key].
Finder rowButton(String key, String tooltip) => find.descendant(
    of: configured(key),
    matching: find.ancestor(
        of: find.byTooltip(tooltip), matching: find.byType(IconButton)));

/// Taps [f], scrolling the picker list until it is built and visible.
Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 200, scrollable: pickerScrollable);
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MySetting.initSharedPreferences();
    ScheduledEvents.resetMemory();
    // No documents directory: cache reads and deletes fail at once (inside
    // fake async) instead of waiting on a real platform channel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    ScheduledEvents.resetMemory();
  });

  group('AC1 (intent 0016): summary row', () {
    testWidgets('shows "3 regions" in order and opens the picker',
        (tester) async {
      phone(tester);
      await EventSources.save([
        regionSource('938017'),
        customSource,
        regionSource('750128',
            category: ScheduleEventsSourceID.fromInternationalRegion),
      ]);
      await tester.pumpWidget(app(const SettingsPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Event Info Source'));
      await tester.pumpAndSettle();

      final summary = find.byKey(const Key('event-sources-summary'));
      expect(summary, findsOneWidget);
      expect(find.descendant(of: summary, matching: find.text('3 regions')),
          findsOneWidget);
      expect(
          find.descendant(
              of: summary,
              matching: find.text('1. PA: Eastern\n'
                  '2. Custom Event Data URL\n'
                  '3. FR: Audax Club Parisien')),
          findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(summary);
      await tester.pumpAndSettle();
      expect(find.byType(RegionPickerPage), findsOneWidget);
    });

    testWidgets('singular "1 region"', (tester) async {
      phone(tester);
      await EventSources.save([regionSource('938017')]);
      await tester.pumpWidget(app(const SettingsPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Event Info Source'));
      await tester.pumpAndSettle();
      expect(find.text('1 region'), findsOneWidget);
      expect(find.text('1. PA: Eastern'), findsOneWidget);
    });
  });

  group('AC2 (intent 0016): categories', () {
    testWidgets('checking two US and one International region adds three',
        (tester) async {
      await EventSources.save([customSource]);
      await pumpPicker(tester);
      // The three categories.
      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('International'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('US'), 2000,
          scrollable: pickerScrollable);
      expect(find.text('US'), findsOneWidget);

      const picks = {
        '938017': 'pennsylvania',
        '905030': 'california',
        '750128': 'parisien',
      };
      for (final id in picks.keys) {
        await search(tester, picks[id]!);
        await tapAndSettle(tester, regionTile(id));
      }
      final list = EventSources.list;
      expect(keys(list),
          ['custom', 'region-938017', 'region-905030', 'region-750128']);
      expect([
        for (final s in list) s.id
      ], [
        ScheduleEventsSourceID.fromURL,
        ScheduleEventsSourceID.fromRegion,
        ScheduleEventsSourceID.fromRegion,
        ScheduleEventsSourceID.fromInternationalRegion,
      ]);
    });

    testWidgets('grouped by state or country, sorted by compareByStateName',
        (tester) async {
      await EventSources.save([regionSource('938017')]);
      await pumpPicker(tester);
      // Tall enough that every California row is built.
      tester.view.physicalSize = const Size(390 * 3, 3000 * 3);
      await search(tester, 'california');
      expect(find.text('California'), findsOneWidget); // group header
      final shown = [
        for (final t in tester
            .widgetList<CheckboxListTile>(find.byType(CheckboxListTile)))
          if ((t.key as ValueKey<String>).value.startsWith('region-'))
            (t.key as ValueKey<String>).value.substring('region-'.length)
      ];
      final expected = Region.regionMap.keys
          .where((id) => Region.regionMap[id]!['state_code'] == 'CA')
          .toList()
        ..sort(Region.compareByStateName);
      expect(shown, expected);
      expect(shown, contains('905030'));

      await search(tester, 'parisien');
      expect(find.text('FR'), findsOneWidget); // country group header
    });
  });

  group('AC3 (intent 0016): search', () {
    testWidgets('filters by name, state or country, case-insensitively',
        (tester) async {
      await EventSources.save([regionSource('938017')]);
      await pumpPicker(tester);

      await search(tester, 'PENNSYLVANIA'); // state name
      expect(regionTile('938017'), findsOneWidget);
      expect(regionTile('905030'), findsNothing);

      await search(tester, 'san FRANcisco'); // region name
      expect(regionTile('905030'), findsOneWidget);
      expect(regionTile('938017'), findsNothing);

      await search(tester, 'Se'); // country code (SE) among others
      expect(regionTile('011302'), findsOneWidget);

      await search(tester, 'zzqqxx');
      expect(find.text('No matching regions'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsOneWidget); // custom only

      await search(tester, '');
      expect(find.text('No matching regions'), findsNothing);
    });
  });

  group('AC4 (intent 0016): custom source', () {
    testWidgets('custom plus a region are both configured', (tester) async {
      await EventSources.save([regionSource('938017')]);
      await pumpPicker(tester);
      await tapAndSettle(tester, find.byKey(const ValueKey('custom-source')));
      expect(keys(EventSources.list), ['region-938017', 'custom']);
      expect(configured('custom'), findsOneWidget);

      // Removing it again.
      await tapAndSettle(tester, find.byKey(const ValueKey('custom-source')));
      expect(keys(EventSources.list), ['region-938017']);
    });

    testWidgets('URL and secret fields shown in Settings only while custom',
        (tester) async {
      phone(tester);
      await EventSources.save([regionSource('938017'), customSource]);
      await tester.pumpWidget(app(const SettingsPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Event Info Source'));
      await tester.pumpAndSettle();
      expect(find.text(AppSettings.eventInfoURL.title), findsOneWidget);
      expect(find.text(AppSettings.customRegionSecret.title), findsOneWidget);

      await EventSources.save([regionSource('938017')]);
      await tester.pumpWidget(app(const SettingsPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Event Info Source'));
      await tester.pumpAndSettle();
      expect(find.text(AppSettings.eventInfoURL.title), findsNothing);
      expect(find.text(AppSettings.customRegionSecret.title), findsNothing);
    });
  });

  group('AC5 (intent 0016): reorder and remove', () {
    final a = regionSource('938017');
    final b = regionSource('905030');
    final c = customSource;

    List<String> stored() => [
          for (final e in jsonDecode(MySetting.prefs.getString(_sourcesKey)!))
            (e as Map)['region_id'] as String? ?? 'custom'
        ];

    testWidgets('move up / move down reorder and persist', (tester) async {
      await EventSources.save([a, b, c]);
      await pumpPicker(tester);
      // First row cannot move up, last cannot move down.
      expect(tester.widget<IconButton>(rowButton(a.key, 'Move up')).onPressed,
          isNull);
      expect(tester.widget<IconButton>(rowButton(c.key, 'Move down')).onPressed,
          isNull);

      await tapAndSettle(tester, rowButton(a.key, 'Move down'));
      expect(stored(), ['905030', '938017', 'custom']);
      await tapAndSettle(tester, rowButton(c.key, 'Move up'));
      expect(stored(), ['905030', 'custom', '938017']);
      // AC8 (intent 0017): a reorder keeps the selection.
      expect(EventSources.selected.key, a.key);
    });

    testWidgets('drag handle reorders', (tester) async {
      await EventSources.save([a, b, c]);
      await pumpPicker(tester);
      final handle = find.descendant(
          of: configured(a.key), matching: find.byIcon(Icons.drag_handle));
      final rowHeight = tester.getSize(configured(a.key)).height;
      final g = await tester.startGesture(tester.getCenter(handle));
      for (var i = 0; i < 10; i++) {
        await g.moveBy(Offset(0, rowHeight * 0.15));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(stored(), ['905030', '938017', 'custom']);
    });

    testWidgets('remove drops the source and persists', (tester) async {
      await EventSources.save([a, b, c]);
      await pumpPicker(tester);
      await tapAndSettle(tester, rowButton(b.key, 'Remove'));
      expect(stored(), ['938017', 'custom']);
      expect(configured(b.key), findsNothing);
      expect(find.byKey(const Key('last-source-message')), findsNothing);
    });

    testWidgets('the last source cannot be removed', (tester) async {
      await EventSources.save([a]);
      await pumpPicker(tester);
      expect(tester.widget<IconButton>(rowButton(a.key, 'Remove')).onPressed,
          isNull);
      expect(find.text(lastSourceMessage), findsOneWidget);
      // Unchecking it in its category is disabled too.
      await search(tester, 'pennsylvania');
      final tile = tester.widget<CheckboxListTile>(regionTile('938017'));
      expect(tile.value, isTrue);
      expect(tile.onChanged, isNull);
      await tester.tap(regionTile('938017'));
      await tester.pumpAndSettle();
      expect(keys(EventSources.list), [a.key]);

      // With a second source, removal is allowed again.
      await tapAndSettle(tester, find.byKey(const ValueKey('custom-source')));
      expect(find.text(lastSourceMessage), findsNothing);
      expect(tester.widget<IconButton>(rowButton(a.key, 'Remove')).onPressed,
          isNotNull);
    });
  });

  testWidgets('AC6 (intent 0016): picker cannot create duplicates',
      (tester) async {
    await EventSources.save([regionSource('938017')]);
    await pumpPicker(tester);
    await search(tester, 'california');
    // Check, uncheck, check: one entry.
    await tapAndSettle(tester, regionTile('905030'));
    await tapAndSettle(tester, regionTile('905030'));
    await tapAndSettle(tester, regionTile('905030'));
    expect(keys(EventSources.list), ['region-938017', 'region-905030']);
    // A configured region shows as checked.
    expect(tester.widget<CheckboxListTile>(regionTile('905030')).value, isTrue);
  });

  testWidgets(
      'AC8 (intent 0016): unknown region is listed with the message and can '
      'be removed', (tester) async {
    expect(Region.regionMap.containsKey('999999'), isFalse);
    await EventSources.save([regionSource('999999'), regionSource('938017')]);
    await pumpPicker(tester);
    expect(tester.takeException(), isNull);
    expect(
        find.descendant(
            of: configured('region-999999'),
            matching: find.text('Region 999999')),
        findsOneWidget);
    expect(
        find.descendant(
            of: configured('region-999999'),
            matching: find.text(unknownRegionMessage)),
        findsOneWidget);

    await tapAndSettle(tester, rowButton('region-999999', 'Remove'));
    expect(keys(EventSources.list), ['region-938017']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AC11 (intent 0016): no overflow at 390 dp', (tester) async {
    await EventSources.save([
      regionSource('999999'),
      regionSource('938017'),
      customSource,
      regionSource('905030'),
      regionSource('750128',
          category: ScheduleEventsSourceID.fromInternationalRegion),
    ]);
    await pumpPicker(tester);
    expect(tester.getSize(find.byType(RegionPickerPage)).width, 390);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('US'), 2000,
        scrollable: pickerScrollable);
    expect(tester.takeException(), isNull);
    await search(tester, 'zzqqxx');
    expect(tester.takeException(), isNull);
  });
}
