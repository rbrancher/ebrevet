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

// A small, static drawing of a route's shape through its controls
// (intent 0009). Drawn locally: no tiles, no network.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'control.dart';
import 'route_geometry.dart';

/// Kinds of marker drawn on a [RouteSketch].
enum SketchMarker { start, finish, startFinish, intermediate }

class RouteSketch extends StatelessWidget {
  /// Fixed width:height so cards do not change height.
  static const double aspectRatio = 5 / 2;

  final List<Control> controls;

  const RouteSketch({super.key, required this.controls});

  /// Screen-reader label; [controlCount] is the event's control count.
  static String semanticsLabel(int controlCount) =>
      'Sketch of the route with $controlCount controls';

  RouteGeometry get geometry =>
      RouteGeometry.fromLatLongs(controls.map((c) => LatLong(c.lat, c.long)));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final geometry = this.geometry;
    return Semantics(
      container: true,
      image: true,
      label: semanticsLabel(controls.length),
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: geometry.isDrawable
                ? CustomPaint(
                    painter: RouteSketchPainter.themed(geometry, scheme),
                    child: const SizedBox.expand(),
                  )
                : Center(
                    child: Icon(Icons.route, color: scheme.onSurfaceVariant),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Draws the route line and markers. Shared by [RouteSketch] (points fitted
/// into the canvas) and the map overlay in `route_map.dart` (intent 0010),
/// which passes [screenPoints] already projected by the map camera.
class RouteSketchPainter extends CustomPainter {
  final RouteGeometry geometry;
  final Color line, casing, start, finish, intermediate;

  /// Screen positions of [RouteGeometry.points], in the same order. When
  /// null the points are fitted into the canvas with [RouteGeometry.fit].
  final List<Offset>? screenPoints;

  /// Screen positions of a road route (intent 0014). When given (at least
  /// 2 points) the line follows them instead of joining the controls with
  /// straight segments; the markers stay on the controls, above the line.
  final List<Offset>? routePoints;

  RouteSketchPainter({
    required this.geometry,
    required this.line,
    required this.casing,
    required this.start,
    required this.finish,
    required this.intermediate,
    this.screenPoints,
    this.routePoints,
  });

  /// The route colors, from the theme's [ColorScheme] only.
  factory RouteSketchPainter.themed(RouteGeometry geometry, ColorScheme scheme,
          {List<Offset>? screenPoints, List<Offset>? routePoints}) =>
      RouteSketchPainter(
        geometry: geometry,
        line: scheme.primary,
        casing: scheme.surface,
        start: scheme.tertiary,
        finish: scheme.onSurface,
        intermediate: scheme.onSurfaceVariant,
        screenPoints: screenPoints,
        routePoints: routePoints,
      );

  /// Marker kind for each usable point, in control order. A loop gets one
  /// combined start/finish marker on the first point and none on the last,
  /// instead of two overlapping markers.
  List<SketchMarker?> get markers {
    final n = geometry.points.length;
    if (n < 2) return const [];
    final loop = geometry.isLoop;
    return [
      loop ? SketchMarker.startFinish : SketchMarker.start,
      for (var i = 1; i < n - 1; i++) SketchMarker.intermediate,
      loop ? null : SketchMarker.finish,
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pts = screenPoints ??
        [
          for (final p in geometry.fit(size.width, size.height))
            Offset(p.x, p.y)
        ];
    if (pts.length < 2) return;

    final linePts =
        (routePoints != null && routePoints!.length >= 2) ? routePoints! : pts;
    final path = Path()..moveTo(linePts.first.dx, linePts.first.dy);
    for (final p in linePts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    Paint stroke(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, stroke(casing, 6));
    canvas.drawPath(path, stroke(line, 3));

    final fill = Paint()..style = PaintingStyle.fill;
    final ring = stroke(casing, 2);
    final kinds = markers;
    // Draw intermediates first so start/finish stay on top.
    for (var i = 0; i < kinds.length; i++) {
      if (kinds[i] == SketchMarker.intermediate) {
        canvas.drawCircle(pts[i], 3.5, fill..color = intermediate);
        canvas.drawCircle(pts[i], 3.5, ring);
      }
    }
    for (var i = 0; i < kinds.length; i++) {
      final p = pts[i];
      switch (kinds[i]) {
        case SketchMarker.start:
          canvas.drawCircle(p, 6, fill..color = start);
          canvas.drawCircle(p, 6, ring);
          break;
        case SketchMarker.finish:
          final r = Rect.fromCenter(center: p, width: 11, height: 11);
          canvas.drawRect(r, fill..color = finish);
          canvas.drawRect(r, ring);
          break;
        case SketchMarker.startFinish:
          // Finish square with the start dot inside it.
          final r = Rect.fromCenter(center: p, width: 15, height: 15);
          canvas.drawRect(r, fill..color = finish);
          canvas.drawRect(r, ring);
          canvas.drawCircle(p, 4.5, fill..color = start);
          break;
        case SketchMarker.intermediate:
        case null:
          break;
      }
    }
  }

  @override
  bool shouldRepaint(RouteSketchPainter oldDelegate) =>
      oldDelegate.geometry != geometry ||
      !listEquals(oldDelegate.screenPoints, screenPoints) ||
      !listEquals(oldDelegate.routePoints, routePoints) ||
      oldDelegate.line != line ||
      oldDelegate.casing != casing ||
      oldDelegate.start != start ||
      oldDelegate.finish != finish ||
      oldDelegate.intermediate != intermediate;
}
