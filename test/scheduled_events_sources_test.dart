// Intent 0015: configured event sources, selection, separate caches,
// per-source refresh and cross-source lookup. Mock shared preferences, temp
// storage and the mock server only; never the network.

import 'dart:convert';
import 'dart:io';

import 'package:ebrevet_card/activated_event.dart';
import 'package:ebrevet_card/app_settings.dart';
import 'package:ebrevet_card/event.dart';
import 'package:ebrevet_card/mock/mock_server.dart';
import 'package:ebrevet_card/my_settings.dart';
import 'package:ebrevet_card/outcome.dart';
import 'package:ebrevet_card/region.dart';
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:ebrevet_card/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/event_sources.dart';

const _sourcesKey = 'key-event-sources';
const _selectedKey = 'key-selected-event-source';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory docs;

  setUp(() async => docs = await setUpEventSources());
  tearDown(() => tearDownEventSources(docs));

  List<String> keys(List<ScheduledEventsSource> l) =>
      [for (final s in l) s.key];

  group('AC1 (intent 0015): source list', () {
    test('round trip keeps every kind of entry and the order', () async {
      final sources = [
        regionSource('905030'),
        customSource,
        regionSource('750128',
            category: ScheduleEventsSourceID.fromInternationalRegion),
      ];
      await EventSources.save(sources);
      final read = EventSources.list;
      expect(keys(read), ['region-905030', 'custom', 'region-750128']);
      expect([
        for (final s in read) s.id
      ], [
        ScheduleEventsSourceID.fromRegion,
        ScheduleEventsSourceID.fromURL,
        ScheduleEventsSourceID.fromInternationalRegion,
      ]);
      expect(read[0].regionID, '905030');
      expect(read[1].regionID, isNull);
      // Stored as JSON through MySetting/shared preferences.
      final stored = jsonDecode(MySetting.prefs.getString(_sourcesKey)!);
      expect(stored, [
        {'category': 'fromRegion', 'region_id': '905030'},
        {'category': 'fromURL'},
        {'category': 'fromInternationalRegion', 'region_id': '750128'},
      ]);
    });

    test('the custom entry uses the custom URL and secret settings', () async {
      await AppSettings.eventInfoURL.setValue('https://example.invalid/feed');
      await AppSettings.customRegionSecret.setValue('custom-secret');
      expect(customSource.url, 'https://example.invalid/feed');
      expect(customSource.secret, 'custom-secret');
      expect(regionSource('905030').secret, isNot('custom-secret'));
    });

    test('duplicates are rejected', () async {
      await EventSources.save([regionSource('938017')]);
      expect(await EventSources.add(regionSource('938017')), isFalse);
      // Same region in the other category is the same source.
      expect(
          await EventSources.add(regionSource('938017',
              category: ScheduleEventsSourceID.fromInternationalRegion)),
          isFalse);
      expect(await EventSources.add(customSource), isTrue);
      expect(await EventSources.add(customSource), isFalse);
      expect(keys(EventSources.list), ['region-938017', 'custom']);
      expect(
          () => EventSources.save(
              [regionSource('905030'), regionSource('905030')]),
          throwsArgumentError);
      expect(keys(EventSources.list), ['region-938017', 'custom']);
    });

    test('garbage stored data gives the default list and never throws',
        () async {
      for (final garbage in [
        'not json',
        '{"category":"fromRegion"}',
        '[1,2]',
        '[{"category":"nope","region_id":"938017"}]',
        '[{"category":"fromRegion"}]',
        '[{"category":"fromRegion","region_id":938017}]',
        '[{"category":"fromRegion","region_id":"905030"},'
            '{"category":"fromRegion","region_id":"905030"}]',
        'null',
      ]) {
        await MySetting.prefs.setString(_sourcesKey, garbage);
        expect(keys(EventSources.list), ['region-938017'], reason: garbage);
        expect(EventSources.selected.key, 'region-938017', reason: garbage);
      }
    });
  });

  group('AC3 (intent 0015): selected source', () {
    test('is persisted and survives a restart', () async {
      await EventSources.save([regionSource('938017'), regionSource('905030')]);
      await EventSources.select(regionSource('905030'));
      // Restart: a fresh read of the same stored prefs.
      final stored = {
        _sourcesKey: MySetting.prefs.getString(_sourcesKey)!,
        _selectedKey: MySetting.prefs.getString(_selectedKey)!,
      };
      tearDownEventSources(docs);
      docs = await setUpEventSources(stored);
      expect(EventSources.selected.key, 'region-905030');
      expect(SourceSelection().eventInfoSource.key, 'region-905030');
    });

    test('a selection missing from the list falls back to the first source',
        () async {
      await EventSources.save([regionSource('905030'), customSource]);
      await EventSources.select(regionSource('750128'));
      expect(EventSources.selected.key, 'region-905030');
    });

    test('an empty list falls back to the default region', () async {
      await EventSources.save([]);
      expect(EventSources.list, isEmpty);
      expect(EventSources.selected.key, 'region-${Region.defaultRegion}');
    });
  });

  group('AC4 (intent 0015): separate caches', () {
    test('load A, load B: A events and last-refreshed are unchanged', () async {
      final a = regionSource('938017');
      final b = regionSource(MockServer.altRegionID);
      await EventSources.save([a, b]);

      await refreshFromMock(a);
      final aEvents = [
        for (final e in ScheduledEvents.cacheFor(a).events) e.eventID
      ];
      final aRefreshed = ScheduledEvents.cacheFor(a).lastRefreshed;
      expect(aEvents, isNotEmpty);
      expect(aRefreshed, isNotNull);
      final aFile = await ScheduledEvents.storageFor(a).readJSON();

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await EventSources.select(b);
      await refreshFromMock(b);

      expect(ScheduledEvents.cacheFor(b).events, isNotEmpty);
      expect([for (final e in ScheduledEvents.cacheFor(a).events) e.eventID],
          aEvents);
      expect(ScheduledEvents.cacheFor(a).lastRefreshed, aRefreshed);
      expect(await ScheduledEvents.storageFor(a).readJSON(), aFile);
      // Cache files are named from the stable source key.
      expect(ScheduledEvents.storageFor(a).fileName,
          'futureEvents-region-938017.json');
      expect(ScheduledEvents.storageFor(b).fileName,
          'futureEvents-region-${MockServer.altRegionID}.json');

      // The selected source drives the list page's events and time.
      expect([for (final e in ScheduledEvents.events) e.eventID],
          [for (final e in ScheduledEvents.cacheFor(b).events) e.eventID]);
      expect(ScheduledEvents.lastRefreshed,
          ScheduledEvents.cacheFor(b).lastRefreshed);

      // After a restart both caches come back from their own files.
      ScheduledEvents.resetMemory();
      await ScheduledEvents.refreshEventsFromDisk();
      expect([for (final e in ScheduledEvents.cacheFor(a).events) e.eventID],
          aEvents);
      expect(ScheduledEvents.cacheFor(b).events, isNotEmpty);
    });

    // Since intent 0016 Settings changes the source list through the region
    // picker (SourceSelection.setSources) instead of updateFromSettings.
    test('Settings changes (setSources) keep other sources\' data', () async {
      final a = regionSource('938017');
      final b = regionSource(MockServer.altRegionID);
      await EventSources.save([a]);
      await refreshFromMock(a);
      final aEvents = [
        for (final e in ScheduledEvents.cacheFor(a).events) e.eventID
      ];

      final selection = SourceSelection();
      await selection.setSources([b, a], selectFirst: true);
      expect(EventSources.selected.key, 'region-${MockServer.altRegionID}');
      expect(selection.eventInfoSource.key, 'region-${MockServer.altRegionID}');
      expect(ScheduledEvents.events, isEmpty); // B not loaded yet

      // A's cache, in memory and on disk, is untouched.
      expect([for (final e in ScheduledEvents.cacheFor(a).events) e.eventID],
          aEvents);
      expect((await ScheduledEvents.storageFor(a).readJSON()), isNotEmpty);

      // Switching back shows A's events again, without a refresh.
      await selection.setSources([a, b], selectFirst: true);
      expect([for (final e in ScheduledEvents.events) e.eventID], aEvents);
      selection.dispose();
    });

    test('Clear Event List clears the selected source only', () async {
      final a = regionSource('938017');
      final b = regionSource(MockServer.altRegionID);
      await EventSources.save([a, b]);
      await refreshFromMock(a);
      await refreshFromMock(b);
      await EventSources.select(b);
      ScheduledEvents.clearSource(EventSources.selected);
      expect(ScheduledEvents.cacheFor(b).events, isEmpty);
      expect(ScheduledEvents.cacheFor(a).events, isNotEmpty);
    });
  });

  group('AC6 (intent 0015): per-source refresh and verification', () {
    test('fetches only the given source with that source\'s URL', () async {
      final a = regionSource('938017');
      final b = regionSource(MockServer.altRegionID);
      await EventSources.save([a, b]);
      final requested = <Uri>[];
      await refreshFromMock(b, requested: requested);
      expect(requested, hasLength(1));
      expect(requested.single.pathSegments,
          containsAllInOrder(['scheduled_events', MockServer.altRegionID]));
      // Nonce appended, as before.
      expect(requested.single.pathSegments.last, hasLength(32));
      expect(ScheduledEvents.cacheFor(a).events, isEmpty);
      expect(ScheduledEvents.cacheFor(b).events, isNotEmpty);
    });

    test('a region source verifies with its region secret', () async {
      final a = regionSource('938017');
      MockServer.signingSecret = (rid) => Region(regionID: rid!).secret;
      await refreshFromMock(a);
      expect(ScheduledEvents.cacheFor(a).events, isNotEmpty);
    });

    test('the custom source uses the custom URL and custom secret', () async {
      await AppSettings.eventInfoURL
          .setValue('https://mock.ebrevet.invalid/custom/scheduled_events/x');
      await AppSettings.customRegionSecret.setValue('custom-secret');
      await EventSources.save([regionSource('938017'), customSource]);
      MockServer.signingSecret = (_) => 'custom-secret';
      final requested = <Uri>[];
      await refreshFromMock(customSource, requested: requested);
      expect(requested.single.host, 'mock.ebrevet.invalid');
      expect(requested.single.path, startsWith('/custom/scheduled_events/x/'));
      expect(ScheduledEvents.cacheFor(customSource).events, isNotEmpty);
    });

    test(
        'a signature made with another source\'s secret is rejected and '
        'leaves that source\'s cache untouched', () async {
      await AppSettings.eventInfoURL
          .setValue('https://mock.ebrevet.invalid/custom/scheduled_events/x');
      await AppSettings.customRegionSecret.setValue('custom-secret');
      final region = regionSource('938017');
      await EventSources.save([region, customSource]);

      // Good custom data first.
      MockServer.signingSecret = (_) => 'custom-secret';
      await refreshFromMock(customSource);
      final before = [
        for (final e in ScheduledEvents.cacheFor(customSource).events) e.eventID
      ];
      final beforeTime = ScheduledEvents.cacheFor(customSource).lastRefreshed;
      final beforeFile =
          await ScheduledEvents.storageFor(customSource).readJSON();

      // Then a feed signed with the region's secret.
      MockServer.signingSecret = (_) => region.secret;
      await expectLater(refreshFromMock(customSource),
          throwsA(predicate((e) => '$e'.contains('Signature invalid'))));
      expect([
        for (final e in ScheduledEvents.cacheFor(customSource).events) e.eventID
      ], before);
      expect(ScheduledEvents.cacheFor(customSource).lastRefreshed, beforeTime);
      expect(await ScheduledEvents.storageFor(customSource).readJSON(),
          beforeFile);

      // And the other way round: custom secret on the region feed.
      MockServer.signingSecret = (_) => 'custom-secret';
      await expectLater(refreshFromMock(region), throwsA(anything));
      expect(ScheduledEvents.cacheFor(region).events, isEmpty);
      expect(await ScheduledEvents.storageFor(region).readJSON(), isEmpty);
    });
  });

  group('AC7 (intent 0015): cross-source lookup', () {
    test('an event from B resolves while A is selected', () async {
      final a = regionSource('938017');
      final b = regionSource(MockServer.altRegionID);
      await EventSources.save([a, b]);
      await EventSources.select(a);
      await refreshFromMock(a);
      await refreshFromMock(b);
      expect(EventSources.selected.key, a.key);

      final bEvent = ScheduledEvents.cacheFor(b).events.first;
      expect(bEvent.regionID, MockServer.altRegionID);
      expect(ScheduledEvents.events.any((e) => e.eventID == bEvent.eventID),
          isFalse);
      expect(ScheduledEvents.findEvent(bEvent.eventID), same(bEvent));
      final aEvent = ScheduledEvents.cacheFor(a).events.first;
      expect(ScheduledEvents.findEvent(aEvent.eventID), same(aEvent));
      expect(ScheduledEvents.findEvent('no-such-event'), isNull);
      // The start-code check's event authority does not depend on selection.
      expect(ScheduledEvents.hasEventAuthority, isTrue);
      await EventSources.select(b);
      expect(ScheduledEvents.findEvent(aEvent.eventID), same(aEvent));
    });

    test('saved ride JSON keys are unchanged', () async {
      final b = regionSource(MockServer.altRegionID);
      await EventSources.save([regionSource('938017'), b]);
      await refreshFromMock(b);
      final event = ScheduledEvents.cacheFor(b).events.first;
      final ride =
          ActivatedEvent(event, '12345', EventOutcomes(), StartStyle.massStart);
      final json = ride.toJson();
      expect(
          json.keys.toSet(), {'event', 'outcomes', 'start_style', 'rider_id'});
      // No source or selection data leaks into the saved ride.
      expect(jsonEncode(json), isNot(contains('event_info_source')));
      expect(jsonEncode(json), isNot(contains('region-')));
      final restored = ActivatedEvent.fromJson(jsonDecode(jsonEncode(json)));
      expect(restored.event.eventID, event.eventID);
    });
  });

  group('AC8 (intent 0015): removed or unknown region', () {
    test('stays in the list; refresh fails gracefully, never crashes',
        () async {
      final gone = regionSource('999999');
      expect(Region.regionMap.containsKey('999999'), isFalse);
      await EventSources.save([gone, regionSource('938017')]);
      expect(keys(EventSources.list), ['region-999999', 'region-938017']);
      expect(EventSources.selected.key, 'region-999999');
      expect(gone.isUnknownRegion, isTrue);
      expect(gone.fullDescription, contains('Unknown Region'));

      final requested = <Uri>[];
      await expectLater(refreshFromMock(gone, requested: requested),
          throwsA(predicate((e) => '$e'.contains('Unknown region 999999'))));
      expect(requested, isEmpty);
      expect(ScheduledEvents.events, isEmpty);
      // Still configured, and startup loading copes with it.
      expect(keys(EventSources.list), ['region-999999', 'region-938017']);
      ScheduledEvents.resetMemory();
      expect(await ScheduledEvents.refreshEventsFromDisk(), 'unknown');
    });
  });

  testWidgets(
      'AC8 (intent 0015): Settings shows the unknown region message and '
      'keeps the region configured', (tester) async {
    await AppSettings.scheduleEventsSourceID
        .setValue(ScheduleEventsSourceID.fromRegion);
    await AppSettings.regionID.setValue('999999');
    await EventSources.migrate();
    final selection = SourceSelection();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: selection,
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
              child: EventSearchSettings(initiallyExpanded: true)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Somehow the region selected is not in the'),
        findsOneWidget);
    // The rider can still open the region picker (intent 0016 replaced the
    // dropdown with a summary row).
    expect(find.byKey(const Key('event-sources-summary')), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Nothing was silently reset.
    expect(AppSettings.regionID.value, '999999');
    expect(EventSources.list.single.regionID, '999999');
  });

  test('ScheduledEvents.events setter still targets the selected source',
      () async {
    // Existing widget tests set events this way (AC9, intent 0015).
    final events = <Event>[];
    ScheduledEvents.events = events;
    expect(ScheduledEvents.events, same(events));
    expect(
        ScheduledEvents.cacheFor(EventSources.selected).events, same(events));
  });
}
