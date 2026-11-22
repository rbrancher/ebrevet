// Fake router for tests (intent 0014): never touches the network.

import 'package:ebrevet_card/route_geometry.dart';
import 'package:ebrevet_card/route_service.dart';

/// Records every request and answers with [answer] (a road-like line
/// through the controls by default).
class FakeRouteService extends RouteService {
  final List<List<LatLong>> requests = [];
  Future<List<LatLong>?> Function(List<LatLong> controls) answer;

  FakeRouteService({Future<List<LatLong>?> Function(List<LatLong>)? answer})
      : answer = answer ?? ((c) async => wiggle(c));

  int get calls => requests.length;

  @override
  Future<List<LatLong>?> fetchRoute(List<LatLong> controls) {
    requests.add(controls);
    return answer(controls);
  }

  /// [controls] with a point off to the side between each pair.
  static List<LatLong> wiggle(List<LatLong> controls) => [
        for (var i = 0; i < controls.length; i++) ...[
          if (i > 0)
            LatLong((controls[i - 1].lat + controls[i].lat) / 2 + 0.01,
                (controls[i - 1].long + controls[i].long) / 2 - 0.01),
          controls[i],
        ]
      ];
}
