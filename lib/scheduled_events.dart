// Copyright (C) 2023 Chris Nadovich
// This file is part of eBrevet <https://github.com/ctnadovich/ebrevet>.
//
// eBrevet is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// eBrevet is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with eBrevet.  If not, see <http://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'dart:math';

import 'snackbarglobal.dart';
import 'event.dart';
import 'dart:async';
import 'dart:convert';
import 'files.dart';
import 'exception.dart';
import 'app_settings.dart';
import 'mylogger.dart';
import 'region.dart';
import 'report.dart';
import 'my_settings.dart';
// import 'permanent.dart';

// import 'current.dart';
//
enum ScheduleEventsSourceID {
  fromRegion('US RUSA Region'),
  fromInternationalRegion('International Region'),
  // fromPerm('RUSA Permanent Search'),
  fromURL('Custom Event Data URL');

  final String description;
  const ScheduleEventsSourceID(this.description);

  String toJson() => name;
  static ScheduleEventsSourceID fromJson(String json) => values.byName(json);
  static const ScheduleEventsSourceID defaultID =
      ScheduleEventsSourceID.fromRegion;
}

// One configured event source (intent 0015): a region (US or International,
// with its own region ID) or the custom URL source, which uses the custom URL
// and secret settings.

class ScheduledEventsSource {
  final ScheduleEventsSourceID id;

  /// Region ID (ACP club code) for region sources; null for the custom URL
  /// source. Also null in a legacy cache record, which only stored [id].
  final String? regionID;

  bool get isCustom => id == ScheduleEventsSourceID.fromURL;

  /// Stable identity, used for duplicate checks and to name the cache file.
  /// The US and International categories are two views of the same region
  /// list, so a region ID gives the same key in either.
  String get key => isCustom
      ? 'custom'
      : 'region-${(regionID ?? '').replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

  /// The region this source refers to. A legacy record without a region ID
  /// falls back to the region setting, as before.
  Region get region => Region(regionID: regionID ?? AppSettings.regionID.value);

  /// True for a region source whose ID is not in [Region.regionMap].
  bool get isUnknownRegion =>
      !isCustom &&
      !Region.regionMap.containsKey(regionID ?? AppSettings.regionID.value);

  String get description => id.description;

  /// Short label for the events page region switcher (intent 0017): the
  /// region's short name, "Custom" for the custom URL source, or the region
  /// ID for a region not in [Region.regionMap].
  String get shortLabel {
    if (isCustom) return 'Custom';
    if (isUnknownRegion) return regionID ?? AppSettings.regionID.value;
    return region.regionSubName;
  }

  String get fullDescription {
    return "${id.description}: $subDescription";
  }

  // String get sourceID {
  //   final srcID = id.index.toString();
  //   final rgnID = Region.fromSettings().regionID;
  //   return "$srcID.$rgnID";
  // }

  String get subDescription {
    String d;
    switch (id) {
      case ScheduleEventsSourceID.fromRegion:
      case ScheduleEventsSourceID.fromInternationalRegion:
        var rgn = region;
        d = rgn.regionName;
        break;
      case ScheduleEventsSourceID.fromURL:
        var url = AppSettings.eventInfoURL.value;
        d = "($url)";
        break;
    }
    return d;
  }

  /// The single source described by the old settings
  /// (`scheduleEventsSourceID`, `regionID`). Used for migration only; since
  /// intent 0016 Settings no longer writes these keys.
  factory ScheduledEventsSource.fromSettingsSourceID() {
    var sourceID = AppSettings.scheduleEventsSourceID.value;
    return ScheduledEventsSource(sourceID,
        regionID: sourceID == ScheduleEventsSourceID.fromURL
            ? null
            : AppSettings.regionID.value);
  }

  ScheduledEventsSource(this.id, {this.regionID});

  String get url {
    String eventsURL;
    switch (id) {
      case ScheduleEventsSourceID.fromRegion:
      case ScheduleEventsSourceID.fromInternationalRegion:
        var rgn = region;
        eventsURL = rgn.scheduledEventsURL;
        break;
      case ScheduleEventsSourceID.fromURL:
        eventsURL = AppSettings.eventInfoURL.value;
        break;
    }
    return eventsURL;
  }

