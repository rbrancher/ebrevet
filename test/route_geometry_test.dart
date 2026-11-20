// Route geometry (intent 0009, slice a): usable points, Web Mercator
// projection, padding and uniform-scale fitting.

import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:ebrevet_card/route_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

LatLong ll(double lat, double long) => LatLong(lat, long);

double dist(math.Point<double> a, math.Point<double> b) => a.distanceTo(b);

void main() {
  group('AC1 (intent 0009)', () {
    test('points keep control order', () {
      final g = RouteGeometry.fromLatLongs([
        ll(40.0, -75.2),
        ll(40.4, -75.0),
        ll(41.0, -75.1),
        ll(40.8, -75.3),
      ]);
      expect(g.latLongs, [
        ll(40.0, -75.2),
        ll(40.4, -75.0),
        ll(41.0, -75.1),
        ll(40.8, -75.3),
      ]);
      // Projected order matches: x follows longitude, y goes up (smaller)
      // going north.
      expect(g.points[1].x, greaterThan(g.points[0].x));
      expect(g.points[2].y, lessThan(g.points[1].y));
      expect(g.points[3].x, lessThan(g.points[0].x));
    });

    test('uses spherical Web Mercator (EPSG:3857)', () {
      // Known EPSG:3857 values (metres).
      final p = RouteGeometry.project(ll(40.0, -75.0));
      expect(p.x, closeTo(-8348961.81, 0.1));
      expect(-p.y, closeTo(4865942.28, 0.1));
      final o = RouteGeometry.project(ll(0.0001, 0));
      expect(o.x, 0);
    });

    test('padding is applied and every point lies inside the padded box', () {
      final g = RouteGeometry.fromLatLongs(
          [ll(40.0, -75.2), ll(40.4, -75.0), ll(41.0, -75.1)]);
      final xs = g.points.map((p) => p.x), ys = g.points.map((p) => p.y);
      final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
      final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
      final pad =
          RouteGeometry.defaultPadFraction * math.max(maxX - minX, maxY - minY);
      expect(pad, greaterThan(0));
      final b = g.paddedBounds;
      expect(b.minX, closeTo(minX - pad, 1e-6));
      expect(b.maxX, closeTo(maxX + pad, 1e-6));
      expect(b.minY, closeTo(minY - pad, 1e-6));
      expect(b.maxY, closeTo(maxY + pad, 1e-6));
      for (final p in g.points) {
        expect(b.contains(p), isTrue);
        expect(p.x, greaterThan(b.minX));
        expect(p.x, lessThan(b.maxX));
        expect(p.y, greaterThan(b.minY));
        expect(p.y, lessThan(b.maxY));
      }
      // Fitted points also stay inside the target box.
      for (final p in g.fit(160, 90)) {
        expect(p.x, inInclusiveRange(0, 160));
        expect(p.y, inInclusiveRange(0, 90));
      }
    });

    test('a start-equals-finish loop keeps both points', () {
      final g = RouteGeometry.fromLatLongs([
        ll(40.0034, -75.1977),
        ll(40.3753, -75.0305),
        ll(40.9863, -75.1440),
        ll(40.0034, -75.1977),
      ]);
      expect(g.points, hasLength(4));
      expect(g.points.first, g.points.last);
      expect(g.isLoop, isTrue);
      expect(g.isDrawable, isTrue);
    });

    test('a point-to-point route is not a loop', () {
      final g = RouteGeometry.fromLatLongs([ll(40.0, -75.2), ll(40.5, -75.2)]);
      expect(g.isLoop, isFalse);
    });

    test('invalid points are dropped', () {
      final g = RouteGeometry.fromLatLongs([
        ll(40.0, -75.2),
        ll(double.nan, -75.0),
        ll(40.2, double.infinity),
        ll(91, -75.0),
        ll(-89, -75.0), // beyond Web Mercator's latitude limit
        ll(40.3, 181),
        ll(0, 0),
        ll(40.4, -75.1),
      ]);
      expect(g.latLongs, [ll(40.0, -75.2), ll(40.4, -75.1)]);
      expect(g.points, hasLength(2));
      // 0 latitude or 0 longitude alone is still valid.
      expect(RouteGeometry.isUsable(ll(0, -75)), isTrue);
      expect(RouteGeometry.isUsable(ll(40, 0)), isTrue);
    });

    test(
        'N-S and E-W legs of equal ground length keep equal length in a '
        '16:9 box (uniform scale)', () {
      // L-shaped route: A -> B due north, B -> C due east, both ~11 km.
      const lat = 40.0, dLat = 0.1;
      final b = ll(lat + dLat, -75.0);
      final a = ll(lat, -75.0);
      // Same ground length east-west at B's latitude.
      final dLong = dLat / math.cos((lat + dLat) * math.pi / 180);
      final c = ll(lat + dLat, -75.0 + dLong);
      final ns = RouteGeometry.groundDistance(a, b);
      final ew = RouteGeometry.groundDistance(b, c);
      expect(ew / ns, closeTo(1, 0.005));

      final g = RouteGeometry.fromLatLongs([a, b, c]);
      for (final box in const [Size(160, 90), Size(90, 160), Size(400, 160)]) {
        final f = g.fit(box.width, box.height);
        expect(dist(f[0], f[1]) / dist(f[1], f[2]), closeTo(1, 0.01),
            reason: 'box $box');
      }
      // Centred: the padded box is centred in the target on its free axis.
      final f = g.fit(160, 90);
      final scale = 90 / g.paddedBounds.height;
      final left = (160 - g.paddedBounds.width * scale) / 2;
      expect(f[0].x,
          closeTo(left + (g.points[0].x - g.paddedBounds.minX) * scale, 1e-9));
    });

    test('mock feed events are drawable', () async {
      useMockServerForTests();
      for (final e in await mockEvents()) {
        final g = RouteGeometry.fromLatLongs(
            e.controls.map((c) => LatLong(c.lat, c.long)));
        expect(g.points, hasLength(e.controls.length), reason: e.name);
        expect(g.isDrawable, isTrue, reason: e.name);
      }
    });
  });

  group('AC2 (intent 0009): not drawable', () {
    test('a single control', () {
      final g = RouteGeometry.fromLatLongs([ll(40.0, -75.2)]);
      expect(g.isDrawable, isFalse);
      expect(g.fit(160, 90), isEmpty);
    });

    test('no controls', () {
      expect(RouteGeometry.fromLatLongs([]).isDrawable, isFalse);
    });

    test('all-invalid controls', () {
      final g = RouteGeometry.fromLatLongs(
          [ll(0, 0), ll(double.nan, 1), ll(100, 10), ll(40, -200)]);
      expect(g.points, isEmpty);
      expect(g.isDrawable, isFalse);
    });

    test('one usable point among invalid ones', () {
      final g = RouteGeometry.fromLatLongs([ll(0, 0), ll(40.0, -75.2)]);
      expect(g.isDrawable, isFalse);
    });

    test('identical points (zero extent)', () {
      final g = RouteGeometry.fromLatLongs(
          [ll(40.0, -75.2), ll(40.0, -75.2), ll(40.0, -75.2)]);
      expect(g.points, hasLength(3));
      expect(g.isDrawable, isFalse);
      expect(g.fit(160, 90), isEmpty);
    });
  });
}
