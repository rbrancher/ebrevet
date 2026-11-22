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

// Road route between an event's controls from a public cycling router
// (intent 0014). Used only by the full-screen map, for events whose feed
// has no `route_polyline`. Only control coordinates are sent.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'route_geometry.dart';
import 'route_map.dart';
import 'route_polyline.dart';

class RouteService {
  /// Router base URL and cycling profile: the OSRM bicycle instance run by
  /// FOSSGIS (routing.openstreetmap.de; OSRM ignores the profile name in
  /// the path, the instance decides). It is a free public server with a
  /// usage policy: swap this for a hosted routing service if usage grows.
  static const String endpoint =
      'https://routing.openstreetmap.de/routed-bike/route/v1/driving';

  /// Host of [endpoint]; the mock server answers it with canned routes.
  static final String routerHost = Uri.parse(endpoint).host;

  /// Longest wait for the router.
  static const Duration timeout = Duration(seconds: 10);

  /// Identifies the app to the router (set where the platform allows it;
  /// browsers send their own).
  static const String userAgent = 'eBrevet (${RouteMap.userAgentPackageName})';

  /// The service the full-screen map uses when none is passed. Tests may
  /// replace it. Under `flutter test` it makes no requests.
  static RouteService Function() factory = defaultService;

  static RouteService defaultService() =>
      RouteMap.isFlutterTest ? NoRouteService() : RouteService();

  /// Routes found this session, by [cacheKey]. Failures are not kept.
  static final Map<String, List<LatLong>> cache = {};

  static String cacheKey(String eventID, List<LatLong> controls) =>
      '$eventID|${controls.map((c) => '${c.lat},${c.long}').join(';')}';

  /// Router request for [controls]: built from their lat/long only.
  static Uri requestUrl(List<LatLong> controls) {
    final coords = controls
        .map((c) => '${c.long.toStringAsFixed(6)},${c.lat.toStringAsFixed(6)}')
        .join(';');
    return Uri.parse(
        '$endpoint/$coords?overview=full&geometries=polyline&steps=false');
  }

  /// Road geometry of an OSRM route response, or null when the response is
  /// not OK or malformed. Never throws.
  static List<LatLong>? parseResponse(int statusCode, String body) {
    if (statusCode != 200) return null;
    try {
      final json = jsonDecode(body);
      if (json is! Map || json['code'] != 'Ok') return null;
      final routes = json['routes'];
      if (routes is! List || routes.isEmpty) return null;
      final route = routes.first;
      if (route is! Map) return null;
      return RoutePolyline.decode(route['geometry']);
    } catch (_) {
      return null;
    }
  }

  /// Road geometry through [controls] (ordered, usable), or null. The one
  /// injectable method: a read-only GET to [endpoint].
  Future<List<LatLong>?> fetchRoute(List<LatLong> controls) async {
    final response = await http
        .get(requestUrl(controls),
            headers: kIsWeb ? null : {'User-Agent': userAgent})
        .timeout(timeout);
    return parseResponse(response.statusCode, response.body);
  }

  /// The route for [eventID] through [controls], from [cache] or the
  /// router. Null when the router fails, throws, takes longer than
  /// [timeout] or gives fewer than 2 points. Never throws.
  static Future<List<LatLong>?> routeFor(
      RouteService service, String eventID, List<LatLong> controls,
      {Duration timeout = timeout}) async {
    final key = cacheKey(eventID, controls);
    final cached = cache[key];
    if (cached != null) return cached;
    try {
      final route = await service.fetchRoute(controls).timeout(timeout);
      if (route == null || route.length < 2) return null;
      return cache[key] = route;
    } catch (_) {
      return null;
    }
  }
}

/// Makes no requests and finds no route (the default under `flutter test`).
class NoRouteService extends RouteService {
  @override
  Future<List<LatLong>?> fetchRoute(List<LatLong> controls) async => null;
}
