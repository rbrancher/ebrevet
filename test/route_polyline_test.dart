// Feed route field and hand-written polyline decoder (intent 0014).

import 'dart:convert';
import 'dart:io';

import 'package:ebrevet_card/activated_event.dart';
import 'package:ebrevet_card/event.dart';
import 'package:ebrevet_card/mock/mock_server.dart';
import 'package:ebrevet_card/route_geometry.dart';
import 'package:ebrevet_card/route_polyline.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

const googleExample = r'_p~iF~ps|U_ulLnnqC_mqNvxq`@';
const googleExamplePoints = [
  LatLong(38.5, -120.2),
  LatLong(40.7, -120.95),
  LatLong(43.252, -126.453),
];

void main() {
  // AC2 (intent 0014)
  group('RoutePolyline.decode', () {
    test('Google documentation example', () {
      expect(RoutePolyline.decode(googleExample), googleExamplePoints);
      expect(RoutePolyline.encode(googleExamplePoints), googleExample);
    });

    test('negative deltas on both axes round-trip', () {
      const points = [
        LatLong(40.00342, -75.19768),
        LatLong(39.94699, -75.18699), // lat falls, long rises
        LatLong(39.78859, -75.69697), // both fall
        LatLong(-33.86882, 151.20929), // across the equator and meridian
        LatLong(-34.0, 150.5),
      ];
      final encoded = RoutePolyline.encode(points);
      expect(RoutePolyline.decode(encoded), points);
    });

    test('empty, non-string and null give no route', () {
      expect(RoutePolyline.decode(''), isNull);
      expect(RoutePolyline.decode(null), isNull);
      expect(RoutePolyline.decode(123), isNull);
      expect(RoutePolyline.decode(['_p~iF']), isNull);
    });

    test('truncated or garbage input gives no route, never throws', () {
      for (final s in [
        googleExample.substring(0, googleExample.length - 1), // mid value
        googleExample.substring(0, 5), // a latitude without its longitude
        '_p~iF~ps|U_ulL', // odd number of values
        'hello world', // space is outside the alphabet
        '!!!!',
        '_p~iF~ps|Uéé', // non-ASCII
        '~~~~~~~~~~~~~~~~?', // endless continuation chunks
        '````',
      ]) {
        expect(() => RoutePolyline.decode(s), returnsNormally, reason: s);
        expect(RoutePolyline.decode(s), isNull, reason: s);
      }
    });

    test('points outside valid lat/long, or fewer than 2, give no route', () {
      expect(
          RoutePolyline.decode(
              RoutePolyline.encode(const [LatLong(40, -75), LatLong(95, -75)])),
          isNull);
      expect(
          RoutePolyline.decode(RoutePolyline.encode(
              const [LatLong(40, -75), LatLong(40, -181)])),
          isNull);
      expect(
          RoutePolyline.decode(RoutePolyline.encode(const [LatLong(40, -75)])),
          isNull);
      expect(RoutePolyline.decode('_p~iF~ps|U'), isNull); // one point
    });

    test('no new dependency: the decoder is hand-written', () {
      final src = File('lib/route_polyline.dart').readAsStringSync();
      expect(src, isNot(contains('package:')));
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('polyline')));
    });
  });

  Future<Map<String, dynamic>> baseJson() async {
    final feed = await MockServer.scheduledEvents();
    // An event without a feed route in the fixture.
    return (feed['event_list'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((e) => e['route_polyline'] == null);
  }

  Map<String, dynamic> copy(Map<String, dynamic> json) =>
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

  // AC1 (intent 0014)
  group('Event route_polyline', () {
    setUp(useMockServerForTests);

    test('a good polyline is decoded', () async {
      final json = copy(await baseJson())..['route_polyline'] = googleExample;
      final e = Event.fromJson(json);
      expect(e.valid, isTrue);
      expect(e.route, googleExamplePoints);
    });

    test('absent, null, non-string or malformed: no route, rest unchanged',
        () async {
      final base = await baseJson();
      final plain = Event.fromJson(copy(base));
      expect(plain.route, isNull);
      for (final value in <Object?>[
        null,
        42,
        {'a': 1},
        ['x'],
        '',
        'garbage!',
        googleExample.substring(0, 10),
      ]) {
        final json = copy(base)..['route_polyline'] = value;
        late Event e;
        expect(() => e = Event.fromJson(json), returnsNormally,
            reason: '$value');
        expect(e.valid, isTrue);
        expect(e.route, isNull, reason: '$value');
        expect(e.toJson, plain.toJson, reason: '$value');
        expect(e.controls.length, plain.controls.length);
      }
    });

    test('fixture events with a feed route decode it', () async {
      final events = await mockEvents();
      expect(events.where((e) => e.route != null), isNotEmpty);
      expect(events.where((e) => e.route == null), isNotEmpty);
    });
  });

  // AC3 (intent 0014): the decoded route is never saved.
  group('persisted state unchanged', () {
    setUp(useMockServerForTests);

    test('toJson has no route key and the same keys as before', () async {
      final base = await baseJson();
      final without = Event.fromJson(copy(base));
      final withRoute =
          Event.fromJson(copy(base)..['route_polyline'] = googleExample);
      expect(withRoute.route, isNotNull);
      final saved = withRoute.toJson;
      expect(saved.keys.toSet(), without.toJson.keys.toSet());
      expect(saved.keys.where((k) => k.contains('route')), isEmpty);
      expect(jsonEncode(saved), jsonEncode(without.toJson));
    });

    test('round trip keeps every existing field; ride restores', () async {
      final base = await baseJson();
      final event =
          Event.fromJson(copy(base)..['route_polyline'] = googleExample);
      final restored = Event.fromJson(copy(event.toJson));
      expect(jsonEncode(restored.toJson), jsonEncode(event.toJson));
      expect(restored.route, isNull);

      final ride = fixtureRide(event, km: 200);
      final json =
          jsonDecode(jsonEncode(ride.toJson())) as Map<String, dynamic>;
      final back = ActivatedEvent.fromJson(json);
      expect(jsonEncode(back.toJson()), jsonEncode(ride.toJson()));
    });
  });
}
