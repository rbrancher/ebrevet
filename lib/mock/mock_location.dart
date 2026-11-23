// Copyright (C) 2026 eBrevet autonomous AI-SDLC
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

// Fake GPS for mock mode. Defaults to the start control of the mock
// fixture's first event (Philadelphia), so a preview user can start that
// event and check in at its start control.

import 'package:geolocator/geolocator.dart';

class MockLocation {
  static const double defaultLatitude = 40.0034216;
  static const double defaultLongitude = -75.1976835;

  static double latitude = defaultLatitude;
  static double longitude = defaultLongitude;

  static void moveTo(double lat, double long) {
    latitude = lat;
    longitude = long;
  }

  static void reset() => moveTo(defaultLatitude, defaultLongitude);

  static Position get position => Position(
        latitude: latitude,
        longitude: longitude,
        timestamp: DateTime.now(),
        accuracy: 5,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );
}
