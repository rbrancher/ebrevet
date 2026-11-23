// Intent 0015: migration from the old single-source settings and adoption of
// the legacy single event cache. Mock prefs and temp storage only.

import 'dart:io';

import 'package:ebrevet_card/app_settings.dart';
import 'package:ebrevet_card/mock/mock_server.dart';
import 'package:ebrevet_card/my_settings.dart';
import 'package:ebrevet_card/region.dart';
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_sources.dart';

// Old settings keys and their stored form (MySetting stores enum indexes).
const _oldSourceKey = 'key-event-info-source-id';
const _oldRegionKey = 'key-region-id';
const _oldURLKey = 'key-event-info-url';
const _sourcesKey = 'key-event-sources';
final _fromRegion = '${ScheduleEventsSourceID.fromRegion.index}';
final _fromIntl = '${ScheduleEventsSourceID.fromInternationalRegion.index}';
final _fromURL = '${ScheduleEventsSourceID.fromURL.index}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Directory? docs;

  tearDown(() {
    if (docs != null) tearDownEventSources(docs!);
    docs = null;
  });

  Future<void> start(Map<String, Object> prefs) async =>
      docs = await setUpEventSources(prefs);

  Map<String, String?> oldKeys() => {
        for (final k in [_oldSourceKey, _oldRegionKey, _oldURLKey])
          k: MySetting.prefs.getString(k),
      };

  group('AC2 (intent 0015): migration', () {
    test('fresh install gives the default region (938017, PA Rando)', () async {
      await start({});
      expect(await EventSources.migrate(), isTrue);
      final list = EventSources.list;
      expect(list, hasLength(1));
      expect(list.single.regionID, Region.defaultRegion);
      expect(list.single.id, ScheduleEventsSourceID.fromRegion);
      expect(Region.defaultRegion, '938017');
      // The old keys stay unset.
      expect(oldKeys().values, everyElement(isNull));
    });

    test('a US region install migrates to exactly that one entry', () async {
      final prefs = {_oldSourceKey: _fromRegion, _oldRegionKey: '905030'};
      await start(prefs);
      expect(await EventSources.migrate(), isTrue);
      final list = EventSources.list;
      expect(list, hasLength(1));
      expect(list.single.id, ScheduleEventsSourceID.fromRegion);
      expect(list.single.regionID, '905030');
      expect(EventSources.selected.key, 'region-905030');
      expect(oldKeys()[_oldSourceKey], _fromRegion);
      expect(oldKeys()[_oldRegionKey], '905030');
    });

    test('an International region install keeps its category', () async {
      await start({_oldSourceKey: _fromIntl, _oldRegionKey: '750128'});
      await EventSources.migrate();
      final list = EventSources.list;
      expect(list, hasLength(1));
      expect(list.single.id, ScheduleEventsSourceID.fromInternationalRegion);
      expect(list.single.regionID, '750128');
    });

    test('a custom-URL install migrates to the single custom entry', () async {
      await start({
        _oldSourceKey: _fromURL,
        _oldRegionKey: '905030',
        _oldURLKey: 'https://example.invalid/feed',
      });
      await EventSources.migrate();
      final list = EventSources.list;
      expect(list, hasLength(1));
      expect(list.single.isCustom, isTrue);
      expect(list.single.url, 'https://example.invalid/feed');
      expect(oldKeys(), {
        _oldSourceKey: _fromURL,
        _oldRegionKey: '905030',
        _oldURLKey: 'https://example.invalid/feed',
      });
    });

    test('a region ID no longer in Region.regionMap is migrated as is',
        () async {
      await start({_oldSourceKey: _fromRegion, _oldRegionKey: '999999'});
      expect(Region.regionMap.containsKey('999999'), isFalse);
      await EventSources.migrate();
      expect(EventSources.list.single.regionID, '999999');
      expect(EventSources.list.single.isUnknownRegion, isTrue);
      expect(oldKeys()[_oldRegionKey], '999999');
    });

    test('runs once and never overwrites an existing list', () async {
      await start({_oldSourceKey: _fromRegion, _oldRegionKey: '905030'});
      expect(await EventSources.migrate(), isTrue);
      await EventSources.save([regionSource('750128'), customSource]);
      // Old settings change later (e.g. the Settings screen of a downgrade).
      await AppSettings.regionID.setValue('938016');
      expect(await EventSources.migrate(), isFalse);
      expect([for (final s in EventSources.list) s.key],
          ['region-750128', 'custom']);
    });

    test('startup migrates through refreshEventsFromDisk', () async {
      await start({_oldSourceKey: _fromRegion, _oldRegionKey: '905030'});
      expect(MySetting.prefs.getString(_sourcesKey), isNull);
      await ScheduledEvents.refreshEventsFromDisk();
      expect(MySetting.prefs.getString(_sourcesKey), isNotNull);
      expect(EventSources.list.single.key, 'region-905030');
      expect(oldKeys()[_oldRegionKey], '905030');
    });
  });

  group('AC5 (intent 0015): legacy cache', () {
    /// Writes a legacy cache, as the old app did after a refresh, from the
    /// mock feed of [regionID] with the recorded [recordedSource].
    Future<List<String>> writeLegacy(
        String regionID, Map<String, dynamic> recordedSource) async {
      final feed = await MockServer.scheduledEvents(regionID: regionID);
      feed[ScheduledEvents.lastRefreshedFieldName] =
          DateTime.utc(2026, 11, 1, 8).toIso8601String();
      feed[ScheduledEvents.eventInfoSourceFieldName] = recordedSource;
      expect(await legacyStorage.writeJSON(feed), isTrue);
      return [for (final e in ScheduledEvents.parseEventList(feed)) e.eventID];
    }

    test(
        'is adopted as the migrated source\'s cache and kept under the new '
        'name', () async {
      await start({_oldSourceKey: _fromRegion, _oldRegionKey: '938017'});
      final ids = await writeLegacy('938017', {'id': 'fromRegion'});

      await ScheduledEvents.refreshEventsFromDisk(); // offline startup
      expect([for (final e in ScheduledEvents.events) e.eventID], ids);
      expect(ScheduledEvents.lastRefreshed,
          DateTime.utc(2026, 11, 1, 8).toLocal());
      expect(ScheduledEvents.hasEventAuthority, isTrue);

      final newFile =
          await ScheduledEvents.storageFor(regionSource('938017')).readJSON();
      expect(newFile, isNotEmpty);
      expect(newFile[ScheduledEvents.eventInfoSourceFieldName],
          {'id': 'fromRegion', 'region_id': '938017'});
      // Left in place for a downgrade.
      expect(await legacyStorage.readJSON(), isNotEmpty);

      // Read once: a later legacy file is not adopted again.
      ScheduledEvents.resetMemory();
      await ScheduledEvents.storageFor(regionSource('938017')).writeJSON({});
      await ScheduledEvents.refreshEventsFromDisk();
      expect(ScheduledEvents.events, isEmpty);
    });

    test('a custom-URL legacy cache is adopted by the custom entry', () async {
      await start({_oldSourceKey: _fromURL, _oldURLKey: 'https://x.invalid'});
      final ids = await writeLegacy('938017', {'id': 'fromURL'});
      await ScheduledEvents.refreshEventsFromDisk();
      expect(EventSources.selected.isCustom, isTrue);
      expect([for (final e in ScheduledEvents.events) e.eventID], ids);
    });

    test('is not adopted if its recorded source does not match', () async {
      // Region install, but the legacy file came from the custom URL.
      await start({_oldSourceKey: _fromRegion, _oldRegionKey: '938017'});
      await writeLegacy('938017', {'id': 'fromURL'});
      await ScheduledEvents.refreshEventsFromDisk();
      expect(ScheduledEvents.events, isEmpty);
      expect(ScheduledEvents.lastRefreshed, isNull);
      expect(
          await ScheduledEvents.storageFor(regionSource('938017')).readJSON(),
          isEmpty);
    });

    test('is not adopted for a different recorded region ID', () async {
      await start({_oldSourceKey: _fromRegion, _oldRegionKey: '938017'});
      await writeLegacy(MockServer.altRegionID,
          {'id': 'fromRegion', 'region_id': MockServer.altRegionID});
      await ScheduledEvents.refreshEventsFromDisk();
      expect(ScheduledEvents.events, isEmpty);
    });

    test('is not adopted with no recorded source', () async {
      await start({_oldSourceKey: _fromRegion, _oldRegionKey: '938017'});
      final feed = await MockServer.scheduledEvents();
      await legacyStorage.writeJSON(feed);
      await ScheduledEvents.refreshEventsFromDisk();
      expect(ScheduledEvents.events, isEmpty);
    });

    test('is not adopted once a source list exists', () async {
      await start({_oldSourceKey: _fromRegion, _oldRegionKey: '938017'});
      await EventSources.save([regionSource('938017')]);
      await writeLegacy('938017', {'id': 'fromRegion'});
      await ScheduledEvents.refreshEventsFromDisk();
      expect(ScheduledEvents.events, isEmpty);
    });
  });
}