  String get secret {
    String secret;
    switch (id) {
      case ScheduleEventsSourceID.fromRegion:
      case ScheduleEventsSourceID.fromInternationalRegion:
        var rgn = region;
        secret = rgn.secret;
        break;
      case ScheduleEventsSourceID.fromURL:
        secret = AppSettings.customRegionSecret.value;
        break;
    }
    return secret;
  }

  ScheduledEventsSource.fromJson(Map<String, dynamic> json)
      : id = ScheduleEventsSourceID.fromJson(json['id']),
        regionID = (json['id'] == ScheduleEventsSourceID.fromURL.name)
            ? null
            : json['region_id'] as String?;

  // 'id' keeps the old format, so an older app version can still read it.
  Map<String, dynamic> toJson() => {
        'id': id.toJson(),
        if (regionID != null) 'region_id': regionID,
      };
}

// The persisted, ordered list of configured event sources and the selected
// one (intent 0015). Stored as JSON through MySetting. The old single-source
// settings keys are never written here, so a downgrade still works.

class EventSources {
  static final MySetting<String> _listSetting = MySetting<String>(
      key: 'key-event-sources', defaultValue: '', title: 'Event Sources');

  static final MySetting<String> _selectedSetting = MySetting<String>(
      key: 'key-selected-event-source',
      defaultValue: '',
      title: 'Selected Event Source');

  static ScheduledEventsSource get defaultSource =>
      ScheduledEventsSource(ScheduleEventsSourceID.fromRegion,
          regionID: Region.defaultRegion);

  static List<ScheduledEventsSource> get defaultList => [defaultSource];

  /// True once a source list has been stored (migration has run).
  static bool get isStored => _listSetting.value.isNotEmpty;

  /// The configured sources, in order. Before migration this is the list
  /// migration would store. Unreadable or invalid stored data gives
  /// [defaultList]; this never throws.
  static List<ScheduledEventsSource> get list {
    if (!isStored) return migratedFromLegacy();
    return decode(_listSetting.value) ?? defaultList;
  }

  /// The one entry described by the old settings: the custom entry for a
  /// custom URL install, otherwise that region (even one no longer in
  /// [Region.regionMap]). A fresh install gives [defaultSource].
  static List<ScheduledEventsSource> migratedFromLegacy() =>
      [ScheduledEventsSource.fromSettingsSourceID()];

  /// Stores the migrated list if no list is stored yet. Returns true if it
  /// did. The old settings keys are left untouched.
  static Future<bool> migrate() async {
    if (isStored) return false;
    final migrated = migratedFromLegacy();
    MyLogger.entry('Migrating event source settings to ${migrated.first.key}');
    await save(migrated);
    return true;
  }

