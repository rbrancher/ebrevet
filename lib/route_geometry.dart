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

// Pure-Dart route geometry (intent 0009). No Flutter imports, so the map
// slice can reuse the same projection and fitting.

import 'dart:math' as math;

/// A latitude/longitude pair in degrees, e.g. from a [Control].
class LatLong {
  final double lat, long;
  const LatLong(this.lat, this.long);

  @override
  bool operator ==(Object other) =>
      other is LatLong && other.lat == lat && other.long == long;

  @override
  int get hashCode => Object.hash(lat, long);

  @override
  String toString() => '($lat, $long)';
}

/// Axis-aligned box in projected (Web Mercator) metres, y increasing south.
class ProjectedBox {
  final double minX, minY, maxX, maxY;
  const ProjectedBox(this.minX, this.minY, this.maxX, this.maxY);

  double get width => maxX - minX;
  double get height => maxY - minY;

  bool contains(math.Point<double> p) =>
      p.x >= minX && p.x <= maxX && p.y >= minY && p.y <= maxY;
}

/// The drawable shape of a route: the usable control points in control
/// order, projected with spherical Web Mercator (EPSG:3857), plus a padded
/// bounding box covering them.
class RouteGeometry {
  /// WGS84 semi-major axis used by EPSG:3857.
  static const double earthRadius = 6378137.0;

  /// Web Mercator latitude limit; points beyond it cannot be projected.
  static const double maxLatitude = 85.05112878;

  /// Padding on each side, as a fraction of the larger box dimension.
  static const double defaultPadFraction = 0.1;

  /// Start and finish closer than this (metres on the ground) form a loop.
  static const double loopTolerance = 250;

  /// Usable points in control order, as given (degrees).
  final List<LatLong> latLongs;

  /// [latLongs] projected to Web Mercator metres (y increasing south, so
  /// north is up on screen).
  final List<math.Point<double>> points;

  /// Bounding box of [points], padded by [padFraction] on every side.
  final ProjectedBox paddedBounds;

  final double padFraction;

  RouteGeometry._(
      this.latLongs, this.points, this.paddedBounds, this.padFraction);

  /// Builds the geometry from controls' coordinates in control order.
  /// Points with non-finite coordinates, out-of-range lat/long, or exactly
  /// 0,0 are skipped.
  factory RouteGeometry.fromLatLongs(Iterable<LatLong> controls,
      {double padFraction = defaultPadFraction}) {
    final usable = [
      for (final c in controls)
        if (isUsable(c)) c
    ];
    final points = [for (final c in usable) project(c)];

    var minX = 0.0, minY = 0.0, maxX = 0.0, maxY = 0.0;
    if (points.isNotEmpty) {
      minX = maxX = points.first.x;
      minY = maxY = points.first.y;
      for (final p in points) {
        minX = math.min(minX, p.x);
        maxX = math.max(maxX, p.x);
        minY = math.min(minY, p.y);
        maxY = math.max(maxY, p.y);
      }
    }
    final pad = padFraction * math.max(maxX - minX, maxY - minY);
    return RouteGeometry._(
        usable,
        points,
        ProjectedBox(minX - pad, minY - pad, maxX + pad, maxY + pad),
        padFraction);
  }

  /// Whether [c] can be drawn.
  static bool isUsable(LatLong c) =>
      c.lat.isFinite &&
      c.long.isFinite &&
      c.lat.abs() <= maxLatitude &&
      c.long.abs() <= 180 &&
      !(c.lat == 0 && c.long == 0);

  /// Spherical Web Mercator (EPSG:3857) in metres, y negated (south-up)
  /// so it maps directly to screen coordinates.
  static math.Point<double> project(LatLong c) {
    final lambda = c.long * math.pi / 180;
    final phi = c.lat * math.pi / 180;
    final x = earthRadius * lambda;
    final y = earthRadius * math.log(math.tan(math.pi / 4 + phi / 2));
    return math.Point(x, -y);
  }

  /// Inverse of [project]: Web Mercator metres (y south) back to degrees.
  static LatLong unproject(math.Point<double> p) {
    final long = p.x / earthRadius * 180 / math.pi;
    final lat = (2 * math.atan(math.exp(-p.y / earthRadius)) - math.pi / 2) *
        180 /
        math.pi;
    return LatLong(lat, long);
  }

  /// South-west corner of [paddedBounds] in degrees, for fitting a Web
  /// Mercator map camera to the same box (intent 0010).
  LatLong get paddedSouthWest =>
      unproject(math.Point(paddedBounds.minX, paddedBounds.maxY));

  /// North-east corner of [paddedBounds] in degrees.
  LatLong get paddedNorthEast =>
      unproject(math.Point(paddedBounds.maxX, paddedBounds.minY));

  /// At least two usable points with a non-zero extent.
  bool get isDrawable =>
      points.length >= 2 && (paddedBounds.width > 0 || paddedBounds.height > 0);

  /// First and last usable points are within [loopTolerance] on the ground.
  bool get isLoop =>
      latLongs.length >= 2 &&
      groundDistance(latLongs.first, latLongs.last) <= loopTolerance;

  /// Great-circle distance in metres (haversine).
  static double groundDistance(LatLong a, LatLong b) {
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(b.lat - a.lat), dLong = rad(b.long - a.long);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(a.lat)) *
            math.cos(rad(b.lat)) *
            math.pow(math.sin(dLong / 2), 2);
    return 2 * earthRadius * math.asin(math.min(1, math.sqrt(h)));
  }

  /// [points] fitted into a [width] x [height] box with one uniform scale
  /// for x and y, centred, so the shape is never stretched.
  List<math.Point<double>> fit(double width, double height) {
    if (!isDrawable) return const [];
    final b = paddedBounds;
    // A straight N-S or E-W route has zero extent on one axis only; the
    // padding keeps both non-zero, but guard anyway.
    final sx = b.width > 0 ? width / b.width : double.infinity;
    final sy = b.height > 0 ? height / b.height : double.infinity;
    final scale = math.min(sx, sy);
    final dx = (width - b.width * scale) / 2;
    final dy = (height - b.height * scale) / 2;
    return [
      for (final p in points)
        math.Point(dx + (p.x - b.minX) * scale, dy + (p.y - b.minY) * scale)
    ];
  }
}
