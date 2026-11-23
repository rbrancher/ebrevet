// Intent 0016: what the region picker does to the stored source list, the
// selection and the per-source caches. Mock shared preferences, temp storage
// and the mock server only; never the network.

import 'dart:io';

import 'package:ebrevet_card/app_settings.dart';
import 'package:ebrevet_card/day_night.dart';
import 'package:ebrevet_card/mock/mock_server.dart';
import 'package:ebrevet_card/my_settings.dart';
import 'package:ebrevet_card/region.dart';
import 'package:ebrevet_card/region_picker_page.dart';
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:ebrevet_card/settings_page.dart';
import 'package:ebrevet_card/settings_tiles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/event_sources.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;

  setUp(() async => docs = await setUpEventSources());
  tearDown(() => tearDownEventSources(docs));

  List<String> keys(List<ScheduledEventsSource> l) =>
      [for (final s in l) s.key];

  List<String> ids(ScheduledEventsSource s) =>
      [for (final e in ScheduledEvents.cacheFor(s).events) e.eventID];

  /// Simulates a restart: the stored prefs are re-read into a fresh
  /// SharedPreferences instance and the in-memory caches are dropped.
  Future<void> restart() async {
    final stored = <String, Object>{
      for (final k in MySetting.prefs.getKeys()) k: MySetting.prefs.get(k)!
    };
    SharedPreferences.setMockInitialValues(stored);
    await MySetting.initSharedPreferences();
    ScheduledEvents.resetMemory();
  }

  group('AC6 (intent 0016): persistence', () {
    test('the saved list and order come back after a restart', () async {
      final selection = SourceSelection();
      await selection.setSources([
        regionSource('905030'),
        customSource,
        regionSource('750128',
            category: ScheduleEventsSourceID.fromInternationalRegion),
      ]);
      await selection.setSources([
        customSource,
        regionSource('905030'),
        regionSource('750128',
            category: ScheduleEventsSourceID.fromInternationalRegion),
      ], selectFirst: true);
      selection.dispose();

      await restart();
      final list = EventSources.list;
      expect(keys(list), ['custom', 'region-905030', 'region-750128']);
      expect(list[2].id, ScheduleEventsSourceID.fromInternationalRegion);
      expect(EventSources.selected.key, 'custom');
    });

    test('duplicates cannot be stored', () async {
      final selection = SourceSelection();
      await selection.setSources([regionSource('938017')]);
      for (final dup in [
        [regionSource('938017'), regionSource('938017')],
        [
          regionSource('938017'),
          regionSource('938017',
              category: ScheduleEventsSourceID.fromInternationalRegion),
        ],
        [customSource, customSource],
      ]) {
        await expectLater(selection.setSources(dup), throwsArgumentError);
      }
      // An empty list is refused too.
      await expectLater(selection.setSources([]), throwsArgumentError);
      expect(keys(EventSources.list), ['region-938017']);
      selection.dispose();
    });
  });

  group('AC7 (intent 0016): selected source stays valid', () {
    test('remove B of A, B, C: A and C unchanged, A selected', () async {
      final a = regionSource('938017');
      final b = regionSource(MockServer.altRegionID);
      final c = regionSource('750128',
          category: ScheduleEventsSourceID.fromInternationalRegion);
      await EventSources.save([a, b, c]);
      for (final s in [a, b, c]) {
        await refreshFromMock(s);
      }
      await EventSources.select(b);
      final selection = SourceSelection();
      expect(selection.eventInfoSource.key, b.key);

      final aIDs = ids(a), cIDs = ids(c);
      final aTime = ScheduledEvents.cacheFor(a).lastRefreshed;
      final cTime = ScheduledEvents.cacheFor(c).lastRefreshed;
      final aFile = await ScheduledEvents.storageFor(a).readJSON();
      final cFile = await ScheduledEvents.storageFor(c).readJSON();
      expect(aIDs, isNotEmpty);
      expect(ids(b), isNotEmpty);
      expect(await ScheduledEvents.storageFor(b).readJSON(), isNotEmpty);

      await selection.setSources([a, c]);

      // The first remaining source is selected, and its events shown.
      expect(EventSources.selected.key, a.key);
      expect(selection.eventInfoSource.key, a.key);
      expect([for (final e in ScheduledEvents.events) e.eventID], aIDs);
      expect(ScheduledEvents.lastRefreshed, aTime);

      // B's cache file and in-memory cache are gone.
      expect(await ScheduledEvents.storageFor(b).readJSON(), isEmpty);
      expect(ScheduledEvents.cacheFor(b).loaded, isFalse);
      expect(ScheduledEvents.cacheFor(b).events, isEmpty);

      // A and C are unchanged, in memory and on disk.
      expect(ids(a), aIDs);
      expect(ids(c), cIDs);
      expect(ScheduledEvents.cacheFor(a).lastRefreshed, aTime);
      expect(ScheduledEvents.cacheFor(c).lastRefreshed, cTime);
      expect(await ScheduledEvents.storageFor(a).readJSON(), aFile);
      expect(await ScheduledEvents.storageFor(c).readJSON(), cFile);
      selection.dispose();
    });

    test('removing a source that is not selected keeps the selection',
        () async {
      final a = regionSource('938017');
      final b = regionSource(MockServer.altRegionID);
      await EventSources.save([a, b]);
      await EventSources.select(b);
      final selection = SourceSelection();
      await selection.setSources([b]);
      expect(EventSources.selected.key, b.key);
      selection.dispose();
    });
  });

  test(
      'AC10 (intent 0016): moving a source first shows its events '
      '(before the slice c switcher)', () async {
    final a = regionSource('938017');
    final b = regionSource(MockServer.altRegionID);
    await EventSources.save([a, b]);
    await refreshFromMock(a);
    await refreshFromMock(b);
    final selection = SourceSelection();
    expect([for (final e in ScheduledEvents.events) e.eventID], ids(a));

    // The picker's move up / drag passes selectFirst.
    await selection.setSources([b, a], selectFirst: true);
    expect(selection.eventInfoSource.key, b.key);
    expect([for (final e in ScheduledEvents.events) e.eventID], ids(b));
    expect(ids(b), isNot(ids(a)));

    // Adding a source keeps showing the selected one.
    await selection.setSources([b, a, customSource]);
    expect(selection.eventInfoSource.key, b.key);
    selection.dispose();
  });

  group('AC9 (intent 0016): old Settings controls', () {
    test('the old settings keys are not written or removed', () async {
      await AppSettings.scheduleEventsSourceID
          .setValue(ScheduleEventsSourceID.fromInternationalRegion);
      await AppSettings.regionID.setValue('750128');
      await EventSources.migrate();
      final oldSource =
          MySetting.prefs.getString(AppSettings.scheduleEventsSourceID.key);
      final oldRegion = MySetting.prefs.getString(AppSettings.regionID.key);
      expect(oldSource, isNotNull);
      expect(oldRegion, '750128');

      final selection = SourceSelection();
      await selection.setSources([customSource, regionSource('905030')],
          selectFirst: true);
      await selection.setSources([regionSource('905030')]);
      await selection.customSettingsChanged();
      selection.dispose();

      expect(MySetting.prefs.getString(AppSettings.scheduleEventsSourceID.key),
          oldSource);
      expect(MySetting.prefs.getString(AppSettings.regionID.key), oldRegion);
    });

    testWidgets('Settings has the summary row, not the dropdowns',
        (tester) async {
      final dn = DayNight();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: dn),
          ChangeNotifierProvider(create: (_) => SourceSelection()),
        ],
        child: MaterialApp(home: const SettingsPage()),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Event Info Source'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('event-sources-summary')), findsOneWidget);
      expect(find.byType(RadioButtonSettingsTile), findsNothing);
      expect(find.byType(DropDownSettingsTile), findsNothing);
      expect(find.byType(DropdownButton<String>), findsNothing);
      // Get Latest Region List is still offered.
      await tester.tap(find.text('Preferences'));
      await tester.pumpAndSettle();
      expect(find.text('Get Latest Region List'), findsOneWidget);
    });

    test('Get Latest Region List still loads the region list (mock server)',
        () async {
      final before = Region.regionMap.length;
      Region.regionsLastRefreshed = null;
      await http.runWithClient(
          () => Region.fetchRegionsFromServer(quiet: true), MockServer.client);
      expect(Region.regionsLastRefreshed, isNotNull);
      expect(Region.regionMap.length, before);
    });

    testWidgets('the picker rebuilds from a new Region.regionMap',
        (tester) async {
      const newID = '999990';
      Region.updateRegionMap([
        {
          'club_acp_code': newID,
          'state_code': 'ZZ',
          'state_name': 'Zedland',
          'country_code': 'US',
          'region_name': 'Testville',
          'club_name': 'Testville Randonneurs',
          'website_url': '',
        }
      ]);
      addTearDown(() => Region.regionMap.remove(newID));

      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => SourceSelection(),
        child: const MaterialApp(home: RegionPickerPage()),
      ));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(
              of: find.byKey(const Key('region-search')),
              matching: find.byType(TextField)),
          'testville');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('region-$newID')), findsOneWidget);
      expect(find.text('Zedland'), findsOneWidget);
    });
  });
}