  /// Parses a stored list. Returns null for anything invalid: not JSON, not
  /// a list, a bad entry, or a duplicate.
  static List<ScheduledEventsSource>? decode(String s) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is! List) return null;
      final result = <ScheduledEventsSource>[];
      for (final e in decoded) {
        if (e is! Map<String, dynamic>) return null;
        final source = entryFromJson(e);
        if (source == null || !canAdd(result, source)) return null;
        result.add(source);
      }
      return result;
    } catch (e) {
      MyLogger.entry('Invalid stored event source list: $e',
          severity: Severity.warning);
      return null;
    }
  }

  static ScheduledEventsSource? entryFromJson(Map<String, dynamic> e) {
    final category = e['category'];
    if (category is! String) return null;
    final id = ScheduleEventsSourceID.values.asNameMap()[category];
    if (id == null) return null;
    if (id == ScheduleEventsSourceID.fromURL) return ScheduledEventsSource(id);
    final rid = e['region_id'];
    if (rid is! String || rid.isEmpty) return null;
    return ScheduledEventsSource(id, regionID: rid);
  }

  static Map<String, dynamic> entryToJson(ScheduledEventsSource s) => {
        'category': s.id.name,
        if (!s.isCustom) 'region_id': s.regionID,
      };

  static String encode(List<ScheduledEventsSource> sources) =>
      jsonEncode([for (final s in sources) entryToJson(s)]);

  /// False if [source] is already in [sources] (same [ScheduledEventsSource.key]).
  static bool canAdd(
          List<ScheduledEventsSource> sources, ScheduledEventsSource source) =>
      sources.every((s) => s.key != source.key);

  /// Stores [sources]. Throws [ArgumentError] on a duplicate or on a region
  /// entry without a region ID.
  static Future<void> save(List<ScheduledEventsSource> sources) async {
    final checked = <ScheduledEventsSource>[];
    for (final s in sources) {
      if (!s.isCustom && (s.regionID == null || s.regionID!.isEmpty)) {
        throw ArgumentError('Region source without a region ID');
      }
      if (!canAdd(checked, s)) {
        throw ArgumentError('Duplicate event source ${s.key}');
      }
      checked.add(s);
    }
    await _listSetting.setValue(encode(checked));
  }

  /// Appends [source]. Returns false (and stores nothing) for a duplicate.
  static Future<bool> add(ScheduledEventsSource source) async {
    final sources = list;
    if (!canAdd(sources, source)) return false;
    await save([...sources, source]);
    return true;
  }

  /// The selected source: the stored selection if it is in [list], else
  /// the first source, else (empty list) [defaultSource].
  static ScheduledEventsSource get selected {
    final sources = list;
    if (sources.isEmpty) return defaultSource;
    final key = _selectedSetting.value;
    return sources.firstWhere((s) => s.key == key, orElse: () => sources.first);
  }

  static Future<void> select(ScheduledEventsSource source) =>
      _selectedSetting.setValue(source.key);

  /// Stores [sources] as the new list (intent 0016, region picker). If the
  /// selected source is no longer listed, the first source becomes selected;
  /// otherwise the selection is kept, also on a reorder (intent 0017; the
  /// events page switcher selects explicitly). Every removed source has its cache file and
  /// in-memory cache dropped; other sources' caches are untouched. Throws
  /// [ArgumentError] for an empty list or a duplicate (see [save]).
  static Future<void> update(List<ScheduledEventsSource> sources) async {
    if (sources.isEmpty) {
      throw ArgumentError('At least one event source is required');
    }
    final old = list;
    final oldSelected = selected.key;
    await save(sources);
    final keys = {for (final s in sources) s.key};
    // Store the kept selection explicitly: with no stored selection the
    // first source is selected, and a reorder must not change that.
    final kept = sources.where((s) => s.key == oldSelected);
    await select(kept.isNotEmpty ? kept.first : sources.first);
    for (final s in old) {
      if (!keys.contains(s.key)) await ScheduledEvents.removeSource(s);
    }
  }
}

// This class stores the currently selected event info source
// and provides change notification to anything that cares

class SourceSelection extends ChangeNotifier {
  ScheduledEventsSource eventInfoSource;
  bool _disposed = false;

  SourceSelection() : eventInfoSource = EventSources.selected;

  /// Re-reads the selected source and shows its cached events (loading them
  /// from disk if needed). Other sources' caches are kept.
  Future<void> refresh() async {
    final next = EventSources.selected;
    eventInfoSource = next;
    notifyListeners();
    await ScheduledEvents.ensureLoaded(next);
    if (!_disposed) notifyListeners();
  }

  /// The region picker changed the source list (intent 0016); see
  /// [EventSources.update].
  Future<void> setSources(List<ScheduledEventsSource> sources) async {
    await EventSources.update(sources);
    await refresh();
  }

  /// The rider picked [source] in the events page switcher (intent 0017):
  /// persists the choice and shows that source's cached events, with no
  /// network call. Other sources' caches are untouched.
  Future<void> select(ScheduledEventsSource source) async {
    await EventSources.select(source);
    await refresh();
  }

