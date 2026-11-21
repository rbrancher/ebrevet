// Helpers for responsive grid tests (intent 0012).

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sets the test window to [width] x [height] logical pixels.
void setSurface(WidgetTester tester, double width, [double height = 900]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
}

/// Rects of the rendered (onstage) widgets matched by [cards].
List<Rect> rectsOf(WidgetTester tester, Finder cards) => [
      for (final e in cards.evaluate())
        (e.renderObject! as RenderBox).localToGlobal(Offset.zero) &
            (e.renderObject! as RenderBox).size
    ];

/// Cards in the first row: those sharing the smallest top offset.
int cardsPerRow(WidgetTester tester, Finder cards) {
  final tops = rectsOf(tester, cards).map((r) => r.top).toList();
  expect(tops, isNotEmpty);
  final first = tops.reduce((a, b) => a < b ? a : b);
  return tops.where((t) => (t - first).abs() < 0.5).length;
}

/// Fails if any two rects overlap.
void expectNoOverlap(List<Rect> rects) {
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      final o = rects[i].intersect(rects[j]);
      expect(o.width <= 0 || o.height <= 0, isTrue,
          reason: 'cards $i ${rects[i]} and $j ${rects[j]} overlap');
    }
  }
}
