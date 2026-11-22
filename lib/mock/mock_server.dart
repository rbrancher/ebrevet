// Fake eBrevet server for mock mode (web previews, tests).
//
// Installed with http.runWithClient in main.dart, so all existing
// http.get / http.post calls are routed here without code changes.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../activated_event.dart';
import '../app_settings.dart';
import '../event.dart';
import '../files.dart';
import '../outcome.dart';
import '../region.dart';
import '../route_geometry.dart';
import '../route_map.dart';
import '../route_polyline.dart';
import '../route_service.dart';
import '../scheduled_events.dart';

class MockServer {
  static const fixtureAsset = 'assets/mock/future_events.json';
  static const checkinPostURL = 'https://mock.ebrevet.invalid/checkin';

  /// Every check-in report POSTed in this session (newest last).
  static final List<Map<String, dynamic>> receivedReports = [];

  /// Override the fixture (tests). Defaults to loading [fixtureAsset].
  static Future<String> Function() loadFixture =
      () => rootBundle.loadString(fixtureAsset);

  /// Secret used to sign event feeds. Defaults to the secret the app
  /// will verify with, so the signature check passes.
  static String Function() signingSecret =
      () => ScheduledEventsSource.fromSettingsSourceID().secret;

  /// Clock, overridable in tests.
  static DateTime Function() now = DateTime.now;

  /// Real client for same-origin requests (e.g. package_info_plus fetching
  /// version.json on web) and map tile GETs. Must be created outside
  /// http.runWithClient.
  static http.Client? passthrough;

  static http.Client client() => MockClient(handle);

  static bool _isSameOrigin(Uri url) =>
      Uri.base.hasScheme &&
      Uri.base.scheme.startsWith('http') &&
      url.origin == Uri.base.origin;

  /// Read-only map tile requests (intent 0010): GET to the host of
  /// [RouteMap.tileUrlTemplate] only.
  static bool _isTileGet(http.Request request) =>
      request.method == 'GET' && request.url.host == RouteMap.tileHost;

  static Future<http.Response> handle(http.Request request) async {
    final path = request.url.pathSegments;
    if (passthrough != null &&
        (_isSameOrigin(request.url) || _isTileGet(request))) {
      // The handler's request is already finalized; send a fresh copy.
      final copy = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = request.bodyBytes;
      return http.Response.fromStream(await passthrough!.send(copy));
    }
    try {
      if (request.url.host == RouteService.routerHost) {
        // Never passed to the real router (intent 0014).
        return _json(await routerResponse(request.url));
      }
      if (request.method == 'POST') {
        return _checkin(request);
      }
      if (path.contains('region_list')) {
        return _json(_regionList());
      }
      final i = path.indexOf('scheduled_events');
      if (i >= 0) {
        // .../scheduled_events/<regionID>[/<nonce>]
        final nonce = (path.length > i + 2) ? path[i + 2] : null;
        return _json(await scheduledEvents(nonce: nonce));
      }
      return http.Response('Not found in mock server: ${request.url}', 404);
    } catch (e) {
      return http.Response('Mock server error: $e', 500);
    }
  }

