import 'dart:convert';

import 'package:ebrevet_card/mock/mock_server.dart';
import 'package:ebrevet_card/route_map.dart';
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fixtures.dart';

void main() {
  setUp(useMockServerForTests);

  group('MockServer scheduled events feed', () {
    test('is signed so the app signature check passes', () async {
      final feed = await MockServer.scheduledEvents(nonce: 'abc123');
      expect(feed['nonce'], 'abc123');
      expect(ScheduledEvents.verifySignature(feed, 'ci-dummy-secret'), isTrue);
      expect(ScheduledEvents.verifySignature(feed, 'wrong-secret'), isFalse);
    });

    test('first event started 20 minutes ago, others start on later days',
        () async {
      final feed = await MockServer.scheduledEvents();
      final events = (feed['event_list'] as List).cast<Map<String, dynamic>>();
      expect(events, isNotEmpty);
      expect(DateTime.parse(events[0]['start_datetime_utc']),
          testNow.subtract(const Duration(minutes: 20)));
      expect(DateTime.parse(events[1]['start_datetime_utc']),
          testNow.add(const Duration(days: 1)));
    });

    test('control windows move with the event start', () async {
      final feed = await MockServer.scheduledEvents();
      final e = (feed['event_list'] as List)[0] as Map<String, dynamic>;
      final start = DateTime.parse(e['start_datetime_utc']);
      final controls = (e['controls'] as List).cast<Map<String, dynamic>>();
      final firstOpen = DateTime.parse(controls[0]['open']);
      expect(firstOpen, start); // start control opens at the start time
    });

    test('every event parses with the real Event model', () async {
      final events = await mockEvents();
      expect(events.every((e) => e.valid), isTrue);
      expect(events.every((e) => e.controls.length >= 2), isTrue);
      expect(events.first.checkinPostURL, MockServer.checkinPostURL);
    });
  });

  group('MockServer routing', () {
    test('GET scheduled_events with nonce is routed and signed', () async {
      final r = await MockServer.handle(http.Request(
          'GET',
          Uri.parse(
              'https://randonneuring.org/ebrevet/scheduled_events/938017/n0nce')));
      expect(r.statusCode, 200);
      expect((jsonDecode(r.body) as Map<String, dynamic>)['nonce'], 'n0nce');
    });

    test('region list has the shape Region.fetchRegionsFromServer expects',
        () async {
      final r = await MockServer.handle(http.Request(
          'GET', Uri.parse('https://randonneuring.org/ebrevet/region_list')));
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      expect(DateTime.tryParse(body['timestamp']), isNotNull);
      final regions =
          (body['region_list'] as List).cast<Map<String, dynamic>>();
      expect(regions.first['club_acp_code'], isNotNull);
    });

    test('check-in POST is captured and answered OK, never sent anywhere',
        () async {
      final req = http.Request('POST', Uri.parse(MockServer.checkinPostURL))
        ..body = jsonEncode({'event_id': '938017-382', 'rider_id': '1234'});
      final r = await MockServer.handle(req);
      expect((jsonDecode(r.body) as Map<String, dynamic>)['status'], 'OK');
      expect(MockServer.receivedReports.single['rider_id'], '1234');
    });

    test('unknown URLs are 404, not forwarded', () async {
      final r = await MockServer.handle(
          http.Request('GET', Uri.parse('https://example.com/whatever')));
      expect(r.statusCode, 404);
    });
  });

  // AC10 (intent 0010): map tile GETs pass through, nothing else does.
  group('MockServer tile pass-through', () {
    late List<http.BaseRequest> forwarded;

    setUp(() {
      forwarded = [];
      // Fake "real" client: records what would have gone to the network.
      MockServer.passthrough = MockClient((req) async {
        forwarded.add(req);
        return http.Response.bytes([1, 2, 3], 200,
            headers: {'content-type': 'image/png'});
      });
    });

    tearDown(() => MockServer.passthrough = null);

    final tileUrl = Uri.parse(RouteMap.tileUrlTemplate
        .replaceAll('{z}', '9')
        .replaceAll('{x}', '146')
        .replaceAll('{y}', '193'));

    test('tile host is taken from the tile URL constant', () {
      expect(RouteMap.tileHost, 'tile.openstreetmap.org');
      expect(tileUrl.host, RouteMap.tileHost);
    });

    test('GET to the tile host goes to the passthrough client', () async {
      final r = await MockServer.handle(http.Request('GET', tileUrl)
        ..headers['User-Agent'] = 'flutter_map (test)');
      expect(r.statusCode, 200);
      expect(r.bodyBytes, [1, 2, 3]);
      expect(forwarded.single.method, 'GET');
      expect(forwarded.single.url, tileUrl);
      expect(forwarded.single.headers['User-Agent'], 'flutter_map (test)');
    });

    // AC10 + AC12 (intent 0010): check-in reports are never sent anywhere
    // real, even if addressed to the tile host.
    test('POST to the tile host is not passed through', () async {
      final req = http.Request('POST', tileUrl)
        ..body = jsonEncode({'event_id': '938017-382', 'rider_id': '1234'});
      final r = await MockServer.handle(req);
      expect(forwarded, isEmpty);
      expect((jsonDecode(r.body) as Map<String, dynamic>)['mock'], isTrue);
    });

    test('other hosts are still answered by the mock', () async {
      final feed = await MockServer.handle(http.Request(
          'GET',
          Uri.parse(
              'https://randonneuring.org/ebrevet/scheduled_events/938017/n0nce')));
      expect(feed.statusCode, 200);
      expect((jsonDecode(feed.body) as Map<String, dynamic>)['nonce'], 'n0nce');

      final unknown = await MockServer.handle(
          http.Request('GET', Uri.parse('https://example.com/9/146/193.png')));
      expect(unknown.statusCode, 404);

      // A look-alike host is not the tile host.
      final lookalike = await MockServer.handle(http.Request(
          'GET', Uri.parse('https://tile.openstreetmap.org.evil.test/1.png')));
      expect(lookalike.statusCode, 404);

      final checkin = await MockServer.handle(
          http.Request('POST', Uri.parse(MockServer.checkinPostURL))
            ..body = jsonEncode({'rider_id': '1234'}));
      expect(
          (jsonDecode(checkin.body) as Map<String, dynamic>)['status'], 'OK');
      expect(forwarded, isEmpty);
    });
  });
}
