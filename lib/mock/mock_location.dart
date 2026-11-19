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
