// Router seam for the full-screen map's road route (intent 0014). Every
// request here goes to a fake client or a fake service, never the network.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ebrevet_card/route_geometry.dart';
import 'package:ebrevet_card/route_map.dart';
import 'package:ebrevet_card/route_polyline.dart';
import 'package:ebrevet_card/route_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_route_service.dart';
import 'support/fixtures.dart';

const controls = [
  LatLong(40.0034216, -75.1976835),
  LatLong(40.37533, -75.0305),
  LatLong(40.9862789, -75.1439695),
];

String okBody(List<LatLong> points) => jsonEncode({
      'code': 'Ok',
      'routes': [
        {'geometry': RoutePolyline.encode(points), 'distance': 1234.5}
      ],
    });

void main() {
  tearDown(RouteService.cache.clear);

  // AC5 (intent 0014)
  group('RouteService seam', () {
    test('endpoint is one cycling constant; timeout at most 10 s', () {
      expect(RouteService.endpoint, startsWith('https://'));
      expect(RouteService.endpoint, contains('bike'));
      expect(RouteService.routerHost, Uri.parse(RouteService.endpoint).host);
      expect(
          RouteService.timeout, lessThanOrEqualTo(const Duration(seconds: 10)));
      expect(RouteService.userAgent, contains(RouteMap.userAgentPackageName));
      final src = File('lib/route_service.dart').readAsStringSync();
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(RegExp('https?://').allMatches(code).length, 1,
          reason: 'the router URL appears only in the endpoint constant');
      expect(src, isNot(contains('http.post')));
      expect(src, contains('swap'));
    });

    test('default fetch is one read-only GET with a user agent', () async {
      final seen = <http.Request>[];
      final route = await http.runWithClient(
          () => RouteService().fetchRoute(controls),
          () => MockClient((req) async {
                seen.add(req);
                return http.Response(
                    okBody(FakeRouteService.wiggle(controls)), 200);
              }));
      expect(seen, hasLength(1));
      expect(seen.single.method, 'GET');
      expect(seen.single.url, RouteService.requestUrl(controls));
      expect(seen.single.body, isEmpty);
      expect(seen.single.headers['User-Agent'], RouteService.userAgent);
      expect(route, hasLength(5));
      expect(route!.first, const LatLong(40.00342, -75.19768));
    });

    test('malformed or non-OK responses give null', () {
      final good = FakeRouteService.wiggle(controls);
      expect(RouteService.parseResponse(200, okBody(good)), hasLength(5));
      for (final r in <List<Object>>[
        [500, okBody(good)],
        [404, 'Not found'],
        [200, 'not json'],
        [200, '[]'],
        [200, '{"code":"NoRoute","routes":[]}'],
        [200, '{"code":"Ok"}'],
        [200, '{"code":"Ok","routes":[]}'],
        [200, '{"code":"Ok","routes":[42]}'],
        [200, '{"code":"Ok","routes":[{"geometry":7}]}'],
        [200, '{"code":"Ok","routes":[{"geometry":"!!garbage"}]}'],
      ]) {
        expect(RouteService.parseResponse(r[0] as int, r[1] as String), isNull,
            reason: '$r');
      }
    });

    test('fetch errors and bad status surface as null via routeFor', () async {
      final result = await http.runWithClient(
          () => RouteService.routeFor(RouteService(), 'e1', controls),
          () => MockClient((req) async => http.Response('oops', 503)));
      expect(result, isNull);
      final thrown = await http.runWithClient(
          () => RouteService.routeFor(RouteService(), 'e1', controls),
          () => MockClient((req) async => throw const SocketException('no')));
      expect(thrown, isNull);
    });

    test('under flutter test the default service makes no requests', () async {
      expect(RouteService.factory(), isA<NoRouteService>());
      expect(await NoRouteService().fetchRoute(controls), isNull);
    });
  });

  // AC6 (intent 0014)
  group('request URL', () {
    setUp(useMockServerForTests);

    test('built from control lat/long only', () async {
      final url = RouteService.requestUrl(controls);
      expect(url.host, RouteService.routerHost);
      expect(url.pathSegments.last,
          '-75.197683,40.003422;-75.030500,40.375330;-75.143969,40.986279');
      expect(url.queryParameters.keys.toSet(),
          {'overview', 'geometries', 'steps'});
    });

    test('no rider ID, event ID, name or any other event field', () async {
      final event = (await mockEvents())[1];
      final coords = [for (final c in event.controls) LatLong(c.lat, c.long)];
      final url = RouteService.requestUrl(coords).toString();
      for (final field in [
        event.eventID,
        event.name,
        event.regionID,
        event.organizerName,
        event.checkinPostURL,
        '12345',
        for (final c in event.controls) c.name,
      ]) {
        expect(url, isNot(contains(field)), reason: field);
      }
      // Only numbers, commas and semicolons in the coordinate segment.
      expect(
          Uri.parse(url).pathSegments.last, matches(RegExp(r'^[-0-9.,;]+$')));
    });
  });

  // AC8 (intent 0014)
  group('cache', () {
    test('same event and controls: one router call', () async {
      final fake = FakeRouteService();
      final a = await RouteService.routeFor(fake, 'e1', controls);
      final b = await RouteService.routeFor(fake, 'e1', controls);
      expect(fake.calls, 1);
      expect(b, a);
    });

    test('changed control set or other event: a new call', () async {
      final fake = FakeRouteService();
      await RouteService.routeFor(fake, 'e1', controls);
      await RouteService.routeFor(fake, 'e1', controls.take(2).toList());
      await RouteService.routeFor(fake, 'e2', controls);
      expect(fake.calls, 3);
    });

    test('failures are not cached: a later call retries', () async {
      var fail = true;
      final fake = FakeRouteService(
          answer: (c) async => fail ? null : FakeRouteService.wiggle(c));
      expect(await RouteService.routeFor(fake, 'e1', controls), isNull);
      fake.answer = (c) async => throw StateError('boom');
      expect(await RouteService.routeFor(fake, 'e1', controls), isNull);
      fake.answer = (c) async => const [LatLong(40, -75)]; // too short
      expect(await RouteService.routeFor(fake, 'e1', controls), isNull);
      fail = false;
      fake.answer = (c) async => FakeRouteService.wiggle(c);
      expect(await RouteService.routeFor(fake, 'e1', controls), isNotNull);
      expect(fake.calls, 4);
      expect(RouteService.cache, hasLength(1));
    });

    test('a timeout gives null', () async {
      final fake =
          FakeRouteService(answer: (c) => Completer<List<LatLong>?>().future);
      final r = await RouteService.routeFor(fake, 'e1', controls,
          timeout: const Duration(milliseconds: 10));
      expect(r, isNull);
      expect(RouteService.cache, isEmpty);
    });
  });
}
