import 'dart:convert';

import 'package:ebrevet_card/mock/mock_server.dart';
import 'package:ebrevet_card/scheduled_events.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

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
      final events = feed['event_list'] as List;
      expect(events, isNotEmpty);
      expect(DateTime.parse(events[0]['start_datetime_utc']),
          testNow.subtract(const Duration(minutes: 20)));
      expect(DateTime.parse(events[1]['start_datetime_utc']),
          testNow.add(const Duration(days: 1)));
    });

    test('control windows move with the event start', () async {
      final feed = await MockServer.scheduledEvents();
      final e = (feed['event_list'] as List)[0];
      final start = DateTime.parse(e['start_datetime_utc']);
      final firstOpen = DateTime.parse(e['controls'][0]['open']);
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
      final r = await MockServer.handle(http.Request('GET',
          Uri.parse('https://randonneuring.org/ebrevet/scheduled_events/938017/n0nce')));
      expect(r.statusCode, 200);
      expect(jsonDecode(r.body)['nonce'], 'n0nce');
    });

    test('region list has the shape Region.fetchRegionsFromServer expects',
        () async {
      final r = await MockServer.handle(http.Request(
          'GET', Uri.parse('https://randonneuring.org/ebrevet/region_list')));
      final body = jsonDecode(r.body);
      expect(DateTime.tryParse(body['timestamp']), isNotNull);
      expect((body['region_list'] as List).first['club_acp_code'], isNotNull);
    });

    test('check-in POST is captured and answered OK, never sent anywhere',
        () async {
      final req = http.Request('POST', Uri.parse(MockServer.checkinPostURL))
        ..body = jsonEncode({'event_id': '938017-382', 'rider_id': '1234'});
      final r = await MockServer.handle(req);
      expect(jsonDecode(r.body)['status'], 'OK');
      expect(MockServer.receivedReports.single['rider_id'], '1234');
    });

    test('unknown URLs are 404, not forwarded', () async {
      final r = await MockServer.handle(
          http.Request('GET', Uri.parse('https://example.com/whatever')));
      expect(r.statusCode, 404);
    });
  });
}