  /// The custom URL or secret changed: the custom cache may hold another
  /// server's events, so drop it (the custom source only).
  Future<void> customSettingsChanged() async {
    final custom = ScheduledEventsSource(ScheduleEventsSourceID.fromURL);
    if (!EventSources.canAdd(EventSources.list, custom)) {
      ScheduledEvents.clearSource(custom);
    }
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The events, refresh time and origin cached for one source.
class SourceCache {
  var events = <Event>[];
  DateTime? lastRefreshed;
  ScheduledEventsSource? eventInfoSource;

  /// Whether the disk cache has been read (or the cache set) this session.
  bool loaded = false;
}

class ScheduledEvents {
  static final Map<String, SourceCache> _caches = {};

  /// The in-memory cache for [source] (by key), created empty if needed.
  static SourceCache cacheFor(ScheduledEventsSource source) =>
      _caches.putIfAbsent(source.key, SourceCache.new);

  static SourceCache get _selectedCache => cacheFor(EventSources.selected);

  /// Events of the selected source.
  static List<Event> get events => _selectedCache.events;
  static set events(List<Event> list) => _selectedCache
    ..events = list
    ..loaded = true;

  static List<Event> getFilteredEvents(EventFilter filter) {
    final result = events.where((e) => filter.apply(e)).toList();
    result.sort(filter.compare);
    return result;
  }

  /// Where the selected source's cached events came from.
  static ScheduledEventsSource? get eventInfoSource =>
      _selectedCache.eventInfoSource;
  static const eventInfoSourceFieldName = 'event_info_source';

  /// When the selected source was last refreshed from its server.
  static DateTime? get lastRefreshed => _selectedCache.lastRefreshed;
  static const lastRefreshedFieldName = 'last_refreshed';

  /// True if any configured source holds server data (the start-code check
  /// needs an event authority). Does not depend on the selected source.
  static bool get hasEventAuthority =>
      EventSources.list.any((s) => _caches[s.key]?.eventInfoSource != null);

  /// Looks [eventID] up in every configured source's cache, in list order,
  /// independent of the selected source.
  static Event? findEvent(String eventID) {
    for (final s in EventSources.list) {
      for (final e in _caches[s.key]?.events ?? const <Event>[]) {
        if (e.eventID == eventID) return e;
      }
    }
    return null;
  }

  /// The cache written before intent 0015, for one source only.
  static var legacyStoredEvents =
      FileStorage(AppSettings.scheduleEventsFilename);

  /// Prefs flag: the legacy cache was considered for adoption (once).
  static const legacyAdoptedKey = 'key-legacy-events-cache-adopted';

  /// The cache file of [source], named from its stable key.
  static FileStorage storageFor(ScheduledEventsSource source) =>
      FileStorage(AppSettings.scheduleEventsFilenameFor(source.key));

  /// Clears the in-memory and disk cache of [source] only.
  static void clearSource(ScheduledEventsSource source) {
    _caches[source.key] = SourceCache()..loaded = true;
    unawaited(storageFor(source).clear());
  }

  /// Drops the in-memory cache and the cache file of a removed [source]
  /// (intent 0016). Other sources are untouched.
  static Future<void> removeSource(ScheduledEventsSource source) async {
    _caches.remove(source.key);
    await storageFor(source).clear();
  }

  /// Forgets every in-memory cache (tests). Disk files are kept.
  static void resetMemory() => _caches.clear();

  /// At startup: migrates the source settings (adopting the legacy cache
  /// for the migrated source), then loads every configured source's cache.
  /// Returns the selected source's last-refreshed description.
  static Future<String> refreshEventsFromDisk() async {
    if (!EventSources.isStored) {
      await adoptLegacyCache(EventSources.migratedFromLegacy().first);
      await EventSources.migrate();
    }
    var result = 'unknown';
    final selectedKey = EventSources.selected.key;
    for (final s in EventSources.list) {
      final lrs = await loadSourceFromDisk(s);
      if (s.key == selectedKey) result = lrs;
    }
    return result;
  }

  /// Loads [source]'s cache from disk unless already loaded this session.
  static Future<void> ensureLoaded(ScheduledEventsSource source) async {
    if (!cacheFor(source).loaded) await loadSourceFromDisk(source);
  }

  /// Copies the legacy single cache file to [source]'s cache file, once, if
  /// its recorded `event_info_source` matches [source] and [source] has no
  /// cache yet. The legacy file is left in place for a downgrade.
  static Future<bool> adoptLegacyCache(ScheduledEventsSource source) async {
    final prefs = MySetting.prefs;
    if (prefs.getBool(legacyAdoptedKey) == true) return false;
    await prefs.setBool(legacyAdoptedKey, true);

    final legacy = await legacyStoredEvents.readJSON();
    if (legacy.isEmpty) return false;
    final recorded = legacy[eventInfoSourceFieldName];
    if (recorded is! Map<String, dynamic> ||
        !legacySourceMatches(recorded, source)) {
      MyLogger.entry('Legacy event cache is not from ${source.key}; '
          'not adopted.');
      return false;
    }
    final target = storageFor(source);
    if ((await target.readJSON()).isNotEmpty) return false;
    legacy[eventInfoSourceFieldName] = source;
    final ok = await target.writeJSON(legacy);
    MyLogger.entry('Adopted legacy event cache as ${target.fileName}: $ok');
    return ok;
  }

  /// A legacy record has only the category ('id'): it matches a region
  /// source if it names a region category (and the same region ID, if it
  /// has one), and the custom source if it names the custom URL.
  static bool legacySourceMatches(
      Map<String, dynamic> recorded, ScheduledEventsSource source) {
    try {
      final r = ScheduledEventsSource.fromJson(recorded);
      if (r.isCustom != source.isCustom) return false;
      return r.isCustom || r.regionID == null || r.regionID == source.regionID;
    } catch (e) {
      return false;
    }
  }

  static Future<String> loadSourceFromDisk(ScheduledEventsSource source) async {
    final storedEvents = storageFor(source);
    final cache = cacheFor(source);
    cache.loaded = true;
    Map<String, dynamic> eventMapFromFile;
    try {
      MyLogger.entry("** Refreshing events from ${storedEvents.fileName}");

      try {
        eventMapFromFile = await storedEvents.readJSON();
      } catch (e) {
        throw NoPreviousDataException(
            'Cound not read ${storedEvents.fileName} file.');
      }

      var lrs = '';
      if (eventMapFromFile.isNotEmpty) {
        cache.events = parseEventList(eventMapFromFile);

        if (eventMapFromFile.containsKey(lastRefreshedFieldName)) {
          var timestamp = eventMapFromFile[lastRefreshedFieldName];
          lrs = "lastRefreshed = $timestamp";
          cache.lastRefreshed = DateTime.tryParse(timestamp)?.toLocal();
        } else {
          cache.lastRefreshed = null;
          lrs = "Unkown";
        }

        if (eventMapFromFile.containsKey(eventInfoSourceFieldName)) {
          cache.eventInfoSource = ScheduledEventsSource.fromJson(
              eventMapFromFile[eventInfoSourceFieldName]);
        } else {
          cache.eventInfoSource = source;
        }

        MyLogger.entry(
            "Successfully restored ${cache.events.length} events from disk. Last Refreshed = $lrs");
        return lrs;
      } else {
        throw NoPreviousDataException("Future events file read was empty.");
      }
    } catch (error) {
      cache.events = [];
      MyLogger.entry("Couldn't refresh future events from FILE: $error");
      return 'unknown'; // 0;
    }
  }

  static String signJson(Map<String, dynamic> data, String secret) {
    final jsonString = jsonEncode(data);
    final key = utf8.encode(secret);
    final bytes = utf8.encode(jsonString);
    final hmacSha256 = Hmac(sha256, key);
    final digest = hmacSha256.convert(bytes);
    return base64.encode(digest.bytes);
  }

  static bool verifySignature(Map<String, dynamic> payload, String secret) {
    final dataToSign = Map<String, dynamic>.from(payload)..remove("signature");
    return signJson(dataToSign, secret) == payload["signature"];
  }

  static String generateNonce([int length = 16]) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<bool> refreshScheduledEventsFromServer(
      ScheduledEventsSource scheduleEventsSource, BuildContext context) async {
    try {
      await refreshSource(scheduleEventsSource);
    } on CueWizardException catch (error) {
      if (context.mounted) {
        // Deliberately not awaited: refresh finishes without waiting for the
        // rider to dismiss the dialog.
        unawaited(cueWizardErrorDialog(error, scheduleEventsSource, context));
      }
    } catch (error) {
      if (error is IncompatibleVersionException) {
        if (context.mounted) {
          // Deliberately not awaited, as above.
          unawaited(versionErrorDialog(error, scheduleEventsSource, context));
        }
        cacheFor(scheduleEventsSource).events = [];
      } else {
        AppSnack.show(error.toString(), style: AppSnackStyle.error);
      }
      MyLogger.entry("Error refreshing events: $error");

      return false;
    }
    return true;
  }

  /// Fetches, verifies and caches the feed of [scheduleEventsSource] only,
  /// with that source's URL and secret. Throws on any failure, leaving the
  /// source's cache unchanged. Other sources' caches are never touched.
  static Future<void> refreshSource(
      ScheduledEventsSource scheduleEventsSource) async {
    if (scheduleEventsSource.isUnknownRegion) {
      throw ServerException('Unknown region ${scheduleEventsSource.regionID}. '
          'Try getting the latest region list.');
    }
    MyLogger.entry(
        "Refreshing events from SERVER for ${scheduleEventsSource.description} with"
        " URL ${scheduleEventsSource.url}");

    // Then try to fetch from the server in background with callback to process
    // Note that we add a nonce to the URL

    String sourceURL = "";
    bool authenticating = true;
    String txNonce = 'nononce';
    String authSecret = '';

    if (AppSettings.authenticateEventsData.value) {
      txNonce = generateNonce();
      sourceURL = "${scheduleEventsSource.url}/$txNonce";
      authSecret = scheduleEventsSource.secret;
    } else {
      sourceURL = scheduleEventsSource.url;
      authenticating = false;
    }

    var eventMapFromServer = await fetchScheduledEventsFromServer(sourceURL);
    if (null == eventMapFromServer) {
      throw ServerException('No event data from $sourceURL');
    }

    // Verify signature

    // If the region was selected from the internal list of regions,
    // the associated region secret is in the Region object
    // But if the Event Info Source was a custom URL, then
    // the secret must be obtained from the settings
    // Presumably the sc

    String rxSignature = eventMapFromServer['signature'] ?? '';
    String rxNonce = eventMapFromServer['nonce'] ?? '';

    if (authenticating && (rxNonce != txNonce)) {
      throw ServerException('Nonce mismatch: TX: "$txNonce"; RX: "$rxNonce"');
    }

    if (authenticating &&
        (false == verifySignature(eventMapFromServer, authSecret))) {
      MyLogger.entry(
          severity: Severity.hidden,
          "Bad signature assuming secret = '${maskSecondHalf(authSecret)}'");
      throw ServerException('Signature invalid RX: $rxSignature');
    }

    if (authenticating) {
      MyLogger.entry(
          'Received scheduled events map for Nonce="$rxNonce"; with valid Signature="$rxSignature"');
    }

    final newEvents = parseEventList(eventMapFromServer);
    var now = DateTime.now();
    eventMapFromServer[lastRefreshedFieldName] = now.toUtc().toIso8601String();
    eventMapFromServer[eventInfoSourceFieldName] = scheduleEventsSource;
    var writeStatus = await storageFor(scheduleEventsSource)
        .writeJSON(eventMapFromServer); // Save what we just downloaded to disk
    cacheFor(scheduleEventsSource)
      ..events = newEvents
      ..lastRefreshed = now
      ..eventInfoSource = scheduleEventsSource
      ..loaded = true;

    // refreshCount.value++;
    MyLogger.entry("Refresh complete. Write status: $writeStatus");
  }

  static String maskSecondHalf(String s) {
    final halfLength = s.length ~/ 2; // integer division
    final firstHalf = s.substring(0, halfLength);
    final masked = firstHalf.padRight(s.length, '*');
    return masked;
  }

  static Future<bool?> versionErrorDialog(IncompatibleVersionException error,
          ScheduledEventsSource scheduledEventsSource, BuildContext context) =>
      showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) {
            return AlertDialog(
              icon: const Icon(Icons.error, size: 62.0),
              title: const Text('Incompatible App Version'),
              content: Text(
                  "You have version ${error.actual} of this app installed, "
                  "but the ${scheduledEventsSource.fullDescription} event data server requires "
                  "version ${error.required} or newer. Please update this app to the latest version."),
              actions: [
                // The "Yes" button
                TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(true);
                    },
                    child: const Text('Continue'))
              ],
            );
          });

  static Future<bool?> cueWizardErrorDialog(CueWizardException e,
          ScheduledEventsSource scheduledEventsSource, BuildContext context) =>
      showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) {
            return AlertDialog(
              icon: const Icon(Icons.error, size: 62.0),
              title: const Text('Route Data Errors'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text("Errors/Warnings found in event data retrieved from "
                        "the ${scheduledEventsSource.fullDescription}. "),
                    Text(
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium!
                            .copyWith(fontStyle: FontStyle.italic),
                        "The event organizer should use the Route Manager to explore/fix these problems before publishing events."),
                    for (var errorMessage in e.errorList)
                      Container(
                          color: Theme.of(context).colorScheme.errorContainer,
                          margin: const EdgeInsets.all(4),
                          padding: const EdgeInsets.all(8),
                          child: Text(errorMessage)),
                  ],
                ),
              ),
              actions: [
                // The "Yes" button
                TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(true);
                    },
                    child: const Text('Continue'))
              ],
            );
          });

  // Behavior assumed for the server is that it will send all future events
  // and some number of past events -- perhaps back a year, or at least
  // several months.  We will put all these events into our list unless they
  // are too old (set by AppSettings.keepPastEventMonths.value) which
  // should be set similarly to the server

  // the getFilteredEvents() method, above,  will take care of filtering
  // out past or future events.

  // the preferred URL for this will be 'ebrevet/scheduled_events' with
  // the previous 'ebrevet/future_events' depreciated.

  static List<Event> parseEventList(Map eventMap) {
    List el = eventMap['event_list'];
    MyLogger.entry("Start parseEventList() from ${el.length} events in Map");
    final events = <Event>[];
    for (var e in el) {
      var eventToAdd = Event.fromJson(e);

      if (eventToAdd.valid == false) {
        throw const FormatException('Invalid event data found.');
      }

      if (eventToAdd.cueVersion <= 0) {
        MyLogger.entry("Ignoring event with no cue sheet.");
        continue;
      }

      if (eventToAdd.startDateTime == null) {
        events.add(eventToAdd); // Permanent
      } else {
        var now = DateTime.now();
        var months = AppSettings.keepPastEventMonths.value;
        var days = ((365.25 / 12.0) * months).round();
        var yearsDuration = Duration(days: days);
        var eventTooOld =
            eventToAdd.startDateTime!.add(yearsDuration).isBefore(now);
        if (!eventTooOld) {
          events.add(eventToAdd);
        } else {
          MyLogger.entry(
              "Ignoring past event older than $months months:  ${eventToAdd.name} ${eventToAdd.distance}K on ${eventToAdd.startTimeWindow.onTime.toString()}");
        }
      }
    }
    events.sort(Event.sort);
    // rider = r;
    var n = events.length;
    MyLogger.entry("Event List rebuilt with $n events.");
    return events;
  }

  static Future<Map<String, dynamic>?> fetchScheduledEventsFromServer(
      String url) async {
    String responseBody = await Report.fetchResponseFromServer(url);
    Map<String, dynamic> decodedResponse = jsonDecode(responseBody);

    if (decodedResponse is List && decodedResponse.isEmpty) {
      throw ServerException('Empty reponse from $url');
    }
    if (false == decodedResponse.containsKey('minimum_app_version')) {
      throw ServerException('Missing app version value in response from $url');
    }

    String minimumAppVersion = decodedResponse['minimum_app_version'];

    if (isIncompatibleAppVersion(minimumAppVersion)) {
      throw IncompatibleVersionException(
          actual: AppSettings.version ?? 'unknown',
          required: minimumAppVersion);
    }

    if (false == decodedResponse.containsKey('event_list')) {
      throw ServerException('No event_list key in response from $url');
    }

    if (true == decodedResponse.containsKey('event_errors') &&
        (decodedResponse['event_errors'] as List).isNotEmpty) {
      List<String> eventErrors =
          List<String>.from(decodedResponse['event_errors'] as List);
      throw CueWizardException(eventErrors);
    }

    return decodedResponse;
  }

  static const numberOfSubversions = 3;
  static final versionPattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');

  static bool isIncompatibleAppVersion(String minimumAppVersion) {
    final myVersion = AppSettings.version ?? '0.0.0';

    RegExpMatch? myVersionMatch = versionPattern.firstMatch(myVersion);
    assert(myVersionMatch != null);

    RegExpMatch? minimumAppVersionMatch =
        versionPattern.firstMatch(minimumAppVersion);

    if (minimumAppVersionMatch == null && myVersionMatch != null) {
      throw ServerException(
          'Empty or invalid app version value in response from server.');
    } else {
      for (var i = 1; i <= numberOfSubversions; i++) {
        var required = int.parse(minimumAppVersionMatch!.group(i)!);
        var mine = int.parse(myVersionMatch!.group(i)!);
        if (mine < required) {
          return true;
        }
        if (mine > required) {
          return false;
        }
      }
      return false;
    }

    // return false;
  }

  static String get lastRefreshedStr {
    if (lastRefreshed == null) {
      return 'Never';
    } else {
      return lastRefreshed.toString().substring(0, 16);
    }
  }

  static String get lastRefreshedSince {
    if (lastRefreshed == null) {
      return 'Never';
    } else {
      var since = DateTime.now().difference(lastRefreshed!);
      return since.toString();
    }
  }
}
