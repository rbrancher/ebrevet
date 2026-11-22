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

// Google encoded polyline (precision 5), decoded by hand (intent 0014).
// Used for the feed's optional `route_polyline` and the router's geometry.

import 'route_geometry.dart';

class RoutePolyline {
  static const double _factor = 1e5; // precision 5

  /// Longest run of 5-bit chunks in one value (30 bits: enough for ±180°
  /// and safe with 32-bit bit operations on web); more is garbage.
  static const int _maxChunks = 6;

  /// The points of [encoded], or null when it is not a usable route:
  /// not a string, empty, garbage or truncated, a point outside valid
  /// lat/long ([RouteGeometry.isUsable]), or fewer than 2 points. Never
  /// throws.
  static List<LatLong>? decode(Object? encoded) {
    if (encoded is! String || encoded.isEmpty) return null;
    final values = <int>[];
    var i = 0;
    while (i < encoded.length) {
      var result = 0, shift = 0, chunks = 0;
      int b;
      do {
        if (i >= encoded.length || chunks >= _maxChunks) return null;
        b = encoded.codeUnitAt(i++) - 63;
        if (b < 0 || b > 63) return null;
        result |= (b & 0x1f) << shift;
        shift += 5;
        chunks++;
      } while (b >= 0x20);
      values.add((result & 1) != 0 ? ~(result >> 1) : result >> 1);
    }
    if (values.length.isOdd) return null;

    final points = <LatLong>[];
    var lat = 0, long = 0;
    for (var k = 0; k < values.length; k += 2) {
      lat += values[k];
      long += values[k + 1];
      final p = LatLong(lat / _factor, long / _factor);
      if (!RouteGeometry.isUsable(p)) return null;
      points.add(p);
    }
    return points.length >= 2 ? points : null;
  }

  /// Encodes [points] (for the mock router and tests).
  static String encode(Iterable<LatLong> points) {
    final out = StringBuffer();
    void value(int v) {
      var s = v < 0 ? ~(v << 1) : v << 1;
      while (s >= 0x20) {
        out.writeCharCode((0x20 | (s & 0x1f)) + 63);
        s >>= 5;
      }
      out.writeCharCode(s + 63);
    }

    var lat = 0, long = 0;
    for (final p in points) {
      final la = (p.lat * _factor).round(), lo = (p.long * _factor).round();
      value(la - lat);
      value(lo - long);
      lat = la;
      long = lo;
    }
    return out.toString();
  }
}