  static http.Response _json(Object body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  static http.Response _checkin(http.Request request) {
    final report = jsonDecode(request.body) as Map<String, dynamic>;
    receivedReports.add(report);
    return _json({'status': 'OK', 'mock': true});
  }

  /// Fixture event the mock router finds no route for, so previews also
  /// show the straight-line case (intent 0014).
  static const unroutableEventID = '938017-402';

  /// Canned OSRM-style answer for a router request [url]: a road-like
  /// line that wiggles between the requested coordinates, or `NoRoute`
  /// for the controls of [unroutableEventID] or a malformed request.
  static Future<Map<String, dynamic>> routerResponse(Uri url) async {
    final noRoute = {'code': 'NoRoute', 'routes': <Object>[]};
    final coords = <LatLong>[];
    for (final pair in url.pathSegments.last.split(';')) {
      final xy = pair.split(',');
      final long = double.tryParse(xy.first);
      final lat = xy.length == 2 ? double.tryParse(xy.last) : null;
      if (long == null || lat == null) return noRoute;
      coords.add(LatLong(lat, long));
    }
    if (coords.length < 2) return noRoute;

    final fixture = jsonDecode(await loadFixture()) as Map<String, dynamic>;
    for (final e in (fixture['event_list'] as List).cast<Map>()) {
      if (e['event_id'] != unroutableEventID) continue;
      final first = (e['controls'] as List).first as Map;
      final start = LatLong(
          (first['lat'] as num).toDouble(), (first['long'] as num).toDouble());
      if (RouteGeometry.groundDistance(coords.first, start) < 1) {
        return noRoute;
      }
    }
    return {
      'code': 'Ok',
      'routes': [
        {'geometry': RoutePolyline.encode(cannedRoute(coords))}
      ],
    };
  }

  /// Through every point of [coords], with 4 points between each pair
  /// offset alternately to each side by up to 4% of the segment.
  static List<LatLong> cannedRoute(List<LatLong> coords) {
    final out = <LatLong>[coords.first];
    for (var i = 1; i < coords.length; i++) {
      final a = coords[i - 1], b = coords[i];
      final dLat = b.lat - a.lat, dLong = b.long - a.long;
      for (var k = 1; k <= 4; k++) {
        final t = k / 5;
        final side = (k.isOdd ? 1 : -1) * 0.04;
        out.add(LatLong(
            a.lat + dLat * t - dLong * side, a.long + dLong * t + dLat * side));
      }
      out.add(b);
    }
    return out;
  }

  static Map<String, dynamic> _regionList() => {
        'timestamp': now().toUtc().toIso8601String(),
        'region_list': [
          for (final e in Region.regionMap.entries)
            {...e.value, 'club_acp_code': e.key},
        ],
      };

  /// The signed scheduled-events feed, with the fixture's dates moved so the
  /// first event started 20 minutes ago and event i starts i days from now.
  static Future<Map<String, dynamic>> scheduledEvents({String? nonce}) async {
    final fixture = jsonDecode(await loadFixture()) as Map<String, dynamic>;
    final events = (fixture['event_list'] as List).cast<Map<String, dynamic>>();
    final t0 = now().toUtc();

    final shifted = <Map<String, dynamic>>[];
    for (var i = 0; i < events.length; i++) {
      final target = (i == 0)
          ? t0.subtract(const Duration(minutes: 20))
          : t0.add(Duration(days: i));
      shifted.add(shiftEvent(events[i], target));
    }

    final feed = <String, dynamic>{
      'minimum_app_version': '0.0.0',
      'event_list': shifted,
      'event_errors': <String>[],
      'nonce': nonce ?? 'nononce',
      'timestamp': t0.toIso8601String(),
    };
    feed['signature'] = ScheduledEvents.signJson(feed, signingSecret());
    return feed;
  }

  /// Rider ID of the demo rider set up in mock mode (main.dart).
  static const demoRiderID = '12345';

  /// Past rides for the demo rider, so mock-mode previews show non-zero
  /// profile stats (intent 0006). Built from the fixture, re-dated into the
  /// past with a "-demo" event ID: finished 200 (twice, one a pre-ride),
  /// 300 and 400 km rides, plus a DNF on the 600.
  static Future<Map<String, ActivatedEvent>> demoRides() async {
    final fixture = jsonDecode(await loadFixture()) as Map<String, dynamic>;
    final events = (fixture['event_list'] as List).cast<Map<String, dynamic>>();
    final t0 = now().toUtc();
    // [fixture index, days ago, outcome, start style]
    final plan = [
      [2, 30, OverallOutcome.finish, StartStyle.massStart], // 200
      [4, 45, OverallOutcome.finish, StartStyle.preRide], // 200
      [0, 60, OverallOutcome.finish, StartStyle.massStart], // 300
      [1, 90, OverallOutcome.finish, StartStyle.massStart], // 400
      [3, 120, OverallOutcome.dnf, StartStyle.massStart], // 600
    ];
    final rides = <String, ActivatedEvent>{};
    for (final p in plan) {
      final json = shiftEvent(
          events[p[0] as int], t0.subtract(Duration(days: p[1] as int)));
      json['event_id'] = '${json['event_id']}-demo';
      final event = Event.fromJson(json);
      final outcome = p[2] as OverallOutcome;
      final outcomes = EventOutcomes(overallOutcome: outcome);
      final checked = outcome == OverallOutcome.finish
          ? event.controls
          : event.controls.take(2);
      for (final c in checked) {
        outcomes.setControlCheckInTime(c.index, c.open);
      }
      rides[event.eventID] =
          ActivatedEvent(event, demoRiderID, outcomes, p[3] as StartStyle);
    }
    return rides;
  }

  /// Adds [demoRides] missing from the saved ride history. Called only in
  /// mock mode, before the history is loaded. Saved rides are kept.
  static Future<void> seedDemoRides() async {
    final storage = FileStorage(AppSettings.pastEventsFileName);
    final saved = await storage.readJSON();
    var added = false;
    for (final e in (await demoRides()).entries) {
      if (!saved.containsKey(e.key)) {
        saved[e.key] = e.value.toJson();
        added = true;
      }
    }
    if (added) await storage.writeJSON(saved);
  }

  /// Copy [event] so it starts at [newStart], moving every control window by
  /// the same offset, and fill fields the legacy fixture lacks.
  static Map<String, dynamic> shiftEvent(
      Map<String, dynamic> event, DateTime newStart) {
    final e = jsonDecode(jsonEncode(event)) as Map<String, dynamic>;
    final oldStart = DateTime.parse(e['start_datetime_utc']);
    final delta = newStart.difference(oldStart);
    String move(String iso) =>
        DateTime.parse(iso).add(delta).toUtc().toIso8601String();

    e['start_datetime_utc'] = move(e['start_datetime_utc']);
    if (e['end_datetime_utc'] != null) {
      e['end_datetime_utc'] = move(e['end_datetime_utc']);
    }
    final local = newStart.toLocal();
    e['start_datetime_at_event'] =
        '${local.toIso8601String().substring(0, 16).replaceFirst('T', ' ')} ${local.timeZoneName}';
    for (final c in (e['controls'] as List).cast<Map<String, dynamic>>()) {
      c['open'] = move(c['open']);
      c['close'] = move(c['close']);
    }
    e['gravel_distance'] ??= '0';
    e['checkin_post_url'] = checkinPostURL;
    e['name'] = '[MOCK] ${(e['name'] as String).trim()}';
    return e;
  }
}
